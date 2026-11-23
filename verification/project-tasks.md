# Projects and tasks verification — 2026-11-23

## Implemented behavior

- Task uses a document icon and replaces the full main canvas in place. Profile controls, app logo/title, recording-status statement, streak, appearance control, and large work buttons are hidden from the task canvas and its accessibility tree. The original main content remains the size reference, so navigation does not resize the window. Groups/Analytics and their footer controls remain independent. Actionable permission/error messages remain available within tasks.
- A single bordered arrow-left button, using the same 28 × 22 label frame and caption/spacing treatment as Badges, sits beside Projects or the selected project name. It returns from a project to Projects and from Projects to the timer. Project editing cancels one level back. Native menu Escape is consumed before page navigation. No separate no-project action appears in the task interface; ordinary timer Start work infers no project.
- Projects have stable IDs, editable colors, and ordered task checklists. Exactly one built-in Random Tasks project has a protected name and cannot be deleted. Legacy catalogs gain it atomically; an existing matching folder is adopted without changing its ID/tasks. Other project names remain editable, and deletion asks before removing entries. Task-row play actions explicitly start or switch work; browsing/editing never start recording. Each project offers Untasked Work.
- Explicit successful work actions promote their project to the front and persist lastWorkedAt. Opening, editing, completion, or automatic assignment reconciliation does not promote projects. Drag/drop and Move up/Move down allow manual project order, including Random Tasks. Manual order survives reload until a subsequent work action promotes a project again.
- A tick appears immediately on completion. At three seconds the row fades, shrinks to 85%, swipes sideways, and settles after older completed tasks. Canonical order stays independent of completion; reopening restores that position. Dragging supports placement before/after rows, including the last row. Menus and accessibility actions support Move up/Move down. Reduce Motion fades and reorders without shrinking or swiping. Pending moves cancel on uncheck/deletion/navigation and completion dates survive relaunch.
- Starting from a task owns the exact new Work boundary. Switching a task/project checkpoints recording without resetting the work target or timer. Completing/deleting the active task changes subsequent work to Untasked Work; deleting its project changes to no project. Catalog renames/colors affect future snapshots and the current tint without rewriting earlier history. Reopening a task does not resume it automatically. New work periods start without a project; breaks retain the assignment.
- Assignment history intersects snapshots with observed normal-phase Work coverage. Breaks, check-ins, awaiting return, Unknown context, unavailable gaps and uncheckpointed tails are excluded. Segment rotation uses the same logical elapsed basis and carries the current choice forward.
- Local catalog and assignment files save atomically. Read/save failures keep existing bytes/published state and expose errors. Legacy sessions remain readable without assignment sidecars. Old tags remain in history/exports; new work has no tag-selection route.
- The private sidecar is included in local folder exports. Development/research upload allowlists exclude it, and names are absent from shared recording metadata and social progress. History reads detailed coverage off the main thread on request.

## Automated results

- `bash scripts/test.sh`: all 45 test groups passed, including existing recording lifecycle, coverage, retention, privacy, exports, tags, targets, tour and social-progress tests.
- Updated `WorkAssignmentsTests` additionally compiled and passed after adding assertions against an actual generated development ZIP and failed sidecar writes. The ZIP payload contained neither test project nor task names.
- Project tests cover trimming/validation, custom colors, persistent IDs/order, completion/reopening, placement before/after rows, renaming/deletion, corrupt catalogs and failed writes. Refinement tests also cover protected default seeding/deletion/rename, migration and adoption preserving IDs/tasks, recent-work promotion, no promotion on edits/completion, manual moves in both directions, persistent manual override, later work promotion and failed ordering writes.
- New assignment tests cover exact work boundaries, switches, breaks, Unknown intervals, check-ins/unavailable gaps, observed totals, local exports, archive privacy, crash-tail clipping, segment rotation, frozen names, missing/corrupt sidecars, finalized writes and rollback after write failure.
- Final Debug native app build passed with signing disabled and a temporary derived-data directory. Compiler plugins require an unrestricted build process in this environment; the successful build used that access.
- `git diff --check` passed. Every implementation commit changes exactly one file, as requested.

## Native preview checks

Run `bash scripts/preview-projects.sh` and open the printed app path. This links the real project store, checklist view, journal types and tint components to a synthetic in-memory recorder. It never links the real recorder/account services; data lives under a unique temporary directory.

Observed through the native UI:

- Project drill-in, task start and immediate Untasked Work continuation on active completion.
- Immediate green tick at original position; delayed completed-row placement and normal-mode shrink/muting; unchecking restores the prior checklist slot.
- Rapid complete/reopen leaves the task incomplete and cancels the delayed move.
- Reduce Motion uses full-size muted completed rows with no swipe/shrink. Its preview toggle overrides only the view's motion choice, without changing system settings.
- Keyboard task creation and inline rename/save; accessible Move down changes canonical ordering.
- Light and dark appearance, scrollable longer lists, retained project navigation, and an independent open side panel. Refinement preview shows one back button beside Projects/the project name, no app chrome or large Start button in tasks, and no no-project action. Random Tasks options omit Delete. Opening a project leaves its position unchanged, starting task work promotes it, and an accessible Move up can manually override that order. Escape dismisses a project menu without leaving Projects.
- With the preview side panel open, captured task and timer views both measured **1542 × 1214 pixels**; switching back to Task retained the selected project. The refined full-canvas preview was measured again with the same **1542 × 1214** result for both pages. Production ContentView retains the entire original main layout as the size reference while making its space available to tasks.

The preview recorder is intentionally synthetic. Real input permissions, accounts, notifications and production recordings were not changed during UI verification. Their existing lifecycle tests remain green; the native app was built, not installed over the running app or published.
