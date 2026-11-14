# Compact break setup and stable work spacing — 2026-11-14

- Break setup measures its padded content and uses that height, capped at 600 points with scrolling for longer forms. Width is 440 points instead of 480. The default form rendered at approximately 297 points tall instead of 520, with no empty lower half.
- Start break retains its prominent native style and press feedback, with the large control size.
- The action row immediately follows DailyProgressCard. Reminders, break history and notices follow the actions rather than inserting space between progress and actions.

## Verification

- Final production Debug build passed with signing disabled.
- An isolated preview built from the updated ContentView and BreakViews passed. Its input monitor is a synthetic stub, account configuration is disabled and session storage is temporary.
- Native screenshots before and after Start work showed the same 20-point gap between daily progress and the action row. Returning from a break preserved that gap, with last-break review below the actions.
- The default break sheet fit its content; selecting Custom expanded the sheet to fit the additional duration field. Start break began the selected five-minute break; I'm back restored work and End work returned to Ready.
- Each implementation file was committed separately. The installed app was not replaced.
