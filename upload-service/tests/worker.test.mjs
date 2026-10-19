import test from "node:test";
import assert from "node:assert/strict";
import { DatabaseSync } from "node:sqlite";
import { readFileSync } from "node:fs";
import worker from "../src/worker.mjs";
import { sha256, reserveSQL, reservationBindings, limits, retryAfter } from "../src/policy.mjs";

const participant = "aaaaaaaa-aaaa-4aaa-aaaa-aaaaaaaaaaaa";
const session = (n) => `bbbbbbbb-bbbb-4bbb-bbbb-${String(n).padStart(12, "0")}`;
const credential = `${participant}.${"a".repeat(64)}`;
// Fake ZIP bytes, not personal recordings. Archive structure is tested by Swift.
const body = new Uint8Array([0x50, 0x4b, 3, 4, 1, 2, 3]);

async function setup() {
  const sql = new DatabaseSync(":memory:");
  sql.exec(readFileSync(new URL("../schema.sql", import.meta.url), "utf8"));
  sql.prepare("INSERT INTO participants(id, token_hash) VALUES (?, ?)")
    .run(participant, await sha256(new TextEncoder().encode(credential)));
  const objects = new Map();
  const counters = { puts: 0, heads: 0 };
  const env = {
    UPLOADS_ENABLED: "true",
    DB: { prepare(query) {
      let args = [];
      return { bind(...values) { args = values; return this; },
        async first() { return sql.prepare(query).get(...args) ?? null; },
        async run() { return sql.prepare(query).run(...args); } };
    } },
    RECORDINGS: {
      async head(key) { counters.heads++; return objects.get(key) ?? null; },
      async put(key, value, options) {
        assert.equal(options.onlyIf.get("If-None-Match"), "*");
        counters.puts++;
        if (objects.has(key)) return null;
        const stored = { size: value.byteLength, customMetadata: options.customMetadata };
        objects.set(key, stored);
        return stored;
      }
    }
  };
  async function request(n = 1, seconds = 3600, extra = {}) {
    return new Request(`https://test.workers.dev/v1/sessions/${session(n)}`, {
      method: "PUT", headers: { "Authorization": `Bearer ${credential}`, "X-Participant-ID": participant,
        "X-Duration-Seconds": String(seconds), "Content-Length": String(body.byteLength),
        "Content-Type": "application/zip", "X-Content-SHA256": await sha256(body), ...extra }, body
    });
  }
  return { env, sql, objects, counters, request };
}

test("closed service, missing/wrong/revoked credentials never reach R2", async () => {
  const s = await setup();
  s.env.UPLOADS_ENABLED = "false";
  assert.equal((await worker.fetch(await s.request(), s.env)).status, 503);
  s.env.UPLOADS_ENABLED = "true";
  assert.equal((await worker.fetch(await s.request(1, 60, { Authorization: "" }), s.env)).status, 401);
  assert.equal((await worker.fetch(await s.request(1, 60, { Authorization: `Bearer ${participant}.${"b".repeat(64)}` }), s.env)).status, 403);
  s.sql.prepare("UPDATE participants SET revoked = 1").run();
  assert.equal((await worker.fetch(await s.request(), s.env)).status, 403);
  assert.deepEqual(s.counters, { puts: 0, heads: 0 });
});

test("uploads exactly once; a duplicate after cloud deletion is acknowledged, not recreated", async () => {
  const s = await setup();
  const first = await worker.fetch(await s.request(), s.env);
  assert.equal(first.status, 200);
  assert.equal((await first.json()).session_id, session(1));
  assert.equal(s.counters.puts, 1);
  s.objects.clear();
  assert.equal((await worker.fetch(await s.request(), s.env)).status, 200);
  assert.equal(s.counters.puts, 1);
  assert.equal(s.sql.prepare("SELECT SUM(seconds) AS total FROM uploads").get().total, 3600);
});

test("three 60-minute sessions fit; fourth waits; >180 minute session is rejected", async () => {
  const s = await setup();
  for (let i = 1; i <= 3; i++) assert.equal((await worker.fetch(await s.request(i), s.env)).status, 200);
  const fourth = await worker.fetch(await s.request(4), s.env);
  assert.equal(fourth.status, 429);
  assert.ok(Number(fourth.headers.get("Retry-After")) >= 60);
  assert.equal((await worker.fetch(await s.request(5, 10801), s.env)).status, 413);
  assert.equal(s.counters.puts, 3);
});

test("concurrent sessions cannot overspend quota; concurrent duplicates use one reservation", async () => {
  const s = await setup();
  const responses = await Promise.all([1, 2, 3, 4].map(async n => worker.fetch(await s.request(n), s.env)));
  assert.equal(responses.filter(r => r.status === 200).length, 3);
  assert.equal(responses.filter(r => r.status === 429).length, 1);
  assert.equal(s.sql.prepare("SELECT SUM(seconds) AS total FROM uploads").get().total, 10800);
  const t = await setup();
  const duplicates = await Promise.all([1, 1].map(async n => worker.fetch(await t.request(n), t.env)));
  assert.ok(duplicates.every(r => r.status === 200));
  assert.equal(t.sql.prepare("SELECT COUNT(*) AS total FROM uploads").get().total, 1);
});

test("checksum/size/content-type mismatches never store data; conflicting retry cannot replace data", async () => {
  const s = await setup();
  assert.equal((await worker.fetch(await s.request(1, 60, { "X-Content-SHA256": "0".repeat(64) }), s.env)).status, 422);
  assert.equal((await worker.fetch(await s.request(2, 60, { "Content-Length": "1" }), s.env)).status, 400);
  assert.equal((await worker.fetch(await s.request(3, 60, { "Content-Type": "text/plain" }), s.env)).status, 415);
  assert.equal((await worker.fetch(await s.request(4, 60, { "Content-Length": String(limits.bytes + 1) }), s.env)).status, 413);
  assert.equal(s.counters.puts, 0);
  assert.equal((await worker.fetch(await s.request(5), s.env)).status, 200);
  assert.equal((await worker.fetch(await s.request(5, 1), s.env)).status, 409);
  assert.equal(s.counters.puts, 1);
});

test("R2 failure retries with the same reservation; receipt failure recovers without a second PUT", async () => {
  const s = await setup();
  const originalPut = s.env.RECORDINGS.put;
  s.env.RECORDINGS.put = async () => { throw new Error("synthetic R2 failure"); };
  assert.equal((await worker.fetch(await s.request(), s.env)).status, 503);
  s.env.RECORDINGS.put = originalPut;
  assert.equal((await worker.fetch(await s.request(), s.env)).status, 200);
  s.sql.prepare("UPDATE uploads SET completed = 0").run(); // Simulate lost D1 completion.
  assert.equal((await worker.fetch(await s.request(), s.env)).status, 200);
  assert.equal(s.counters.puts, 1);
  assert.equal(s.sql.prepare("SELECT COUNT(*) AS total FROM uploads").get().total, 1);
});

test("SQL enforces bytes, session count and UTC boundary independently of client", async () => {
  const s = await setup();
  const day = "2026-10-19";
  const reserve = (n, bytes = limits.bytes, date = day) => s.sql.prepare(reserveSQL).run(
    ...reservationBindings(participant, date, { sessionID: session(n), seconds: 1, bytes, hash: "a".repeat(64) }));
  assert.equal(reserve(1).changes, 1);
  assert.equal(reserve(2).changes, 1);
  assert.equal(reserve(3, 1).changes, 0);
  assert.equal(reserve(3, 1, "2026-10-20").changes, 1);
  s.sql.exec("DELETE FROM uploads");
  for (let i = 1; i <= 30; i++) assert.equal(reserve(i, 1).changes, 1);
  assert.equal(reserve(31, 1).changes, 0);
  assert.equal(retryAfter(new Date("2026-10-19T12:00:00Z")), 43200);
  assert.equal(retryAfter(new Date("2026-10-19T23:59:59Z")), 60);
});

test("120 daily authenticated requests maximum, with no R2 operations after exhaustion", async () => {
  const s = await setup();
  for (let i = 0; i < 120; i++) {
    assert.equal((await worker.fetch(await s.request(1, 60, { "Content-Type": "text/plain" }), s.env)).status, 415);
  }
  assert.equal((await worker.fetch(await s.request(), s.env)).status, 429);
  assert.equal(s.counters.heads, 0);
});
