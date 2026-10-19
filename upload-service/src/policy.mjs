// FF: QUOTAS — server-side participant limits, not an account-wide spending cap.
// Keep limits, SQL thresholds and the app's UploadPolicy/UI explanations in sync.
export const limits = Object.freeze({ seconds: 10800, bytes: 25 * 1024 * 1024,
  dailyBytes: 50 * 1024 * 1024, sessions: 30, attempts: 120 });
// Restrict IDs and fingerprints to the formats this protocol expects.
export const uuid = /^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/;
export const hashPattern = /^[0-9a-f]{64}$/;
// Name the UTC calendar day used by the shared quota counters.
export const dayFor = (now) => now.toISOString().slice(0, 10);
// Tell a quota-limited client how many seconds to wait until the next UTC day.
export const retryAfter = (now) => Math.max(60, Math.ceil((Date.parse(`${dayFor(now)}T00:00:00Z`) + 86400000 - now.getTime()) / 1000));
// Compute a one-way fingerprint to compare credentials or check transferred bytes.
export async function sha256(data) {
  return [...new Uint8Array(await crypto.subtle.digest("SHA-256", data))]
    .map((byte) => byte.toString(16).padStart(2, "0")).join("");
}

// Check declared session duration, ZIP size, session ID and checksum before reading data.
export function metadata(request, sessionID) {
  const secondsText = request.headers.get("X-Duration-Seconds") ?? "";
  const bytesText = request.headers.get("Content-Length") ?? "";
  const seconds = Number(secondsText), bytes = Number(bytesText);
  const hash = request.headers.get("X-Content-SHA256") ?? "";
  if (!uuid.test(sessionID) || !/^[1-9][0-9]*$/.test(secondsText) || !/^[1-9][0-9]*$/.test(bytesText)
      || !Number.isSafeInteger(seconds) || seconds > limits.seconds || !hashPattern.test(hash)) return null;
  if (!Number.isSafeInteger(bytes) || bytes > limits.bytes) return null;
  return { sessionID, seconds, bytes, hash };
}

// This conditional INSERT is one atomic SQLite statement, not a read-then-write
// counter in Worker memory. Concurrent requests cannot both spend the last quota.
export const reserveSQL = `
INSERT INTO uploads(participant_id, session_id, day, seconds, bytes, sha256)
SELECT ?, ?, ?, ?, ?, ?
WHERE (SELECT revoked FROM participants WHERE id = ?) = 0
  AND COALESCE((SELECT SUM(seconds) FROM uploads WHERE participant_id = ? AND day = ?), 0) + ? <= 10800
  AND COALESCE((SELECT SUM(bytes) FROM uploads WHERE participant_id = ? AND day = ?), 0) + ? <= 52428800
  AND (SELECT COUNT(*) FROM uploads WHERE participant_id = ? AND day = ?) < 30
ON CONFLICT(participant_id, session_id) DO NOTHING`;

// Supply values to the SQL placeholders in exactly their declared order.
export function reservationBindings(participant, day, meta) {
  return [participant, meta.sessionID, day, meta.seconds, meta.bytes, meta.hash,
    participant, participant, day, meta.seconds, participant, day, meta.bytes, participant, day];
}

// Count authenticated requests atomically, including retries and rejected metadata.
export const attemptsSQL = `
INSERT INTO attempts(participant_id, day, count) VALUES (?, ?, 1)
ON CONFLICT(participant_id, day) DO UPDATE SET count = count + 1 WHERE count < 120
RETURNING count`;

// Read a stream only up to its declared/allowed size; reject missing or extra bytes.
export async function readBounded(body, declaredBytes) {
  if (!body) throw new Error("missing body");
  const reader = body.getReader();
  const parts = [];
  let count = 0;
  try {
    while (true) {
      const { done, value } = await reader.read();
      if (done) break;
      count += value.byteLength;
      if (count > declaredBytes || count > limits.bytes) throw new Error("body too large");
      parts.push(value);
    }
    if (count !== declaredBytes) throw new Error("body length mismatch");
    const data = new Uint8Array(count);
    let offset = 0;
    for (const part of parts) { data.set(part, offset); offset += part.byteLength; }
    return data;
  } catch (error) {
    await reader.cancel().catch(() => {});
    throw error;
  } finally { reader.releaseLock(); }
}
