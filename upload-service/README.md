# FocusFix uploads

This is the small receiver for my macOS app, not a public download website.
It puts one ZIP per session in my **private `focusfix-mldata` R2 bucket**.
The app still works locally without it. Creating the bucket doesn't deploy this service.

## What is ready

- The code and local tests are here. Nothing has been deployed to my Cloudflare account yet.
- The bucket binding already says `focusfix-mldata`. The D1 database ID and the app's
  Worker URL still need to be filled in.
- Uploads default to disabled on the server and off in the app. I need to finish the
  study consent/storage plan before enrolling participants. I can use dummy data to test.
- This is a research pilot, not an anonymous public upload endpoint. No public signup.
  I issue one credential per enrolled participant ID and can revoke it.
- R2 holds ZIP files. D1 holds credential hashes, quota reservations and upload receipts,
  not CSV contents. These services have separate usage limits from R2 storage.

## Connect Cloudflare

Use a recent Node.js LTS (22.13+ for the local tests) and run these commands from
this `upload-service` folder. `npx wrangler@4` downloads Cloudflare's deployment CLI;
log in yourself in the browser, don't paste your Cloudflare password or API token into chat.

1. Keep the R2 bucket private. Don't enable an `r2.dev` public URL or attach a public domain.
   Use Standard storage, not Infrequent Access. Enable MFA on my Cloudflare account.

2. Sign in and create the small upload-control database:

   ```sh
   npx wrangler@4 login
   npx wrangler@4 d1 create focusfix-upload-control
   ```

   Copy the returned `database_id` into `wrangler.jsonc`. The ID isn't a secret.
   Review the requested permissions and the account selected by Wrangler.

3. Create the database tables:

   ```sh
   npx wrangler@4 d1 execute focusfix-upload-control --remote --file=schema.sql
   ```

4. Deploy with the service still disabled:

   ```sh
   npx wrangler@4 deploy
   ```

   Cloudflare prints a URL like `https://focusfix-uploads.MY-SUBDOMAIN.workers.dev`.
   I don't need to buy a domain. This isn't the R2 S3 endpoint or a public bucket URL.

5. In `FocusFix/FocusFix/UploadTransport.swift`, set `UploadConfiguration.serviceURL`
   to that exact HTTPS origin (no `/v1/...` suffix), then rebuild the app.
   Changing the origin in a later build turns sharing off and requires fresh opt-in.

6. For my dummy-data test, set `UPLOADS_ENABLED` to `"true"` in `wrangler.jsonc`
   and deploy again. That doesn't make the bucket public; credentials are still required.
   Keep real participants out until my consent and institutional approvals are ready.
   Setting it back to `"false"` and redeploying is the server-wide kill switch.

## Enroll a participant

1. Open the app's account icon and copy the participant ID.
2. On **my** computer, run:

   ```sh
   node enroll.mjs PARTICIPANT-ID-FROM-THE-APP
   ```

3. It prints a SQL statement containing only the ID and a credential **hash**. Run that
   statement in Cloudflare → D1 → `focusfix-upload-control` → Console.
4. It also prints a private `ID.secret` enrollment credential. Give that only to the
   matching participant through an approved private channel, not GitHub or a public issue.
   Generating another credential doesn't change the server until its SQL is applied.
5. The participant pastes it into **Research enrollment → Save enrollment**, then
   explicitly turns on sharing after completing the study's consent process.
6. Only new sessions started under that opt-in are eligible. Old sessions and sessions
   recorded before enrollment don't get uploaded later. Opt-out invalidates pending
   eligibility; turning sharing back on doesn't restart old uploads.

The app stores its ID and credential in macOS Keychain, never in the session ZIP.
Its random ID is also in new `session.json` files, so I can group all five CSVs by session
and participant without repeating the ID on every event row. It identifies this
installation, not a verified human. A second Mac has a new ID; I must manage that during
enrollment rather than counting it as a second participant or issuing unlimited IDs.
Don't clear the participant's Keychain to reset quotas. Local recordings continue if
Keychain is unavailable, but identity/sharing are unavailable until that is resolved.

To revoke a credential, use the D1 console (replace the placeholder with the actual ID):

```sql
UPDATE participants SET revoked = 1 WHERE id = 'PARTICIPANT-ID';
```

This stops subsequent authorized requests; it doesn't recall data already received.
Issuing a replacement credential for the same ID preserves the quotas and receipts.

## Limits and retries

- 180 minutes of **total elapsed session time, including breaks**, admitted per
  participant per UTC calendar day. This is upload-admission day, not recording day
  or the Mac's time zone. Duration is rounded up to a whole second.
- Whole sessions only. After 120 minutes, a 90-minute session waits for the next UTC
  day. A session longer than 180 minutes is kept locally, not truncated.
- At most 25 MiB per ZIP, 50 MiB of newly admitted ZIPs/day and 30 newly admitted
  sessions/day. The app also refuses to package more than 100 MiB of raw files.
- At most 120 authenticated attempts/day, including retries and invalid requests.
  The app uses a persistent queue, delayed retries (5 minutes or longer), and respects
  the server's next-UTC-day response. Pending work resumes while the app is running;
  quitting doesn't keep a background uploader alive. It resumes on next launch.
- The database reserves quota atomically before receiving a new ZIP. Failed transfers
  keep their reservation; an identical retry uses that reservation, including after
  midnight. The limit bounds newly admitted data, not every byte retransmitted on the
  network. Clock manipulation on the Mac cannot reset the server's counters.
- A modified client could lie about session duration. Hard byte/session/request caps
  provide separate protection. For a wide public launch, add edge rate limiting and
  monitor D1/Worker usage too. R2 limits alone don't protect every service from abuse.
- No admin token is embedded in the app. Redirects are refused so uploads cannot
  silently change host. Enrollment credentials can be revoked server-side.
- The ZIP is allowlisted to the five CSVs and `session.json`, with no symlinks or
  unrelated files. SHA-256 verifies the transfer. The service checks size, ZIP magic
  and checksum; it does not unzip or certify the research content. Treat downloads
  as untrusted files and don't automatically execute anything from them.
- D1 receipts make retries idempotent. Same session + different contents is rejected.
  A completed receipt is kept even if I later archive/delete its ZIP from R2, so an
  uncertain client retry won't recreate deleted data.
- Local files are not deleted after upload. Deleting a local session cancels queued
  work, but does not delete cloud or exported copies. Opt-out cancels pending transfers;
  an in-flight transfer might already have reached Cloudflare.

## Download recordings

Cloudflare → R2 → `focusfix-mldata`. Files are grouped as:

```text
participant-id/
    session-id.zip
```

Download a ZIP, unzip it, then analyze the CSVs. For batch downloads I can later use
`rclone` with a separate researcher-only read credential. Don't put that credential
in the app. Verify downloads and make a second approved encrypted backup before
deleting the cloud originals. ZIP compression is not encryption.

R2 `PutObject` uses Class A. `HeadObject` (existence/recovery checks) and `GetObject`
(downloads) use Class B. A normal new session uses one HEAD and one PUT; concurrent
retries can add checks/writes. Dashboard listing uses Class A; deletion is free.
Workers and D1 are separate services, so R2's free allowance isn't a spending cap
for the entire system. Set usage alerts and review costs/retention before launch.

## Tests

```sh
node --test tests/*.test.mjs
```

These use synthetic request bodies, an in-memory SQLite adapter, and fake R2 storage.
They cover authorization, revocation, byte/time/count limits, UTC reset, concurrent
reservations, corruption, duplicate uploads, cloud deletion and interrupted writes.
They do not prove a live Cloudflare deployment or real network behavior works.
From the app repo root, `bash scripts/test.sh` also checks Swift eligibility and ZIP
allowlisting without touching real sessions, Keychain or the network. It also exercises
the persistent queue with fake identity/networking, including opt-out during preparation,
no backfill, relaunch, offline retry, quota delay and corrupted-settings fail-closed behavior.

Before enabling participants, do a separate dummy-session acceptance test:

- Opt out: finish a session, verify no upload. Turn on sharing: the old session stays local.
- Enroll, opt in, finish a new session: confirm one ZIP under the correct ID in R2.
- Download/unzip and compare all six files and checksums with the local originals.
- Go offline, finish a new session, reconnect: pending upload eventually completes once.
- Quit with work pending and relaunch; confirm pending work resumes without duplicates.
- Opt out during queued/preparing/uploading states; verify no further queue starts.
- Run short synthetic uploads against quota boundaries and reject revoked credentials.
- Delete a local queued session; ensure it doesn't later upload. Local deletion must
  not claim to remove a previously uploaded cloud object.

## References

- [R2 pricing and operation classes](https://developers.cloudflare.com/r2/pricing/)
- [R2 bindings for Workers](https://developers.cloudflare.com/r2/get-started/workers-api/)
- [D1 database bindings](https://developers.cloudflare.com/d1/worker-api/d1-database/)
- [Downloading R2 files](https://developers.cloudflare.com/r2/objects/download-objects/)
