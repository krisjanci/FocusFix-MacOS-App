# Analytics panel and simplified controls — 2026-11-14

Implemented through `8125192`, including the follow-up request for a direct appearance button instead of a menu.

## Verified

- `bash scripts/test.sh`: all 34 synthetic test suites passed. The new export suite covers single/selected/all exports, current and historical revision labels, reminder and study-prompt contexts, streamed JSONL across chunk boundaries, unchanged IDs/times/CSV/metadata/free text, byte-identical originals, malformed-log cleanup, and symlink rejection.
- Shared panel tests cover Groups → Analytics → Groups, repeated active-button clicks, closing, narrow-screen sheet selection, display adaptation, and screen-clamped geometry. Expanded width remains 850 points and compact width 490 points.
- Final Debug build passed with `CODE_SIGNING_ALLOWED=NO` and a temporary derived-data directory. Xcode's expected warning that AppIntents metadata extraction was skipped is unrelated to these changes.
- An isolated preview built from the current view sources used synthetic tracker state, disabled account configuration, and separate preferences; it did not start activity capture or load saved recordings. Native UI inspection confirmed Analytics/Groups replacement at the same 1700-pixel window width on a Retina display, and panel-close restoration to 980 pixels.
- Native UI inspection confirmed the missing secondary recording timer and Context control, the bottom-right Analytics button, blurred placeholder charts with Coming soon, and the current appearance symbol at the former Context location.
- Clicked System → Light → Dark → System without any menu. Checked saved selection across a preview restart and immediate theme changes after moving preference observation into each window view. Inspected the Analytics layout in both light and dark appearances. The appearance control exposes its current value and next action to accessibility.
- Reduce Motion continues to disable the SwiftUI transition and native window-frame animation. No analytics data loading or chart interaction was introduced.
- Source inspection confirms that live context changes are private to the tracker and invoked only by existing work-start/planned-start and work-end paths. The non-work notification action and history editor are absent. Legacy decoding and low-level history APIs remain for compatibility, and hosted archive construction is unchanged.

## Delivery boundary

Each implementation/test/document file was committed separately, including follow-up iterations. This work changes source and local export behavior; it does not replace the installed app, sign/notarize a release, or publish anything.
