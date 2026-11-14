# Button press feedback — 2026-11-14

Implemented through `b0288f6`.

- Applied shared feedback to 142 in-window buttons, menu openers and links, including Start/End work, Sessions, Add tags, Work target and appearance. Existing native styles, roles, shortcuts and action timing remain in place. Native menu items and system-dialog actions keep their native feedback.
- A press eases to 97% size over 60 ms, then returns with a 240 ms spring (damping fraction 0.72). A 70 ms minimum visual press makes quick clicks visible without delaying the action. Disabled controls and Reduce Motion do not scale.
- One local app-event observer returns events untouched. It does not observe other applications or collect/store input. Registration uses weak native markers; release, drag-away, focus loss, menu dismissal, disappearing controls and reparenting clear press state. A common-mode release check handles native tracking loops.

## Verified

- Final full Debug build passed with signing disabled and temporary derived data.
- All 35 suites in `bash scripts/test.sh` passed, including the new hit-area regression.
- The user's report that shrink was not visible exposed AppKit's oversized visibleRect for unclipped background views: every marker could match a click anywhere in the window, selecting a nearby small icon. Hit testing now requires both actual button bounds and the visible region. The regression uses rectangles captured from the native preview and verifies that exactly the intended control matches.
- In a uniquely named isolated preview, a physical primary-button click changed its action counter 0 → 1. Slow inspection showed that same button visibly compressed and then returning to its original size. Only the test preview's hold was extended to two seconds for frame inspection; production retains the 70 ms visual minimum.
- Reduce Motion: the next physical click changed the action counter 1 → 2 with unchanged size; all feedback markers were ineligible. Disabled-button click and drag-away cancellation left the counter at 2. Return then invoked the existing default action once, changing 2 → 3.
- Opened a main-screen preview using the current production feedback source at normal speed, synthetic recorder storage and an input-monitor stub. Native Start work and End work clicks changed status correctly and saved the synthetic session without errors. This preview remains separate from the installed app.
- Every implementation file and follow-up iteration was committed separately. No installed-app replacement or publication was performed.
