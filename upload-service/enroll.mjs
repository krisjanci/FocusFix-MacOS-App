// FF: ENROLLMENT — make one private credential for an approved participant ID.
// Run locally, not on a participant's Mac. No Cloudflare/admin token is requested.
import { randomBytes, createHash } from "node:crypto";
import { uuid } from "./src/policy.mjs";
// Read the ID pasted after the command; reject anything that is not a UUID.
const id = (process.argv[2] ?? "").toLowerCase();
if (!uuid.test(id)) {
  console.error("Usage: node enroll.mjs PARTICIPANT-ID-FROM-THE-APP");
  process.exitCode = 1;
} else {
  // Generate a random secret; only its hash belongs in the database.
  const token = `${id}.${randomBytes(32).toString("hex")}`;
  const hash = createHash("sha256").update(token).digest("hex");
  // Print setup instructions, not an automatic database change. Keep this output private.
  console.log("Run this SQL in the private D1 console (rotates any previous credential for this ID):\n");
  console.log(`INSERT INTO participants(id, token_hash, revoked) VALUES ('${id}', '${hash}', 0) ON CONFLICT(id) DO UPDATE SET token_hash = excluded.token_hash, revoked = 0;`);
  console.log("\nSend ONLY this enrollment credential privately to the participant. Do not commit, screenshot or publish it:\n");
  console.log(token);
}
