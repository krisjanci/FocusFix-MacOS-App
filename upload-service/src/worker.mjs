// FF: UPLOADS — the private bucket's gatekeeper, deployed as a Cloudflare Worker.
// No CSV data or participant credentials should be printed to logs here.
import { uuid, hashPattern, sha256, metadata, dayFor, retryAfter,
  reserveSQL, reservationBindings, attemptsSQL, readBounded } from "./policy.mjs";

// Return a small JSON reply that browsers/proxies must not cache.
function reply(status, value, headers = {}) {
  return Response.json(value, { status, headers: { "Cache-Control": "no-store", ...headers } });
}

export default {
  // Handle one upload: authorize, reserve quota, verify bytes, store once and confirm.
  async fetch(request, env) {
    // A deployed service remains closed until explicitly enabled by the researcher.
    if (env.UPLOADS_ENABLED !== "true") return reply(503, { error: "Uploads are not enabled." });
    const url = new URL(request.url);
    const match = /^\/v1\/sessions\/([0-9a-fA-F-]+)$/.exec(url.pathname);
    if (request.method !== "PUT" || !match || url.search) return reply(404, { error: "Not found." });
    if (url.protocol !== "https:") return reply(400, { error: "HTTPS required." });

    // FF: ENROLLMENT — an ID alone is not enough; require its private credential.
    const participant = request.headers.get("X-Participant-ID") ?? "";
    const authorization = request.headers.get("Authorization") ?? "";
    const token = authorization.startsWith("Bearer ") ? authorization.slice(7) : "";
    const parts = token.split(".");
    if (!uuid.test(participant) || parts.length !== 2 || parts[0] !== participant || !hashPattern.test(parts[1])) {
      return reply(401, { error: "Enrollment required." });
    }
    try {
      const digest = await sha256(new TextEncoder().encode(token));
      const enrolled = await env.DB.prepare("SELECT id FROM participants WHERE id = ? AND token_hash = ? AND revoked = 0")
        .bind(participant, digest).first();
      if (!enrolled) return reply(403, { error: "Enrollment invalid or revoked." });

      // FF: QUOTAS — use the server's UTC day, not a date supplied by the Mac.
      const now = new Date();
      const day = dayFor(now);
      const attempt = await env.DB.prepare(attemptsSQL).bind(participant, day).first();
      if (!attempt) return reply(429, { error: "Daily request limit." }, { "Retry-After": String(retryAfter(now)) });
      if (request.headers.get("Content-Type") !== "application/zip") return reply(415, { error: "ZIP required." });
      const meta = metadata(request, match[1].toLowerCase());
      if (!meta) return reply(413, { error: "Invalid metadata or session exceeds limits." });

      // Look up the reservation/receipt for this exact participant and session.
      const receiptQuery = () => env.DB.prepare("SELECT * FROM uploads WHERE participant_id = ? AND session_id = ?")
        .bind(participant, meta.sessionID).first();
      // A retry must describe the same bytes and duration, not replace existing data.
      const receiptMatches = (receipt) => receipt.sha256 === meta.hash && receipt.bytes === meta.bytes && receipt.seconds === meta.seconds;
      // Confirm the exact session/checksum the app is waiting for.
      const confirmed = () => reply(200, { stored: true, session_id: meta.sessionID, sha256: meta.hash });
      let receipt = await receiptQuery();
      if (receipt && !receiptMatches(receipt)) return reply(409, { error: "Session ID already reserved for different content." });
      if (receipt?.completed) return confirmed(); // Never reupload archived/deleted objects.

      // New uploads and retries must stay within daily incoming bytes and duration.
      // A reservation is charged before reading the body; interrupted uploads keep
      // their quota reservation and can retry without charging the session twice.
      if (!receipt) {
        await env.DB.prepare(reserveSQL).bind(...reservationBindings(participant, day, meta)).run();
        receipt = await receiptQuery();
      }
      if (!receipt) return reply(429, { error: "Daily session quota reached." }, { "Retry-After": String(retryAfter(now)) });
      if (!receiptMatches(receipt)) return reply(409, { error: "Session ID collision." });
      if (receipt.completed) return confirmed();

      // FF: STORAGE — one private object per session, grouped by participant ID.
      const key = `${participant}/${meta.sessionID}.zip`;
      // Recover a successful R2 write if the previous Worker stopped before D1 confirmation.
      const existing = await env.RECORDINGS.head(key);
      if (existing) {
        if (existing.size !== meta.bytes || existing.customMetadata?.sha256 !== meta.hash) {
          return reply(409, { error: "Stored object doesn't match this session." });
        }
      } else {
        // Bound memory use and reject truncated, non-ZIP or changed content.
        let body;
        try { body = await readBounded(request.body, meta.bytes); }
        catch { return reply(400, { error: "Incomplete or oversized upload." }); }
        if (body[0] !== 0x50 || body[1] !== 0x4b || body[2] !== 3 || body[3] !== 4) {
          return reply(422, { error: "Not a ZIP archive." });
        }
        if (await sha256(body) !== meta.hash) return reply(422, { error: "Checksum mismatch." });
        // Recheck revocation before writing. In-flight uploads cannot be recalled
        // with certainty; disclose that to participants in the app.
        const active = await env.DB.prepare("SELECT id FROM participants WHERE id = ? AND revoked = 0")
          .bind(participant).first();
        if (!active) return reply(403, { error: "Enrollment revoked." });
        // Conditional creation prevents simultaneous retries from replacing a ZIP.
        const stored = await env.RECORDINGS.put(key, body, {
          onlyIf: new Headers({ "If-None-Match": "*" }),
          sha256: meta.hash,
          httpMetadata: { contentType: "application/zip" },
          customMetadata: { sha256: meta.hash, participant_id: participant,
            session_id: meta.sessionID, duration_seconds: String(meta.seconds), upload_day_utc: receipt.day }
        });
        if (!stored) {
          const concurrent = await env.RECORDINGS.head(key);
          if (concurrent?.size !== meta.bytes || concurrent?.customMetadata?.sha256 !== meta.hash) {
            return reply(409, { error: "Concurrent upload conflict." });
          }
        }
      }
      // Keep this receipt even after a researcher downloads/deletes the R2 object.
      await env.DB.prepare("UPDATE uploads SET completed = 1 WHERE participant_id = ? AND session_id = ? AND sha256 = ?")
        .bind(participant, meta.sessionID, meta.hash).run();
      return confirmed();
    } catch {
      // Never log request bodies, tokens, headers or the contents of survey files.
      return reply(503, { error: "Upload temporarily unavailable. Keep the local copy and retry." });
    }
  }
};
