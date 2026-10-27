# FocusFix research/privacy implementation handoff

October 26, 2026. Implementation changes are recorded in one-file commits; see Git history. Backend migrations and deletion
functions were deployed to the existing Free Supabase project through its owner's
already-authenticated dashboard. No participant accounts or recordings were created,
no real recruitment/collection was enabled, and nothing was submitted to Apple.

## Implemented

- Profile contains identity/account management; Settings → Privacy & Research contains
  recording, study participation, survey and detailed privacy controls.
- First app entry offers Enable recording / Not now. Recording preference and Input
  Monitoring remain separate; Start is required. Disabling recording stops the current
  session and blocks direct/menu-bar Start paths until consent is enabled again.
- Account-based participation, full versioned study consent, eligibility attestations,
  manual approval and explicit sharing. No visible enrollment key or live legacy uploader.
- Transactional cap of 50 total selected accounts; deleting accounts does not reopen places.
- Server consent, immutable withdrawn consent IDs, cross-account isolation and Storage
  checks for current approval/version/consent plus exact owner/consent/archive paths.
- Shared upload locks conflict with withdrawal/deletion locks, ordering accepted Storage
  transactions before cloud deletion. Withdrawal tombstones affect only their own account.
- Durable offline withdrawal, an independent preference protecting opt-out if the queue
  file cannot be rewritten, account-switch protection, no historical backfill, receipt
  deduplication, automatic per-session delivery and recovery after temporary access failures.
- Research deletion endpoint and updated account deletion endpoint revoke access first,
  remove hosted archives, and retain a private researcher cleanup request for downloaded
  copies/datasets. Failures remain retryable; model unlearning is not falsely promised.
- Incomplete study configuration fails closed. Release preparation script updates local
  flags and privacy declarations only after complete reviewed configuration is supplied.
- Account privacy manifest, website privacy draft, App Store listing/reviewer draft and
  release-content gates updated. App Store export requires a public privacy-policy URL.

## Deployed state

Project: `ltgyhstpbiocuxvyjpcb`. Organization remains Free.

Applied to the existing base schema:

1. `202610270001_consent_and_lifetime_cohort.sql`
2. `202610270002_serialize_upload_withdrawal.sql`
3. `202610270003_scope_withdrawal_tombstones.sql`

Both `delete-account` and `delete-research-data` are deployed. Dashboard sources inline
`functions/_shared/research-cleanup.ts` and append the respective `Deno.serve` wrapper.
They validate access tokens with Supabase Auth before any privileged operation. The
incompatible legacy-secret-only gateway check is off; explicit user authentication
remains required. CLI source includes the same handler as a shared import.

Final dashboard check: recruitment **false**, collection **false**, selected count
**0**, research bucket public **false**. Email authentication is enabled and requires
confirmation. The checked-in research flag remains false and study URL remains empty.
Migrations were run manually in the dashboard; reconcile migration history before
introducing CLI `db push`, rather than blindly replaying already-applied migrations.

See `verification/deployment.json`, `verification/live-endpoints.json`, and
`verification/backend-disabled.png` for recorded evidence.

## Verification completed

- All **20 Swift test runs passed**, including consent changes while the dialog is
  open, current-version enforcement, durable/offline opt-out, stale queue restoration,
  changed accounts, no backfill, receipt deduplication and access-check failure recovery.
- **7 backend-function tests passed** using mocked Auth/Storage, including authentication,
  target-account isolation, unsafe paths, revoke-before-delete ordering and failure handling.
- Actual migrations executed in isolated PostgreSQL via PGlite, with RLS/access tests for
  consent, withdrawal, version changes, capacity, account deletion and cross-account
  tombstone poisoning. This models Supabase schemas; it is not a live Auth/Storage test.
- **Universal Release build passed** for arm64 and x86_64. Release-content checks passed.
  No valid Apple signing identities are available here; this is not a Store-signed export.
- Four live HTTP checks confirmed both deployed deletion endpoints reject missing and
  invalid tokens with 401. These requests did not delete any accounts or recordings.
- Isolated app identity used for UI checks: guest entry, first-launch consent, simplified
  Profile, Settings navigation, recording re-enable consent and recording disablement.
  No Input Monitoring permission was granted and no session was recorded. Engineering
  screenshots are under `verification/`; they are not a final App Store screenshot set.
  The three app images were recaptured with the pointer outside the app window so no
  OpenAI cursor marker appears; the backend capture was also visually checked.
- Diff whitespace, release-script syntax, live-runner syntax and configuration guards
  checked. Store submission gate correctly rejects the missing public privacy-policy URL.

Build: `/tmp/focusfix-research-build/Build/Products/Release/FocusFix.app`.
It is an unsigned verification build, not a distributable App Store app.

## Remaining launch requirements

1. University determination and approved eligibility, purposes, consent, contact,
   retention, withdrawal and future model-training terms. No approval or retention period
   has been fabricated. Activate only within the approved study periods.
2. Two confirmed disposable accounts and an isolated Supabase test project for full
   authenticated app/API delivery, deletion, email and token-refresh verification.
   `supabase/tests/live-delivery.mjs` is prepared and explicitly refuses the participant
   project. Run the two-connection 50th/51st approval race in that disposable environment.
3. Publish actual privacy/study pages and establish the private research contact channel.
   Set `FocusFixPrivacyPolicyURL`; prepare research settings/manifest using
   `scripts/prepare-research-release.py` only with the finalized reviewed study configuration.
4. Complete fresh-Mac real Input Monitoring, notifications, sleep/wake, export/deletion,
   and advertised OS/hardware qualification. Local compilation cannot establish these.
5. Owner/contributor/artwork and GPL/App Store distribution-rights determination. The
   existing license is unchanged; code generation cannot grant missing rights.
6. Apple Developer signing/provisioning, final screenshots/metadata/private reviewer access,
   TestFlight and App Review. No Apple agreements were accepted or submissions performed.

Operational instructions: `supabase/RESEARCH-OPERATIONS.md`.
Submission copy and checklist: `STORE-SUBMISSION.md`.
Local website privacy draft: `../FocusFix-Website/dist/privacy.html`.
