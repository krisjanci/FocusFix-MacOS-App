# Narrow daily CSV exports — verification

November 25, 2026. Original source baseline: `f99fe15`. Final implementation and schema documentation verified through `928799c`.

## Delivered layout

`focusfix.daily_tables.v2` exports plain folders on demand. Each local date has only populated tables: inputs, movement, breaks, checkins and changes. Shared `sessions.csv` and `metadata.json` hold original identifiers, clock anchors/origins, durable bounds, field mappings and remaining provenance/settings. There is no summary table, ZIP package or live secondary CSV copy. Backend analysis was not changed.

High-volume tables have no source JSON copies, repeated UUIDs, UTC/local timestamps or assignment names. Known numeric fields lose only redundant decimal zeros; strings, blanks and zeroes remain distinct. CSV quoting is byte-aware, including CRLF and quoted Unicode text. Spreadsheet protection has an explicit inverse map.

CSV source descriptors preserve original headers, constants and original record order when sorting changes it. `identity_csv_fields` declares each short-reference lookup domain. JSON scalar moves and lexical remaining JSON preserve all fields and original numeric precision. Document collections and JSONL record lists retain original order. Cross-day references live in metadata; full interval bounds remain in one source row. Archived legacy recordings use the original folder's start anchor, not the temporary extraction directory's creation date.

## Validation

- All **51 synthetic executable test groups passed** using `bash scripts/test.sh` outside the sandbox so SwiftUI macros could compile.
- After the final unused-header/identity-schema cleanup, SessionStorageTests, DailyExportSizeTests and DailyTimelineTests passed again against the final source.
- The independent inverse reader reconstructs every source CSV field and JSON document/log value from only the exported tables and schema. It checks historical workload/productivity protocols, large integers, high-precision JSON timestamps, empty/null/missing fields, changing identifiers/protocols, unknown columns/logs, numeric-looking text, quoted multiline Unicode/CRLF, duplicate events, original ordering, mixed compressed/uncompressed sessions, fractional segment origins, midnight, DST, zero-record categories and failure cleanup.
- The final unsigned Debug macOS app build passed with `CODE_SIGNING_ALLOWED=NO SWIFT_ENABLE_EXPLICIT_MODULES=NO`, using derived data at `/tmp/focusfix-narrow-build`.
- `git diff --check` passed. Every implementation iteration was committed with one changed file per commit.

## Uncompressed size comparison

DailyExportSizeTests uses the same fixed 10,000-input-event / 100-mouse-interval recording for both formats. The v1 baseline was measured before replacing the implementation. Totals include every exported CSV and all lookup/metadata files; no compression is applied.

| Format | Total bytes | Files |
| --- | ---: | ---: |
| Wide daily timeline v1 | 7,108,139 | 2 |
| Narrow daily tables v2 | 312,981 | 5 |

The fixture is **95.60% smaller**. Its three populated categories have 10 input columns, 8 movement columns and 7 change columns. Empty break/check-in sources add no CSV files or unused columns; their original headers remain reconstructable from metadata. The test enforces at least a 75% total-size reduction, rather than asserting timing on specific hardware.

The final fixture export took approximately 1.38 seconds in an unoptimized synthetic test; results vary with recording content and hardware. No updated app was installed or launched against live recordings. New exports take effect when the updated build is used; existing export folders are not rewritten.
