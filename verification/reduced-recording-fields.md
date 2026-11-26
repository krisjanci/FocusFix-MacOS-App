# Reduced recording and export fields — verification

Date: 2026-11-26 (America/New_York)

Baseline: `bd3491b`. Implementation and test changes verified through `33668d3`.

## Result

New recordings use schema 12 (`focusfix.recording.v12`); daily exports use `focusfix.daily_tables.v3`. Input and movement rows omit phase and since-break measurements. Inputs retain repeat, hold duration, scroll precision, input timestamps and existing measurement precision. Movement retains every row and its distance/count, with start/end rounded to whole seconds and since-movement rounded to at most two decimals. Decimal rounding uses nearest with ties away from zero, without intermediate floating-point or six-decimal rounding. Blanks and zeroes remain distinct.

Existing recordings are not rewritten. The new exporter handles older recordings with the same reductions, using their original timestamps for sorting, day grouping and cross-day references before rounding. Omitted values and discarded movement precision are not copied into export metadata. Other recorded fields, JSON details and revisions remain reconstructable.

Exact app coverage is stored separately in `observed_coverage.json`, using merged adjacent intervals with equal phase. Capture gaps remain gaps. The writer synchronizes this coverage before advancing durable bounds or finalizing. Readers use exact coverage for schema 12 and the original movement coverage for schema 11. Missing or malformed new coverage does not fall back to rounded measurements. Exports include the compact coverage once in metadata.

## Measured plain export size

The fixed synthetic fixture contains the same 10,000 keyboard events and 100 movement intervals used for the pre-change baseline. Totals include all daily tables, sessions lookup and metadata, including the new coverage document. No compression is counted.

| Format | Total bytes | Files |
|---|---:|---:|
| Previous narrow export (v2) | 312,981 | 5 |
| Reduced export (v3) | 252,619 | 5 |

Saving: **60,362 bytes, or 19.29%** relative to v2. This fixture is mostly keyboard events; savings depend on the actual mix of inputs, movement and metadata. This percentage is not a claim about compressed internal archives.

## Validation

- `bash scripts/test.sh`: all **51** expected test groups ran in order and passed. Final log: `/tmp/focusfix-reduced-final-tests.log`.
- Additional focused midnight/checkpoint checks passed in `/tmp/focusfix-reduced-edge-tests.log`.
- Unsigned Debug macOS build passed using `xcodebuild -project FocusFix/FocusFix.xcodeproj -scheme FocusFix -configuration Debug -destination 'platform=macOS' -derivedDataPath /tmp/focusfix-reduced-build CODE_SIGNING_ALLOWED=NO SWIFT_ENABLE_EXPLICIT_MODULES=NO build`. Log: `/tmp/focusfix-reduced-build.log`.
- Regression checks cover retained field reconstruction, explicit omissions, exact decimal ties, scientific notation, blanks/zeroes, coincident rounded bounds, historical midnight grouping, DST, simultaneous events, source ordering, checkpoint tails, fractional coverage, check-ins, capture gaps, original/archived history, v11 crash recovery and unchanged progress totals.
- The social-progress and survey fixtures were updated to supply/assert the new exact coverage instead of removed movement phase fields.
- `git diff --check` passed. All 18 implementation commits through `33668d3` changed exactly one file each; this report is committed separately.

Backend analysis and existing recordings/exports were left unchanged. Unrelated concurrent edits to the tour/UI and README were excluded from these commits. No app installation or live recording was performed; re-export using the updated build to obtain v3 tables.
