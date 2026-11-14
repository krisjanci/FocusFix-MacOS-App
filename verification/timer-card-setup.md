# Timer-card work setup — 2026-11-14

Implemented through `75c67e7`.

- Removed the bottom Plan session control. Work target is a capsule beside Add tags in the session timer card; the menu-bar entry opens this same target editor.
- Timer tag and target confirmations use Start work while idle or automatically recording Unknown. Active edits use Done and preserve the current recording. Saved-library tag edits remain history edits.
- Opening/cancelling setup does not start work. Recording acknowledgement and Input Monitoring availability remain required. Starting via tags does not edit the last saved session; stale saved tags/target/tint are hidden on the idle timer.
- Target edits preserve observed work credit, including work earned before a target existed. Saving an unchanged target preserves its completion acknowledgement. Custom targets retain the 1–480 minute validation.
- Updated the quick tour and README for timer-card setup.

## Verification

- Full `bash scripts/test.sh`: all 34 synthetic suites passed, including expanded work-target and fractional-retention regressions.
- Final Debug app build passed with code signing disabled and temporary derived data.
- An isolated app exercised the actual tracker setup methods with synthetic storage, an input-monitor stub (no tap or real input collection), disabled account configuration, isolated sharing stores, and test preferences. Manual tag/target starts, automatic Unknown tag/target starts in the existing recorder, active edits, cancellation, unavailable permission, and last-saved-session isolation passed. All four resulting sessions were finalized and retained, with no pending test sessions left.
- Native UI inspection confirmed matching timer-card capsule styling, no bottom Plan session button, Start work in both idle editors, Done in the active target editor, tag confirmation changing the status to Working, target editing keeping the current tag/session, and End work restoring the idle setup chips.
- The smoke run exposed a fractional-duration reader discrepancy: JSONSerialization can round a value one ULP differently from JSONDecoder. New-schema metadata durations now use the same decoder as recording contracts. Strict duration equality remains; tests cover subsecond saves and reject genuinely mismatched bounds.
- Each changed file and follow-up iteration was committed separately. The installed app was not replaced or published.

Button press-animation feedback was discussed only and remains unimplemented, following the user's request for an opinion before making that change.
