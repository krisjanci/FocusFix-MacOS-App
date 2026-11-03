# Current redesign handoff — November 2, 2026

I implemented all twelve automatic-tracking steps locally and committed each changed
file separately in each iteration. The current behavior/contract is in README,
RECORDING-CONTRACT and CODE_MAP; the requirement/verification/release boundaries are
in [REDESIGN-READINESS.md](REDESIGN-READINESS.md). Historical deployment entries below
do not mean this redesign was deployed or qualified on a signed Mac.

- Automatic mode requires a new explicit scope; manual remains available. Unknown,
  declared work, intervention phase and capture state remain independent.
- Lifecycle, atomic labels/revisions, coverage/history, contextual notifications and
  survey-free ordinary use are implemented. Study configuration is absent/off.
- New Work totals stay local: the old group RPC cannot reconcile decreases. Existing
  groups/healthy-break rules stay intact. New research archive qualification is off;
  old consent cannot authorize automatic/non-work delivery. No collection activated.
- Backend clustering and independent validation are separate, synthetic by default,
  with leakage checks and disabled preview fallback. Real fatigue benefit is unproven.
- 32 Swift executables, 40 pinned Python tests, seven mocked Node tests and isolated
  PostgreSQL checks passed. Universal unsigned builds/content checks and component
  visual evidence are recorded in readiness. The missing public privacy URL still
  blocks the submission gate; signing/live-device/service checks remain unperformed.

Next action: qualify one stable signed build on a fresh Mac using
[MANUAL-QUALIFICATION.md](MANUAL-QUALIFICATION.md), starting with actual Input
Monitoring and idle/pause/sleep. Keep research and unsupported new Work sync off.
Nothing pushed, deployed, published, submitted to Apple, or changed in live billing.

---

## Expandable People panel — October 27, 2026

The main Groups button now toggles a right-hand People panel, expanding from 490 to 850 points while retaining the timer width. Screens narrower than 850 points use the same panel in a sheet. The shared group selector and metric tabs persist by account, and account changes immediately clear displayed members. Rankings share rows with the Groups window and isolated 12-step tutorial, including positive-score podium markers and a pinned personal rank. Decorative animation respects Reduce Motion and inactive windows. Group progress has explicit signed-out, opt-in, loading, enabled and retry states; enabling is an in-app action, not a macOS permission prompt. Profile retains Test tracking and Quick tour.

All 23 Swift test executables, the isolated PostgreSQL suite (including creator-inclusive 49/50/51 capacity), 15 Node regressions, and final Debug/Release builds passed. Native synthetic previews verified expansion/collapse, 50-member scrolling, pinned rank, shared selections, opt-in and light/dark appearance. Evidence and limits are in `verification/people-verification.json`. Narrow-screen geometry was tested without changing the physical display; full spoken VoiceOver and a real multi-device session remain manual checks. No new backend schema or deployment was needed; the deployed RPC already enforces 50 members. Existing account, recording, research and billing settings were preserved.

## Group setup completed — October 27, 2026

Private groups, both daily-point leaderboards, automatic monthly streak freezes and account-scoped offline retries are implemented. The group migration is deployed to the existing configured Supabase project. Its function body matches the source; six private social tables and authenticated-only RPC access were verified. Live synthetic-role scoring, invite, isolation and freeze checks passed and rolled back all fixtures. Research collection remains disabled; billing was unchanged.

Test tracking and Quick tour are directly in Profile and close the sheet before opening. Both were exercised without starting recording. The main-screen tools overflow was removed. All 22 Swift checks, 15 Node tests, local PostgreSQL checks, Debug/Release builds and a normally sandbox-signed Debug build passed. Evidence is in `verification/social-*` and `verification/profile-*`. A real simultaneous two-device session test remains outside these checks. The sandboxed app launch reached a macOS Keychain prompt, which requires direct user handling because UI tools cannot operate SecurityAgent. The Profile navigation checks were completed in the unsigned verification build. The implementation and setup work are committed locally; no push was requested.

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

## Automatic tracking Step 1 — November 2, 2026

I added schema 11 and an atomic context snapshot with independent mode, capture
state, context and intervention phase. Manual Start declares work; old phase
values and raw CSV layouts keep their original meaning. Legacy history remains
unknown without destructive migration. New formats fail closed for research at
queueing and ZIP construction. See `RECORDING-CONTRACT.md` for the exact contract.
Automatic capture is not enabled by this foundation. Next: Step 2 explicit
versioned automatic-recording consent and optional login launch.

## Automatic tracking Step 2 — November 2, 2026

I added a separate versioned automatic-recording acknowledgement, disabled by
default for fresh and existing installations. Global recording revocation disables
it; stale automatic callbacks can use the invalidated generation. The settings
choice does not request OS permissions. Optional login launch uses SMAppService,
reads actual OS status and registers only on the explicit toggle. Failed setup
stays visible. Login launch is separate from capture/pause consent. Fake-client
preference/login tests passed; actual registration and login remain manual checks.
The lifecycle in Step 3 is next; this step does not start automatic capture.

## Automatic tracking Step 3 — November 2, 2026

I connected silent launch/activation, sleep/display/login, permission loss, idle,
user pause, preference revocation and Quit to a single lifecycle decision point.
Automatic capture requires both explicit scope consent and existing OS access.
Idle defaults to five minutes, pause persists, and resumed automatic capture starts
unknown. Daily/timezone rotation preserves logical IDs and cooldown while changing
segments. Synchronized checkpoints bound crash recovery; sampling gaps are not
backfilled. Short automatic intervals are retained. New data remain local only.

Pure lifecycle/recovery/rotation tests passed and Debug compiled. Release and the
full Swift runner passed for this iteration. Real sleep/lock, permission,
long-running memory/disk behavior and signed-device operation remain manual.
Next: Step 4 work/non-work/unknown actions and bounded history revisions.

## Automatic tracking Step 4 — November 2, 2026

I connected optional Start work to forward labels on the existing automatic writer,
and End work to unknown (automatic) or stop/save (manual). Work/Not working/Unknown
are in the menu. History has a minimal bounded context editor with optimistic
revision checks, retry IDs and atomic original-label provenance; raw files stay
unchanged. Generated tests cover mixed labels, repeated Start, bounded/retried/
stale edits, preserved original labels and byte-identical events. Live capture
interaction still needs device qualification. Next: Step 5 contextual reminders.

## Automatic tracking Step 5 — November 2, 2026

I added forward-only Not working notification actions, stable policy/recording/
work-period targeting, duplicate/stale checks and append-only request/action logs.
The fixed baseline remains active, defaulting to declared work; screen-use reminders
outside work are separately opt-in. Dismissal/no response does not label context or
prove fatigue/rest. Denied notifications still leave useful in-app controls.
Pure reminder tests cover current/stale/duplicate/no response, context changes,
pause/revoke and midnight cooldown. Debug compiled; actual banner delivery/actions
remain manual device checks. Next: Step 6 main/menu/history and isolated tour.

## Automatic tracking Step 6 — November 2, 2026

I aligned the main window/menu around recording status, optional Start/End work,
Pause/Resume and context. Recorded elapsed time is labeled separately from declared
work. History identifies recording/segment IDs and shows observed work/non-work/
unknown/break/unavailable coverage, with check-in/return time separate. Short auto
retention is already in the lifecycle. Legacy history/export/deletion remain.
The isolated tour now practices automatic Unknown capture, optional work labels,
notification Not working and pause/resume without live dependencies.

Generated coverage/status/tour checks and unsigned Debug compilation were run.
The actual shared status component was rendered and visually inspected in light/
dark at narrow width, including paused/idle/permission and long text. Evidence:
`verification/recording-status-previews.png`. These are component previews, not
full-window or spoken VoiceOver qualification. Source inspection confirms keyboard
history controls and explicit labels; full keyboard navigation remains manual.
Next: Step 7 ordinary use without surveys and separately gated study checks.

## Automatic tracking Step 7 — November 2, 2026

I made ordinary use survey-free without deleting old answers/options. An independent
versioned study scope plus complete reviewed configuration is required for prompts;
none is bundled. Only generated tests inject the synthetic schedule. Rate/quiet
limits and frozen versions gate cross-context requests, and their immutable IDs
join to precise preceding recall windows/context. Revocation cancels stale prompts.
Old survey exports remain readable and are not relabeled as new measurements.
The original supervised backend remains work-only and cannot consume schema 11.
Debug compiled; generated preference/schedule/recall/withdrawal checks and the
existing Swift runner are used. Real study configuration/approval remains absent.
Next: Step 8 declared-work progress and fail-closed unsupported social corrections.

## Automatic tracking Step 8 — November 2, 2026

I replaced live wall-time credit with synchronized observation slices intersecting
declared work. Version-2 local progress stores replaceable segment/day allocations,
revision counts and account-scoped social ownership; legacy credit is preserved.
Corrections and recovery reconcile idempotently. Explicit break rules, private
groups, point thresholds and freezes are unchanged. The increment-only server RPC
cannot reconcile decreases, so new work stays in a separate local replacement
outbox and is never sent as legacy events. Existing healthy-break sync remains.
`supabase/DECLARED-WORK-SYNC.md` describes the server release dependency.

Generated progress/outbox/account tests, full Swift regressions, unsigned Debug and
the isolated PostgreSQL suite passed. PGlite 0.5.12 was restored into /tmp with
package scripts disabled; the suite uses an in-memory database, not real groups.
Next: Step 9 research archive/scope preparation, with new-format delivery disabled.

## Automatic tracking Step 9 — November 2, 2026

I prepared archive version 2, scope/provenance validation, account/consent segment
boundaries and the expanded allowlist. Old consent has no automatic/non-work scope;
withdrawal/account mismatch/pre-consent data fail closed. New-schema production
queue/ZIP eligibility remains disabled. The new ZIP builder is compiled only for
synthetic tests and requires generated-fixture metadata. Caps remain 180 minutes/
study day, 100 MiB raw and 25 MiB compressed. Long segments are ineligible rather
than bypassing the cap. Existing withdrawal/deletion/receipt protections remain.
See research operations for downloaded-data/model inventory deletion requirements.

Generated archive/scope/cap/path/retry/account tests and the existing withdrawal
regressions are run. Local Debug compiled; real reviewed consent, disposable-service
end-to-end/race checks and cumulative server compatibility remain absent. No
migrations/functions deployed, settings enabled, billing changed or data accessed.
Next: Step 10 a separate local clustering experiment on generated fixtures.

## Automatic tracking Step 11 — November 2, 2026

I added a versioned provider seam with the fixed timer selected. The only alternate
provider is an explicitly disabled synthetic preview: exact seven-rate/float32
parity, full coverage, context/pause/cooldown, version, model age and unknown-cluster
checks all fall back safely. It returns descriptive IDs, never a fatigue score.
The backend independently compares prompt-linked fatigue against mean and context/
time/prior-work baselines, with added clusters, separate person/time splits and
count/missingness/uncertainty reports. Small generated demos report insufficient
evidence. The private planning draft separates validation from a proposed future
randomized comparison; no course/IRB document was changed or randomization enabled.

Full Swift regressions, synthetic Python validation/parity tests and Debug passed.
Cluster structure is demonstrated only synthetically; real fatigue improvement is
not established; intervention benefit is not tested. Next: Step 12 integrated audit,
release documentation, remaining regressions and explicit manual qualification.
