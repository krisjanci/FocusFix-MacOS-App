# Finding things in my code

I use `FF:` as a searchable label for a feature. Comments explain what each function
does; `// MARK: -` also gives Swift files section headings in Xcode's jump bar.
These are reading aids, not extra features or code that runs.

## Quick search on my Mac

- **Command-Shift-F** in Xcode or VS Code: search across the open project/workspace.
  Try `FF: RESEARCH SHARING`, `FF: SURVEYS`, or a function name like `beginBreak`.
- **Command-F**: search only the file I'm reading.
- **VS Code: Command-P**: type a filename. **Command-Shift-O**: find a symbol in that file.
- **Xcode: Command-Shift-O**: Open Quickly; type a Swift filename or function name.
  The editor's jump bar also lists types, functions and `MARK` headings.

Xcode normally shows the Swift app project, not its sibling `supabase` folder.
For receiver code and setup files, open the whole FocusFix-MacOS-App folder in VS Code.

## Where each feature lives

All Swift paths below are inside `FocusFix/FocusFix/`.

| Search | Files | What I can find there |
| --- | --- | --- |
| `FF: TRACKING` | `ActivityTracker.swift`, `InputMonitor.swift` | Passive Input Monitoring tap, start/stop, input events, session clock and coordination with breaks/surveys |
| `FF: STORAGE` | `RecordingData.swift`, `SavedSession.swift` | CSV writing, one-second mouse summaries, key hold timing, saved sessions and exports |
| `FF: BREAKS` | `BreakPolicy.swift`, `BreakViews.swift` | 25-minute/idle reminder rules, snooze, actual break duration and break controls |
| `FF: SURVEYS` | `SurveyPreferences.swift`, `TimedCheckIn.swift`, `SurveyData.swift`, `CheckInViews.swift` | Saved survey switches, session snapshots, 10-minute opportunities, rating validation, CSV answers and sliders |
| `FF: NOTIFICATIONS` | `NotificationAccess.swift`, `BreakNotifications.swift` | Asking for permission, banners and notification buttons |
| `FF: SESSIONS` | `SessionViews.swift` | Session library and Test tracking window |
| `FF: UI` | `MyApp.swift`, `ContentView.swift` | App windows, main screen, menu bar and appearance |
| `FF: STARTUP` | `LaunchScreen.swift` | Play/pause logo animation and skip/reduced-motion behavior |
| Account services | `AccountAPI.swift`, `AccountController.swift`, `UserProfile.swift` | Supabase authentication, profile sync and account Keychain storage |
| `FF: RESEARCH SHARING` | `ResearchSharing.swift`, `ResearchSharingController.swift`, `AccountViews.swift` | Consent snapshots, ZIP allowlisting, delivery queue, retries and withdrawal |
| Research backend | `supabase/functions/`, `supabase/migrations/` (repository root) | Server consent, private Storage policies, approval and deletion |
| `FF: PRIVACY` | `RecordingNotice.swift`, `RecordingNoticeView.swift`, `PrivacyInfo.xcprivacy` | First-use recording notice, remembered acknowledgement and profile privacy details |
| `FF: RELEASE` | `AboutView.swift`, `scripts/check-release-content.py`, `scripts/verify-release.sh` | Release content and distribution checks on an exported signed/notarized app |

## Some useful exact searches

- `receive(`: how a keyboard, click, scroll or mouse event is handled.
- `move(to`: how cursor travel becomes a summary without saving its path.
- `workDelay`: normal break-reminder delay.
- `schedule(from`: the during-work survey timing.
- `checkDue`: research delivery retries and pending withdrawal synchronization.
- `FocusFixAccountURL`: Supabase service configuration.
- `FocusFixResearchSharingEnabled`: study feature gate, separate from signing in.
- `ResearchArchive`: per-session ZIP allowlist and size limits.

When changing a limit, check the app, Supabase policies/functions, tests and
user-facing explanation together. A matching number in just one file isn't enough.

For cloud setup, use [research operations](supabase/RESEARCH-OPERATIONS.md).
For the retired uploader, see [Cloudflare removal notes](CLOUDFLARE-REMOVAL.md).
