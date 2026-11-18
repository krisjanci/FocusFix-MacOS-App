# Analytics badges — 2026-11-18

## Implemented behavior

- Analytics retains its blurred illustrative graphs and Coming soon overlay. A content-width Badges button opens one large badge per row; future badges stay grey with their requirements.
- Eight distinct vector designs progress from a simple teal Joined FocusFix medallion through bronze, silver/turquoise, emerald, gold, sapphire, violet/platinum, and the iridescent 100-day crown crest.
- Local streak milestones are 5, 10, 20, 30, 50, 75, and 100 completed days under the existing 60-minute goal, weekend, and freeze rules. Historical reconciliation supplies the initial awards. Earned milestones never relock.
- Joined FocusFix requires an account. Its persisted identity includes the account-service origin and user ID; guest presentation stays locked. Work badges follow the existing device-local streak card.
- New awards persist their earned, unread, and queued celebration states. The full-window overlay blocks covered controls, blurs the main content, and displays artwork, name, description, and You've gained a badge! Dismissal shrinks the artwork along an arc to the Analytics control; Reduce Motion fades instead.
- Narrow analytics sheets host the celebration above the sheet while its parent is blurred. Other active editors defer the main celebration. Hidden/closed windows retain pending celebrations without forcing the app into the foreground.
- Both Analytics and its Badges entry use the same 7-point red circle as group invitations. Dismissing the celebration does not clear unread state; opening the collection does.
- Earned badge details and celebrations have the LinkedIn logo and Share to LinkedIn. Clicking changes the button to Coming soon without dismissing or sharing externally. Reopening details resets the placeholder.
- Badge details dismiss on a background click or Escape without activating the covered back/collapse controls. A local Escape handler is restricted to its owning app window/sheet and is removed with its view.
- macOS notifications use the exact title You've gained a badge!, the badge name, and a badge-routing payload. Delivery uses existing authorization; clicking the notification requests the badge collection. Reminder cleanup filters by reminder category and excludes newly registered reminders from asynchronous cleanup results.

## Verification

- Debug macOS build passed with `CODE_SIGNING_ALLOWED=NO`, using temporary derived data. The AppIntents metadata notice is expected for this app.
- The complete 37-suite synthetic test run passed. Focused badge tests also passed after the final notification-cleanup change.
- Award tests cover every threshold immediately below/at unlock, repeat evaluation, permanent retention after a break, ordered simultaneous awards, persisted queue/unread recovery, historical backfill without alerts, completed/rest weekends, freeze continuity without extra days, broken historical streaks, and existing progress decoding.
- Controller tests use synthetic tracker/account stand-ins and an injected alert sink. They cover guest/sign-in eligibility, exact native-alert text/payload, duplicate suppression, collection acknowledgement, sequential celebrations, and cleanup races with new break/check-in reminders. They do not send test alerts to the user's desktop.
- Native isolated previews exercised the actual artwork, analytics views, celebration modifier, and controller. Inspected light/dark appearances, full-width entry beneath the graphs, large earned and grey future rows, earned/locked descriptions, 5-day and 100-day celebration artwork, LinkedIn Coming soon in both locations, unread clearing, and main-window/sheet Escape dismissal. The final additional screen-capture attempt failed in ScreenCaptureKit; earlier native captures and interaction checks succeeded.
- System notification display remains subject to macOS authorization and delivery settings; payload and routing are implemented without changing those settings.

## Reproducing the native preview

Run `bash scripts/preview-badges.sh` to build an isolated preview bundle. The script prints its path. Options: `--dark`, `--narrow`, `--legendary`, and `--reduce-motion`. Open the printed app bundle, dismiss its seeded celebration, and use Analytics → Badges. Earn next creates synthetic streak milestones; the narrow sheet has its own synthetic award button.

The preview links `Tests/BadgeTestSupport.swift` instead of the real tracker/account client and suppresses system-alert delivery. Its preferences use a separate bundle identity. This work changes and commits source; it does not replace the installed app or publish a release.
