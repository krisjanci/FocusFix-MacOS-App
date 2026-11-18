# Recording reliability and efficiency verification — 2026-11-18

Scope: the five requested fixes to the macOS app. All reproduction fixtures and benchmarks use temporary synthetic files and mocked account transports. No release, deployment, signing, version bump, or push was performed by this work.

## Changes and evidence

| Requirement | Implementation | Regression evidence |
| --- | --- | --- |
| Independent interrupted-recording recovery | `SessionFiles.recoverPending` catches failures per entry, validates metadata before modification, continues valid recovery, and reports partial failures using the existing warning text. The tracker retains the warning while displaying compatible recordings. | `RecordingLifecycleTests` covers valid entries mixed with absent metadata, malformed JSON, invalid contracts and invalid metadata, using different name orders. Damaged file bytes remain unchanged. Recovery stops at checkpoint 2 despite a later raw tail. A crash between final contract and metadata saves remains recoverable. The original implementation failed the mixed-batch test. |
| Deleted upload source cannot block later recordings | Development delivery acknowledges a missing direct recording folder only after confirming the recordings root is accessible. Queue changes are persisted before continuing, with in-memory rollback on persistence failure. Hosted-object lookup remains first; permission, storage and archive failures retain the existing retry path. | `DevelopmentDeliveryTests` starts with two queued recordings and deletes the first. It verifies temporary network failure retains the valid second item, relaunch delivers it, queue removal survives reload, and a hosted archive with no local folder is acknowledged without reupload or hosted deletion. The original implementation failed the relaunch test. |
| Reduce full-ledger work during recording without weakening durability | Work updates write atomic per-segment revision files in an account-specific sidecar directory. Full snapshots compact those updates only after the snapshot write succeeds. Main-actor ordering prevents an older write from overtaking a newer one. Existing ledger JSON remains compatible. | `SocialControllerTests` verifies live work leaves the full ledger unchanged and replays on reload. `RecordingEfficiencyTests` checks revision 30 survives replay; an equal-revision journal left after acknowledgement cannot resurrect work. Account-cache deletion removes the sidecar too. Existing social tests cover account isolation and stale network responses. The original implementation failed the no-full-ledger-rewrite assertion. |
| Reuse unchanged historical reconciliation | An ephemeral cache is keyed by local day and Calendar. Historical work edits, protection-start changes, direct freeze changes, date rollover and Calendar changes invalidate it. Today's work does not change already-allocated historical freezes. Cache state is excluded from encoding and semantic equality. | `DailyProgressTests` compares cached results to freshly decoded cold ledgers across weekends, DST, month/year boundaries, timezone changes and late additions/removals. It checks streaks, freezes and tokens, plus that 100 identical calls perform no extra history walks. `BadgeAwardsTests` checks matching badge awards across DST/month boundaries and corrections. |
| Coalesce scans and batch deletion | `SessionLibraryLoader` cancels obsolete wrappers and their detached workers, checks cancellation before starting work and publishes only the current result. `SessionFiles.inspect` checks cancellation between folders. One batch deletion retains whole-selection validation, per-item revalidation, partial failure reporting and one final tracker refresh. | `SessionLibraryLoadingTests` verifies 200 rapid requests start one scan, superseding a running scan cancels its worker, a 200-recording batch reports 199 successes and one simulated failure, and an active recording prevents every move. The view subtracts only successful IDs from selection. |

## Measured performance

Command: `bash scripts/benchmark-recording.sh` (optimized Swift build).

| Synthetic workload | Previous work pattern | Updated work pattern |
| --- | ---: | ---: |
| Reconcile ten years of history | 36.678 ms/call | 0.005 ms/call with unchanged history |
| Main-actor update with 2,000 recording segments | 33.075 ms/update | 1.766 ms/update |
| Full-ledger replacements over 30 work updates | 30 | 0 |
| Durable segment replacements over those updates | 0 | 30 |
| Encoded bytes over those updates | 41,188,344 | 9,102 |

The previous patterns are measured by forced cold reconciliation and the original full-ledger encode/atomic-write operation on equivalent synthetic values. Timings vary by Mac and load; byte and write counts are deterministic for this fixture. The optimization preserves an atomic durable write for every work update rather than postponing writes with a debounce. Full snapshots still occur at existing synchronization boundaries; small segment writes remain synchronous to preserve durability.

## Final checks

- `bash scripts/test.sh`: all 40 suites passed.
- Extended `BadgeAwardsTests`: passed after adding explicit cache/cold badge parity coverage.
- `npm test` in `supabase`: all 10 tests passed.
- `npm run test:database` in `supabase`: passed against the current local migrations and database regression scripts.
- Unsigned Debug build: `xcodebuild -project FocusFix/FocusFix.xcodeproj -scheme FocusFix -configuration Debug -derivedDataPath /tmp/focusfix-fixes-build CODE_SIGNING_ALLOWED=NO build` succeeded.
- `git diff --check`: passed.
- The session-library view body, layout, wording, controls and presentation code before its deletion action are byte-for-byte unchanged from baseline `26ee5a7`. Only action implementation changed in that view. Other visual assets, view layouts, recording formats, project settings and version information were not changed by this work.

## Limits

No live-account upload, real Input Monitoring capture, physical power-loss test, signed release package, or manual visual walkthrough was performed. Crash behavior is verified with deterministic on-disk intermediate states. Cancellation stops between synchronous file reads; an individual in-progress filesystem/JSON operation is not forcibly interrupted. This work does not claim to eliminate all occasional full-history storage or computation.

Changed files were committed individually through each implementation iteration. Concurrent, unrelated weekend-streak database/screenshot work was left alone and was not included in this work's commits.
