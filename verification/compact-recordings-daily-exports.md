# Compact recordings and daily exports — verification

November 25, 2026. Verified app source through `edb7351`; original baseline `9208d34`.

## Delivered behavior

- Completed current and legacy recordings use verified lossless ZIP storage when the archive plus index is smaller. All original file bytes, precision and recording schemas remain recoverable. Active capture/checkpoints retain their existing format. Startup handles saved history and interrupted cleanup; finalization/rotation schedule newly saved recordings.
- Single, selected and all-session exports produce one chronological `activity-YYYY-MM-DD.csv` per day and one `metadata.json`, using a single timezone captured at export start. Original source values/provenance remain available; Work intent and intervention phase remain separate. Midnight continuation references repeat no measurement totals.
- Start-of-day prompts, views, controller and settings are removed. Launch cleanup deletes the old local responses and preferences, retries on failure, and leaves timed session check-ins in place.
- Hosted archive formats, file allowlists and consent/qualification gates remain unchanged. Backend analysis is excluded at the user's request; temporary analysis-adapter changes were reverted without changing the user's existing backend work.

## Checks

All **49 synthetic executable test groups passed**. `bash scripts/test.sh` passed the first 37 groups; the sandbox blocked SwiftUI macro compilation at BadgeSharingTests. The remaining 12 groups, including BadgeSharingTests, passed using the same runner outside the sandbox with `FOCUSFIX_TEST_FILTER`. No app source changed between those runs.

The new tests cover exact file recovery, net size reduction, rollback before the archive commit point, interrupted cleanup and unused archive removal, legacy schemas 1–10, checkpoint-tail recovery, corruption and unsafe files, archived metadata/context edits, task totals, unchanged hosted allowlists, deletion, daily merging, simultaneous events, quoted multiline/UTF-8 records crossing 64 KiB, skipped answers, repeated requests, legacy breaks, DST, all export entrypoints and incomplete-export cleanup.

The unsigned Debug macOS build passed:

```sh
xcodebuild -project FocusFix/FocusFix.xcodeproj -scheme FocusFix \
  -configuration Debug -destination 'platform=macOS' \
  -derivedDataPath /tmp/focusfix-storage-build CODE_SIGNING_ALLOWED=NO \
  SWIFT_ENABLE_EXPLICIT_MODULES=NO build
```

`bash scripts/benchmark-recording.sh` passed. `git diff --check` passed. Every implementation commit changes one file; verification documentation is committed separately too.

## Measurements

Synthetic unoptimized storage/export tests, under concurrent build/test load:

| Measurement | Result |
| --- | --- |
| Raw recording → archive plus index | 318,912 → 39,016 bytes; about 87% smaller |
| History metadata read | Raw 0.563 ms; archived 1.920 ms per session |
| Daily export with 10,000 input events | 3.152 seconds |

Existing optimized recording benchmark: ten-year history reconciliation 37.604 ms full / 0.003 ms cached; a 2,000-segment ledger retained equivalent progress and durable latest work, with no full-ledger replacements during 30 live updates.

Compression and timing vary with recording content and hardware. The updated app was built but not installed or launched against live data. Existing-session compaction and retired-survey cleanup run when the updated app launches. Signed runtime, power-loss and long-duration hardware qualification remain separate from these synthetic checks.
