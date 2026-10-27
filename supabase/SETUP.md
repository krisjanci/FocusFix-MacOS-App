## Current deployment and consent flow

Follow [RESEARCH-OPERATIONS.md](RESEARCH-OPERATIONS.md) for the new migration,
manual approval, server consent, lifetime capacity and both deletion endpoints.
The account settings are connected in the current source; research is disabled.
The live legacy upload path is retired. The instructions below are historical
stage-one setup notes; their direct interest inserts, profile research controls,
legacy-uploader availability and approval-only Storage policies are superseded.
Apply the new migration once after the original account migration. Do not replay
the original migration on an existing project.

# Free-plan accounts and per-session research ZIPs

The app integration is prepared but is **not connected or deployed**. Local profiles,
recording, surveys and progress work without a Supabase account. Stage 1 adds private
account profiles, not leaderboards or activity-history sync.

## 1. Keep the organization on Free

Create an account at https://supabase.com and create a dedicated FocusFix project in an organization
whose billing page explicitly says **Free**. Do not start a Pro trial, upgrade,
transfer the project into a paid organization, or enable paid add-ons. No payment
method or administrator credential belongs in the app. This repository never calls
Supabase management/billing APIs or upgrades the plan.

As checked on October 24, 2026, the Free plan includes 1 GB of file storage, a 500 MB
database, 5 GB of uncached egress, and 50,000 monthly active users. Projects may pause
after a week of inactivity. Supabase states that Free-plan users are not charged;
continuing to exceed quotas can restrict service. The allowance is NOT a promise
that an upload stops at the exact byte where the quota is reached. A grace period
may apply. Client limits alone cannot stop a modified client from exhausting quotas.

- Pricing: https://supabase.com/pricing
- Free-plan cost rule: https://supabase.com/docs/guides/platform/cost-control
- Quotas/restrictions: https://supabase.com/docs/guides/platform/billing-faq

At 25 MB per ZIP, 1 GB holds only about forty full-size archives across participants.
Download received ZIPs into your approved research storage and remove the received
copies from the bucket when appropriate for the study's retention rules. Deleting
received files is a separate explicit researcher action, not an automatic app action.
A download also consumes egress. The app keeps originals when delivery fails and
provides **Export ZIP…**; there is no paid fallback.

## 2. Set up authentication and the private schema

1. In the project's SQL editor, run
   `migrations/202610250001_accounts_and_research.sql` once. It creates a private
   `account_profiles` table and a private `research-sessions` storage bucket. Users
   can only read/write their own profile and their own upload directory. The bucket
   enforces 25 MiB per file independently of the app. Nothing is publicly readable.
2. Enable email/password authentication and keep email confirmation enabled.
   Configure the project's password minimum to at least eight characters.
3. Configure custom SMTP using an existing institutional or other mail service
   that you are authorized to use and whose plan has no usage charges. Supabase's
   default email sender is restricted to organization-team addresses and is not a
   general production email service. If a provider requires a paid plan/domain,
   stop and use local profiles until a free or existing mail option is available.
   Never put SMTP credentials in the app or this repository.
4. In the confirmation and password-recovery email templates, include the
   `{{ .Token }}` code clearly. The app accepts codes inside its account screen;
   no custom URL scheme or hosted password-reset page is needed. Leave provider
   rate limits enabled. Auth setup reference:
   https://supabase.com/docs/guides/auth/auth-smtp
5. Deploy `functions/delete-account/index.ts` to this project. For example, with
   the Supabase CLI already authenticated to your own account:

   ```sh
   supabase functions deploy delete-account --project-ref YOUR_PROJECT_REF --no-verify-jwt
   ```

   The function explicitly verifies the caller's access token with Auth's
   `/auth/v1/user` endpoint before making any admin request. It accepts no user ID
   from the caller. The gateway flag allows this explicit verification to work
   with current project signing-key configurations; it does not make deletion
   anonymous. Supabase supplies `SUPABASE_URL`, `SUPABASE_ANON_KEY`, and
   `SUPABASE_SERVICE_ROLE_KEY` to the server environment. Keep the service-role
   secret exclusively there. The function deletes only that verified user's research
   objects, then their auth account (the private profile cascades). Downloaded
   researcher copies and local recordings are not deleted. If server-side deletion
   fails, the app keeps the account signed in so the user can retry.

## 3. Connect the app

In `FocusFix/Configuration/Info.plist`, set:

- `FocusFixAccountURL`: the HTTPS project origin, such as
  `https://YOUR_PROJECT_REF.supabase.co` (no endpoint path).
- `FocusFixAccountPublicKey`: the publishable key (`sb_publishable_…`) or legacy
  **anon** key. These are public client settings; access rules protect data.
  Never use a secret key or service-role key; the app rejects those formats.
- `FocusFixStudyInformationURL`: the HTTPS URL of the approved study information.
  If it is absent/invalid, research sharing stays unavailable even if its flag is on.
- Keep `FocusFixResearchSharingEnabled` **false** while testing accounts. Set it
  **true** only after deploying/testing the private bucket and reviewing the study
  information, research consent, privacy declarations and participant distribution.

Both build configurations allow outgoing HTTPS. The legacy Cloudflare uploader is
still available in Debug builds when the research-sharing flag is off. With the research-sharing flag
on, its live environment is disabled and its existing credentials/queue are left
untouched: a recording cannot be sent through both paths by this build. Release
still has no legacy upload endpoint. Neither path is opted into by signing in.

Build and open the profile screen. Create an account, enter the emailed code,
then create an account profile. Existing local names/photos are NOT automatically
sent to the account service. Explicitly save a chosen name/avatar to sync it.
Account profiles are private in stage 1. A signed-out local profile stays separate.
Passwords are never persisted. Session tokens use a separate Keychain service.
The first launch offers Create account, Log in and Use as guest. Guest choice is
remembered. Keep me signed in is selected by default; successful sign-in with that
choice saves tokens in Keychain and authorizes automatic restoration after the intro
on future launches. macOS can prompt for Keychain access. Without that choice, the
new session stays in memory and is not automatically restored. Old installations
without the new preference do not automatically read previously saved credentials.
Continue with saved account remains an explicit option in the account form. Guest
selection cancels pending authentication/restoration, ignores late results, and
turns off automatic restoration without opening Keychain. A previous credential
can remain in Keychain until an explicit sign-out/deletion; Guest does not reuse it.
Newly confirmed accounts offer optional profile setup with a clickable avatar circle
and Skip for now. The menu-bar Start action cannot bypass unresolved onboarding.

## 4. Per-session delivery and enrollment

Participants may request to join from the profile screen. This inserts only their
account ID and request time in `research_interest`; it does not approve them or
upload recordings. Review requests privately in the Supabase dashboard. After the
institution-approved consent process is complete, approve a selected participant
using the SQL editor, replacing the placeholders:

```sql
insert into public.research_enrollments (user_id, enabled, consent_version)
values ('SELECTED_AUTH_USER_UUID', true, 'APPROVED_CONSENT_VERSION');
```

Only the project researcher/admin can approve participants. Client roles have no
write access to enrollment or capacity. A database trigger locks the capacity row
and refuses cohort additions past **50 selected participants**, including simultaneous
approvals. Paused/withdrawn enrollment records still count toward the cohort size. Users cannot bypass this by modifying the app or calling Storage directly:
Storage write policies require both their own directory and active enrollment.
The capacity is not a storage/traffic quota; selected users can still exhaust free
allowances. Increasing to 100 requires an explicit researcher action and any study
approval changes required by the institution:

```sql
update public.research_capacity set max_participants = 100 where singleton = true;
```

To pause a selected participant, set their enrollment `enabled` to false. This
blocks further storage writes immediately at the server. The app checks approval
on sign-in and before delivery, pauses if it cannot verify it, and exposes a Check
approval button. Record the approved consent version in each enrollment; changing
it requires a fresh app upload opt-in before new recordings can be shared.
Enrollment records document the researcher's approval; they are not an electronic
signature system or a substitute for approved consent records.

After approval, the participant explicitly confirms **Share new sessions for
research**. Only finished sessions whose recording started under the current
consent are queued. No historical backfill or scan of unrelated sessions occurs.
Opting out or signing out cancels queued deliveries. A session spanning
opt-out/re-opt-in is excluded. Each session starts uploading after Stop/save; checks
once per minute drain pending sessions while the app is open and signed in.
Closing the app, offline operation, expired credentials or a restricted/paused
project can delay delivery. It never wakes or launches the app. Failed delivery
retries no more than hourly unless the user presses **Deliver now**. Relaunch
preserves the queue and upload identifier.

Each archive holds exactly one completed session, up to 100 MiB raw and 25 MiB
compressed. Pending sessions drain in successive checks. An individual oversized/missing/unsafe session pauses delivery with an
explanation; export individual recordings from Sessions to resolve it. The next
ZIP export contains the oldest queued session, uses the same raw-size bound and does not mark anything as delivered.
Archives include only the six existing recording files under session UUID folders.
Profile files, progress files, account tokens and consent-queue state are excluded.
Session contents can still include user-entered break labels; the recording notice
warns against personal information in them. The authenticated service can associate
uploads with an account even though names/photos are absent from ZIPs.

The researcher receives archives in Storage → `research-sessions` → user UUID →
consent UUID. Download and verify received archives before deleting remote copies.
Nightly deletion frees storage but does not reset monthly download traffic. With
50 participants over 30 days, a 5 GB uncached egress allowance averages about 3.3 MB
per person per day, before account/API traffic. At 100 participants it is about
1.7 MB. Measure actual compressed recording volumes in a synthetic pilot before
recruiting that cohort; participant count alone cannot guarantee the Free plan fits. The bucket is private: download through the authenticated dashboard.
This is automatic private delivery, **not email delivery**. Storage upserts reuse
the persisted batch path after retries. The server's `confirm_research_upload` RPC
checks that the authenticated participant's object exists before recording a durable
receipt. Clients check that receipt before retrying, so an old queue snapshot does
not recreate a ZIP already received and then cleared from storage. When performing
nightly downloads, use `research_upload_receipts` to identify confirmed files; verify
your local copy before deleting the corresponding Storage object. Keep receipt rows
so retries remain deduplicated; they contain identifiers/times, not recording data.
Off-device receipt cannot be recalled by opting out; the UI states this explicitly.
Do not delete the Cloudflare account or old received research data as part of setup.
Retire the old Worker/bucket only after successful end-to-end testing and an explicit
migration/decommissioning decision.

## 5. Verification before connecting participants

Local synthetic checks (never real accounts/credentials/recordings):

```sh
bash scripts/test.sh
node --test supabase/tests/*.test.mjs
```

The SQL has not been applied to a live database, and the function has not been
deployed by Codex. `tests/access.sql` is a rollback-only policy/capacity test for a
disposable project; it creates synthetic auth users inside a transaction. Run it
there after the migration, never against participant data. Also test simultaneous
50th/51st approval attempts from two database connections. On the Free project, use two disposable test accounts to verify:

- Confirmation codes, sign-in, relaunch/restore, expired-session refresh, invalid
  credentials, sign-out, recovery codes and account deletion.
- Names and photos sync to a second installation only after Save. Signing out never
  shows the previous account's private profile to another account.
- User A cannot read or overwrite user B's profile, list/download B's ZIPs, or write
  outside A's own folder. Unauthenticated calls cannot read either table/bucket.
- The 51st concurrent active approval is rejected; users cannot approve themselves.
  An unapproved/revoked account cannot upload even by calling Storage directly.
- A MIME mismatch or file over 25 MiB is rejected by Storage even without the app.
- Creating an account or pressing Start does not opt in. Sharing sends only new
  consented sessions. Test Deliver now with synthetic sessions, opt-out during a
  transfer, retry after simulated quota/offline failure, and Export ZIP.
- Deletion requires a valid current-user access token, removes that user's objects
  and account, and cannot delete a different account via a request-body user ID.
- Inspect the archive and the receiving dashboard, then test on a clean Mac.

Before distributing a configured build, review/update `PrivacyInfo.xcprivacy`, App
Store privacy answers, study materials and support/deletion instructions for actual
account/profile/research collection. The current unconfigured build has no account
endpoint and performs no account collection; this is not public-release approval.
