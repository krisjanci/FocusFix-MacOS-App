# Cloudflare uploader removal — October 29, 2026

## What changed

Supabase is now the only research delivery implementation in the app source.
Removed the retired Cloudflare Worker, R2/D1 bindings and schema, enrollment helper,
service package, Swift queue/transport/installation-identity code, and their obsolete
tests. Removed the Worker test step from CI and the old uploader status in Sessions.
The project uses Xcode folder synchronization, so deleted Swift files require no
manual project-file entries to be removed.

Recording start/stop/delete no longer accesses the retired uploader. New session
metadata omits its optional `participant_id` and `sharing_consent_id` fields and
explains the current account-based sharing policy. Schema version 8 and all CSV
formats remain unchanged; the removed metadata fields were optional. Older files
remain readable and export with their original metadata.

Updated README, code map, release checks and Supabase setup/test instructions.
The existing release-content checker still rejects the old development endpoint;
this is an absence check, not an active Cloudflare integration. Historical notes
and earlier verification logs retain their original context. Ignore rules for
`.wrangler`, local secrets and enrollment SQL remain to keep any old local files
out of future commits.

## What is preserved

Supabase authentication, profiles, groups, research approval, versioned consent,
private Storage delivery, retry state, withdrawal and deletion flows are unchanged.
The Supabase archive implementation is independent of the deleted ZIP helper.
Local recording, surveys, breaks, session browsing and export remain available.
The current research feature gate is unchanged: removing Cloudflare does not enable
research collection or grant consent.

No participant recording, saved queue, Keychain entry, cloud data or deployed
service was deleted. Old development state is left dormant; it is not migrated or
resumed. Session deletion still moves the local recording to Trash. Research-data
deletion remains a separate action in Settings → Privacy & Research.

## Deployment boundary

Deleting repository source does not disable a deployed Worker, delete an R2 bucket
or D1 database, or change Cloudflare billing. Those resources must be reviewed
separately before decommissioning, preserving received data under the applicable
study policy. The Cloudflare account can still be used for website hosting or DNS.
This change makes no cloud deployment or account changes.

## Verification

- The pre-change Swift suite passed.
- All 19 retained Swift test programs passed after removal, including account,
  research consent/delivery, groups, recording, exports, surveys and input handling.
- The recording regression test verifies that new files omit retired identifiers,
  while a historical recording reloads and exports its metadata byte for byte.
- All seven Supabase endpoint tests passed with fake authentication/storage.
- Isolated PostgreSQL checks passed: migrations, RLS, consent, withdrawal,
  deletion, lifetime cohort cap, group capacity, scoring and freezes.
- Debug and Release Xcode builds succeeded for both `arm64` and `x86_64` with
  code signing disabled. Both binaries contain no `workers.dev` address, retired
  participant header or legacy enrollment Keychain service string.
- The Release content checker passed identity, manifest, license, icon,
  architecture and development-endpoint checks.

Builds needed Xcode compiler helpers outside the filesystem sandbox. The package
registry was unavailable inside the sandbox, so database verification used the
already installed PGlite 0.5.12 runtime in `/tmp/focusfix-sql-validation`, matching
the version pinned in `supabase/package.json`. No live Supabase or Cloudflare
requests or participant recordings were used for verification.

These checks do not establish signing, notarization, fresh-Mac permissions,
manual UI/runtime compatibility, App Review approval or live study delivery.

## Commit history

Each changed or deleted file was committed separately. Follow-up edits to the
recording test received their own commit. Earlier history is preserved; no rebase,
squash or force push was performed. Commits are local until explicitly pushed.
