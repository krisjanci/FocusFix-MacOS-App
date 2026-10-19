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

Think of the setup as three things:

- **R2 bucket = cupboard.** It holds the session ZIPs.
- **Worker = person at the door.** It checks who is allowed to send a ZIP.
- **D1 = notebook.** It remembers enrollment, daily limits and what already arrived.

The bucket is already named in the code, but creating it alone doesn't connect the app.
Read the billing section below first: this setup does **not** guarantee a $0 bill.
These steps deploy a real service; I haven't run them against my account yet.

### 1. Check my account and bucket

Open Cloudflare and find R2 → `focusfix-mldata`. Keep it **private**, with public
`r2.dev` access disabled and no public custom domain. Use **Standard** storage.
Check the Workers plan is Free if that is the plan I intend to use, and enable account MFA.
Do not upgrade a plan just to follow this guide. Workers Free does not remove R2 overage charges.

### 2. Open the right terminal folder

In VS Code, choose **Terminal → New Terminal**. Paste this command and press Return:

```sh
cd "/Users/krisjanci/Desktop/CS 600/FocusFix-MacOS-App/upload-service"
```

`cd` means change folder. The quotes keep the space in `CS 600` from confusing the terminal.
Run each following command separately and wait for it to finish. Stop if one reports an error.

### 3. Check Node is installed

```sh
node --version
```

If it says command not found, install the current LTS macOS installer from
[the official Node.js download page](https://nodejs.org/en/download), then reopen
the terminal and repeat step 2. Node runs the small setup scripts; it isn't added to the Mac app.
The local service tests need Node 22.13 or newer.

### 4. Let the deployment tool sign in

```sh
npx wrangler@4 login
```

`npx` downloads/runs Wrangler, Cloudflare's deployment tool. If it asks to install Wrangler,
confirm. A browser opens: sign into my own account and review/approve its access request.
Wait for the terminal to confirm login. Never paste a Cloudflare password or admin token into chat or Swift code.

### 5. Create the notebook (D1 database)

```sh
npx wrangler@4 d1 create focusfix-upload-control
```

The output includes a `database_id`. Copy that value. Open `upload-service/wrangler.jsonc`
in VS Code and replace **only** `REPLACE_WITH_YOUR_D1_DATABASE_ID` with the copied ID.
Keep its quotation marks and save. Leave the `RECORDINGS` and `DB` binding names unchanged;
the receiver uses those exact names. If the database already exists, use its existing ID
from the Cloudflare D1 dashboard instead of creating another database.

### 6. Give the notebook its tables

```sh
npx wrangler@4 d1 execute focusfix-upload-control --remote --file=schema.sql
```

Confirm the remote execution if asked. This creates enrollment, upload and attempt tables
in the cloud, not just on my laptop. The supplied schema uses `IF NOT EXISTS`; it doesn't
erase existing rows. Successful output should report that the SQL ran without an error.
These database setup steps follow [Cloudflare's D1 guide](https://developers.cloudflare.com/d1/get-started/).

### 7. Put the receiver online, still closed to uploads

Leave `"UPLOADS_ENABLED": "false"` in `wrangler.jsonc` and run:

```sh
npx wrangler@4 deploy
```

If Cloudflare asks me to choose a workers.dev subdomain, choose an available one.
Copy the actual HTTPS address printed after a successful deployment. It looks like
`https://focusfix-uploads.MY-SUBDOMAIN.workers.dev`; the example is not my real address.
No domain purchase is needed. This address belongs to the Worker, not the R2 bucket.
Opening it in a browser is not an upload test: there is no website at that address.

### 8. Tell the Mac app where the receiver lives

In Xcode or VS Code, search the project for `FF: UPLOAD_CONFIG`.
Open `UploadTransport.swift` and find:

```swift
static let serviceURL = ""
```

Put the copied Worker address between the quotes. Use the origin only: no `/v1/sessions`
suffix, no bucket name, no password. Save. Open `FocusFix/FocusFix.xcodeproj` in Xcode,
select **FocusFix → My Mac**, and press **Command-R** to build/run this new version.
Old app builds don't acquire this address automatically. Changing the address in a
later build turns sharing off and requires a fresh opt-in.

### 9. Open the receiver for a controlled test

Only when ready to send deliberately created test data, change `UPLOADS_ENABLED` to
`"true"` in `wrangler.jsonc`, save, and run `npx wrangler@4 deploy` again from this folder.
This doesn't make the bucket public. Enrollment and opt-in are still required.
For real participants, first finish the approved study consent and storage plan.

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

For my first test, I'm the participant: copy the ID from my own app, replace the
placeholder in the command with that ID, then use the printed SQL in D1's Console.
Click Run in that console. The other printed value, shaped like `ID.secret`, goes
into the app's secure **Enrollment credential** box, not the SQL console.

### 10. Check one short test session arrives

With sharing on, start a **new** session. Use only deliberate test activity; the app
records activity outside its own window too. Stop after about a minute and leave the app
open with internet access. Open Sessions and check the upload status.

In Cloudflare, open R2 → `focusfix-mldata` and refresh the object list. Look inside
my participant-ID prefix for a session ZIP. Download and unzip it. There should be
five CSVs plus `session.json`, with matching session/participant IDs in the metadata.
Compare these with the local originals before calling the connection tested.

If something doesn't arrive:

- Sharing toggle unavailable: check the app's service URL, saved enrollment and Keychain notice.
- Enrollment rejected: confirm I ran the generated SQL in the same D1 database used by this Worker.
- Service unavailable: check `UPLOADS_ENABLED` is true **and redeployed**.
- Waiting: keep the app open; retries are delayed. The account panel also has Check pending uploads.
- Quota reached: wait until the next UTC day. Don't reset identity to bypass it.
- Old session stays local: expected. Opt-in only applies to sessions started afterwards.

### 11. Close the receiver when finished testing

Set `UPLOADS_ENABLED` back to `"false"`, save and deploy again. Turn off sharing in
the test app too. This stops new app uploads; it doesn't delete files already stored,
remove accrued usage, or guarantee billing stops. Downloads/retention are still my responsibility.

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

## Operations and avoiding surprise bills

I am keeping one ZIP per session for now. With 100 participants doing three sessions
each day for 30 days, that is 9,000 new session uploads. The current normal path makes
one R2 PUT (Class A) and one HEAD (Class B) per new session. Downloads, listings and
some retries add operations. The current Standard allowance is 1 million Class A,
10 million Class B and 10 GB-month of storage per month.
[Check current R2 pricing](https://developers.cloudflare.com/r2/pricing/).

Combining three sessions into one daily ZIP could reduce upload operations, but just
waiting until evening to send three separate ZIPs would not. Batching doesn't remove
the recorded bytes. It also delays delivery and needs new packaging/retry logic.
The app still uploads per session; this guide has not changed that behavior.

**I cannot promise never to be charged on pay-as-you-go R2.** The 180-minute limit
is per participant, not a global storage limit or spending ceiling. Worker and D1
usage also need review. I shouldn't enable real uploads if an absolute $0 guarantee
is a requirement; I need an institution-funded service or an enforced free-only cap instead.

My precautions before a pilot:

1. Confirm Standard storage and my intended Workers/D1 plans in my account. Avoid
   enabling unrelated paid features. Review usage across the account, not just this project.
2. Use a small enrolled group first and measure actual ZIP sizes. Don't guess storage
   needs from session length alone. There is no global automatic storage cutoff in this code.
3. In Cloudflare's account billing area, open **Billable Usage → Create budget alert**
   if available, choose a low threshold and an email I check. Alerts only warn: they
   **do not stop usage**, and spending can already have happened when one arrives.
   [Cloudflare budget-alert instructions and limitation](https://developers.cloudflare.com/billing/manage/budget-alerts/).
4. Review R2 storage/operations plus Worker/D1 usage regularly. Keep a comfortable
   margin below allowances. Follow the approved retention plan: download, verify,
   make a second encrypted backup, then delete cloud copies when appropriate.
5. If I need to stop receiving data, use the disabled-and-redeploy step above. Already
   stored data can still accrue storage usage. Disabling uploads is not a billing switch.

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
