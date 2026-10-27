# Research participation and data operations

The account-based path replaces visible enrollment keys. There is no random selection:
researchers manually approve up to 50 total participants. The production study row
starts disabled and has no approval or retention terms invented by the app.

## Deployment and verification

Apply migrations in filename order, once. Existing projects that already have the
accounts migration need `202610270001_consent_and_lifetime_cohort.sql` followed by
`202610270002_serialize_upload_withdrawal.sql` and
`202610270003_scope_withdrawal_tombstones.sql`.
Deploy both `delete-account` and `delete-research-data` after that migration. Both
import `_shared/research-cleanup.ts`; CLI deployments include that dependency.

```sh
supabase functions deploy delete-account --project-ref YOUR_PROJECT_REF --no-verify-jwt
supabase functions deploy delete-research-data --project-ref YOUR_PROJECT_REF --no-verify-jwt
```

The legacy-secret gateway check is incompatible with some current JWT signing
configurations. The functions instead authenticate the supplied access token with
Supabase Auth's `/auth/v1/user` **before** using any service credential. Missing or
invalid authentication fails closed. Never add the service-role key to the app.

Local checks require Node 22.13+ and Python 3:

```sh
cd supabase
npm install --ignore-scripts
npm test
npm run test:database
```

The in-memory PostgreSQL runner models Supabase roles, `auth.uid()` and private
Storage tables, then executes the actual migrations and the policy tests. It does
not emulate Supabase Auth, email delivery, HTTP Storage size/MIME enforcement,
Edge Runtime, or two independent database connections. Run `tests/consent-access.sql`
on a **disposable project only** for a real Supabase policy test; it rolls back all
fixtures. Separately test concurrent approvals 50/51 with two database connections.
Use generated recordings and disposable accounts for app-to-service delivery tests.
Do not point a synthetic-enabled configuration at a participant project.

## Configure the approved study

1. Obtain the institution's determination and finalized eligibility, study duration,
   research contact, data uses, retention and withdrawal/deletion terms. Include
   whether future model training and product improvement are allowed. If restricted
   to Allegheny students, set `allegheny_only` and describe the actual criteria.
2. Copy `study-config.example.json` outside the repo and complete it from those
   materials. The default proposal is US adults 18+; an attestation is not independent
   verification of eligibility. The researcher verifies each application.
3. Publish the approved study information and privacy policy to their final HTTPS
   URLs. Review host/server logging and access by the storage provider.
4. Update the singleton `research_study` row privately with these exact terms.
   Setting recruitment or collection on fails if required fields are empty. Enable
   recruitment only for the approved recruitment period and collection only for the
   approved collection period. A nonempty determination reference is a configuration
   check, **not a machine verification of institutional approval**.
5. Run `python3 scripts/prepare-research-release.py /path/to/reviewed-study.json`
   from the app repo. It validates only. After review, `--write` prepares the local
   research flag, study URL, and account-linked research privacy declarations.
   It does not deploy the study or change live settings.
6. Finish App Store disclosures and synthetic end-to-end tests before distribution.
   Do not label account-linked recordings anonymous. Do not claim all processing
   stays on the Mac in a research-enabled build.

## Manual participant approval

Applicants affirm adult US residency and the current study's eligibility criteria.
Requesting to join sends their authenticated ID, requested version and attestations,
not recordings. Inspect requests privately in the dashboard. Use the institution's
approved private process to verify identity/eligibility and any consent documentation
requirements. The built-in consent record is not an electronic signature service.

```sql
insert into public.research_enrollments(user_id, enabled, consent_version)
values ('VERIFIED_APPLICANT_UUID', true, 'EXACT_CURRENT_STUDY_VERSION');
```

To decline a request, update that request's `research_interest.status` to
`not_selected`. Do not delete an application merely to reopen it. To pause approval,
set `research_enrollments.enabled=false`. Approval does not grant consent or start
uploads. Participants must separately review the complete consent and enable sharing.

`research_capacity.selected_count` advances atomically on each new enrollment and
never decrements when an account/enrollment is deleted. Paused and withdrawn people
still count. The hard ceiling is 50. Do not reset the counter or raise the cap for
this study. Requests are closed once capacity is reached; existing pending requests
can still be declined explicitly. No names or emails are stored in the aggregate.

## Consent, withdrawal and failures

The app stores the exact version and a fresh consent UUID; the server stores the
current consent and an event trail. Storage writes require current approval, the
active study version, active server consent, and the matching owner/consent/archive
path. Clients cannot write consent/enrollment tables directly. Changed versions
pause uploads until approval matches and the participant reviews and agrees again.

Only whole completed sessions begun under the current local consent are queued.
Signing in, approval, or relaunch never backfills historical recordings. Each archive
contains the existing six recording files and no profile/token files. User-entered
break labels may contain personal information; explain this in participant training.
Private, account-linked storage is pseudonymous at best, not anonymous.

Opt-out cancels local pending work immediately, persists a withdrawal, and revokes
that consent on the server when connectivity and the matching sign-in are available.
An independent local preference prevents an old queue file from restoring consent
if saving the new queue fails. Pending withdrawal blocks later grants/uploads from
that installation. Other devices cannot learn of an offline withdrawal until it
reaches the server; already accepted transfers cannot be recalled. A withdrawn
consent UUID can never be revived by a delayed enable request. Late revocation of
an old UUID cannot disable a newer deliberate grant on another device.

Storage authorization takes a shared account-row lock; consent changes and deletion
requests take the conflicting exclusive lock. Accepted Storage transactions finish
before deletion cleanup begins, and later writes check revoked consent.

Receipts prevent a stale queue from recreating an already received archive after
remote cleanup. Retain minimal receipt records under the approved retention policy;
never delete them while an eligible client could retry an old archive.

## Data deletion and model training

The app's research-data deletion action and account deletion both record an
idempotent request and revoke uploads **before** deleting hosted files. Cloud cleanup
uses only the verified caller's directory. Failures leave a durable pending request;
the user retries, and the researcher must also inspect pending requests.

`research_deletion_requests.status='hosted_deleted'` means hosted ZIPs were removed,
not that all research copies were erased. The request preserves its participant
reference after account deletion so the researcher can find downloaded copies.
Review this minimal identifier's retention/access in the protocol. Consent audit
rows retain consent UUID/version/times after account deletion with their account FK
cleared; they can remain linkable through researcher copies. Do not call them anonymous.

Maintain an access-controlled inventory linking received archive IDs to raw downloads,
working datasets, backups, training runs and model versions. Process each request
according to the approved policy, including any retention exceptions, then mark it
`completed` with `completed_at`. Stop using data for purposes outside the granted
consent. Do not promise automatic model unlearning: deleting source recordings does
not automatically remove their influence from trained weights. Document whether
retraining or another action is required by the policy before training begins.

No arbitrary 90-day timer or indefinite retention is implemented. Once the university
sets the policy, schedule the corresponding cleanup of hosted and researcher-held
copies, consent records, deletion records and backups. Do not rely on bucket cleanup
alone. Do not use future training as an excuse to keep all raw recordings forever.

## Free-plan operation

Keep the project on the existing Free organization; do not enable paid add-ons or
upgrade. The participant cap is not a storage/traffic budget. Monitor quotas, move
verified archives only into approved research storage, and apply the reviewed
retention policy. Quota failures leave originals local; ZIP export is explicit and
does not mark delivery successful. Never request private recordings in public Issues.

## Disposable-project HTTP integration runner

`node tests/live-delivery.mjs` exercises actual Auth/token refresh, Storage delivery,
receipts, cross-account rejection, withdrawal, research deletion and account cleanup.
It refuses the configured participant project and requires explicit acknowledgment
that both accounts are disposable. It reads only environment credentials, never
local recordings, and prints no tokens, passwords, email addresses or server bodies.

On a separate Free test project, apply all migrations and deploy both functions.
Create two confirmed `@example.invalid` fixture accounts using the authorized admin
workflow, configure a complete synthetic-only study with a determination reference
starting `SYNTHETIC` and `future_training=false`, and manually approve those two
account IDs with that study version. These are test configuration values, not a
claim of human-subject approval. Keep this project out of the distributed app.

Set `FOCUSFIX_TEST_SUPABASE_URL`, `FOCUSFIX_TEST_PROJECT_REF`,
`FOCUSFIX_TEST_PUBLIC_KEY`, `FOCUSFIX_TEST_EMAIL_A`, `FOCUSFIX_TEST_PASSWORD_A`,
`FOCUSFIX_TEST_EMAIL_B`, `FOCUSFIX_TEST_PASSWORD_B` privately in your shell, plus
`FOCUSFIX_TEST_ALLOW_ACCOUNT_DELETION=YES_DISPOSABLE_ACCOUNTS`. Do not commit an env
file or paste credentials into chat. Run the script once; it deletes both fixture
accounts in cleanup and retains the monotonic cohort count and minimal deletion
requests as designed. Recreating fixtures consumes additional test cohort slots.
This runner does not test real email delivery or fresh-Mac recording permissions.
