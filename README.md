## Private groups and automatic streak freezes

Groups now supports private invite codes, creator controls, and separate all-time Work and Healthy habits leaderboards. A 60-minute work day earns one work point; a day with a completed one-minute break earns one healthy-habit point. Scores start at joining, and weekends can earn points. The existing weekday streak receives three automatic monthly freezes, without rollover or consecutive calendar-day use. Frozen days add no points or streak days.

Choose **Groups → Enable group progress** to sync account-scoped summaries; guest history stays local and research participation is separate. The updated Quick tour explains groups, scoring and freezes using practice data. The group backend is deployed to the configured FocusFix project. See [Social setup](supabase/SOCIAL-SETUP.md) for verification results and migration instructions for other projects. **Test tracking** and **Quick tour** are available directly in Profile.

## Research/privacy update — October 26, 2026

Profile now contains identity/account actions. **Settings → Privacy & Research**
contains the recording preference, optional surveys, complete study consent,
manual participant approval status and per-session delivery controls. First launch
offers Enable recording or Not now. Neither choice grants Input Monitoring or
starts recording. Switching recording off stops the session and blocks all Start paths.

The live app no longer exposes enrollment keys or starts the legacy Cloudflare
uploader. Its saved development state is preserved. The account-based path requires
server-recorded, versioned consent as well as approval. The lifetime cohort cap is
50 even after account deletion. Offline withdrawal is durable and blocks subsequent
uploads until synchronized. Research-data deletion is separate from local deletion
and leaves a private researcher task for downloaded copies/model datasets.

Accounts are configured; the privacy manifest declares account collection. Research
remains disabled until the actual institution determination, consent, retention and
public study URL are configured. There is no fabricated approval or retention period.

Current implementation and operating instructions: [Research operations](supabase/RESEARCH-OPERATIONS.md).
Current App Store copy, privacy categories and remaining requirements:
[Submission package](STORE-SUBMISSION.md). The historical notes below describe earlier
implementation stages; these current documents supersede their enrollment and
local-only Release descriptions.

![FocusFix logo](Assets/FocusFixLong.png)

# FocusFix-MacOS-App
Evaluating Personalized Microbreaks to Reduce Mental Fatigue While Maintaining Productivity

## Current app: activity collector and rule-based breaks

This version collects local behavior data and recommends breaks using a timing/idle
rule. It collects brief fatigue/self-reported productivity check-ins. It does not predict fatigue with
ML. Optional research uploads require manual researcher approval and explicit versioned consent. The included
upload service is deployed and enabled for a controlled development test. Debug builds
contain its URL and sharing defaults to off. **Release has no legacy research receiver**:
legacy uploads and enrollment are disabled even after a development opt-in. Optional
Supabase accounts and per-session ZIP delivery are prepared but unconfigured; see
[the Free-plan setup guide](supabase/SETUP.md). Outgoing HTTPS is allowed for those
features, but no account request occurs until configuration and explicit sign-in.
A full app-session upload test is still needed before any research release.
The reminder rule is a prototype to evaluate, not evidence that fatigue is reduced.

**Not ready for a public app download yet.** See [my release checklist](RELEASE.md)
for signing, notarization, clean-Mac testing and the separate study approval steps.

For finding/editing a feature, I use [my code map](CODE_MAP.md). It lists the searchable
`FF:` comments, which files do what, and Xcode/VS Code shortcuts. For connecting the
bucket, use [the beginner upload setup guide](upload-service/README.md#connect-cloudflare).
That guide also explains why per-session uploads are reasonable and why R2's free
allowance and budget alerts are **not** a guaranteed spending cap.

### Run it

On launch, the muted play logo holds for 0.9 seconds before a pronounced press,
bounce and clockwise quarter-turn into the full-color pause logo. The pause symbol
presses again and shrinks away while the four ring pieces grow, spread outward and
fade to reveal the app underneath. The full sequence takes about 3.7 seconds and
plays once per app launch. Click to skip; Reduce Motion skips it automatically.
Reopening the main window doesn't replay it. This is visual only, not a loading
operation, and it doesn't start recording or change any session timers.

1. Open `FocusFix/FocusFix.xcodeproj` in Xcode. Select FocusFix → My Mac.
   Debug supports enrolled research tests; do not distribute it. Research setup stays
   locked at launch until explicitly unlocked in the profile.
   Use an unconfigured Release for local recording checks. Both configurations target macOS 14 or later;
   runtime compatibility still needs testing on each supported system.
2. Press **Start session**. On first use, review the recording/privacy notice and
   choose **I understand**, then press Start again. **Not now** records nothing.
   The notice is also available in the profile. Start requests **Input Monitoring** if needed.
   Enable FocusFix in System Settings → Privacy & Security → Input Monitoring.
   **Enable Input Monitoring** is the single setup button: it requests the app entry
   and opens the right Settings page. Turn on FocusFix there, then quit and reopen
   it if macOS asks. FocusFix cannot grant itself permission. Debug, Release and older
   copies can have different entries; older builds used Accessibility.

   For a development build that still fails to appear, add the exact built app using
   **+** in Input Monitoring settings. Repeated local builds are not a substitute
   for testing a stable, developer-signed release.
3. If the starting survey is enabled, rate how mentally tired you feel or choose **Skip & start**.
   Then work normally. Close the window if you like: recording continues, with controls
   in the menu bar. Nothing starts automatically on launch.
4. Choose **Stop & save**. Sessions are saved automatically; you don't need to export
   after every recording. Open **Sessions** to browse previous recordings, select one,
   then choose **Export…**, **Show in Finder**, or **Delete…**.
5. **Test tracking** opens a separate window with live individual-event and
   mouse-interval counts. It doesn't start a separate recording; testing during a
   session adds events to that session. Close it when you're done checking.
6. Use the appearance menu in the main window to choose **System**, **Light**, or
   **Dark**. The choice is remembered and applies to all FocusFix windows.
7. Choose **Enable notifications** on the main window's reminder card, then Allow
   in the macOS dialog. If notifications or banners are off, the card offers
   **Open notification settings** instead. Enable FocusFix and choose Banners or Alerts.
   The card refreshes when you return to the app and disappears when banners are enabled.
   Recording is still allowed without notifications; the same break actions remain
   in the app and menu bar. Focus / Do Not Disturb and
   macOS notification settings may hide or delay banners; the app doesn't override them.

Sessions are automatically saved inside the app sandbox, normally under
`~/Library/Containers/io.github.krisjanci.FocusFix/Data/Library/Application Support/FocusFix/Sessions/<session-id>/`.
Use **Sessions → Show in Finder** to locate the actual folder. Debug builds use
`io.github.krisjanci.FocusFix.debug` and a separate container. Old unsandboxed
recordings are not moved or deleted; export them from the old build before changing
installations. No existing participant identity is automatically migrated.
Each new session has five CSVs and `session.json`. A new session never replaces an old
one. Old sessions appear in the Sessions window after relaunching the app.
Keep recordings out of the repository and personal cloud storage if your study
or dataset agreement prohibits it. Git ignore rules cover these output filenames,
but renamed data could still be staged accidentally.

### Quick tour

Choose **Quick tour** from Welcome, Profile, Help, or the menu bar. A short practice
tour appears inside the current main-window bounds, without resizing the window.
A spotlight reveals one control at a time; click it to try a safe example. Seven
short stops cover starting, planning, work time, breaks, daily progress, saved
sessions, and your profile. Captions have at most eight words.

**Practice · nothing saved** identifies the demo. Only the highlighted control,
Back, Close, and occasional Next/Done actions are available. Return activates the
current action; choose a duration with the keyboard or mouse. Command-[ goes back,
and Escape closes. Each replay starts fresh; Back returns to the previous stop's
starting state. Editing the example name never changes your profile.

The demo uses in-memory values and shared presentation components, with no recording,
storage, credentials, permission requests, file pickers, or network services. Existing
recordings continue underneath, and real menu-bar Stop & save stays available. Pending
recording/check-in sheets finish before a requested tour appears. On exit, your actual
onboarding, account and recording state is restored unchanged.

Spotlights pulse briefly, scenes fade smoothly, and saved/finished actions show
animated feedback. Reduce Motion displays immediate/static results. Captions use
measured text sizes and move into a separate instruction panel when needed. The
practice area scrolls to keep the current target reachable as the window resizes;
the tour never resizes the window. The detailed recording, permissions, research, progress,
and export instructions remain in the sections below.

### Welcome and guest access

After the intro animation, the first launch offers **Create account**, **Log in**,
and **Use as guest**. Guest mode is remembered: later launches open the main app
directly, and account options remain in Profile. Guest mode includes local profiles,
recording, surveys, saved sessions and progress. It never opts into research sharing.
The checked-in build has no account service configured, so account buttons explain
that online access is unavailable and Guest remains usable.

**Keep me signed in** is checked by default in account forms. After a successful
sign-in with that choice, future launches restore the account from Keychain after
the intro; macOS may ask for Keychain access. Failed restoration offers retry,
login or Guest. Choosing Guest cancels pending authentication and ignores late
responses. Leaving the choice off keeps the new session in memory only, without
saving its tokens for automatic restoration. Signing out disables automatic restore
and leaves local recording available as a guest.

Newly created accounts offer optional name/avatar setup after email confirmation;
**Skip for now** enters the app. Nothing starts recording or requests Input Monitoring
before a recording action. A menu-bar Start action during onboarding shows the
welcome window first.

### Personal profile

Open the profile button at the top left, then click your name or **Add your name**
to edit it in place (1–40 characters). Import a PNG, JPEG, HEIC or TIFF photo under
10 MB by clicking the avatar circle's camera-plus badge. Click the same circle to
replace a photo; **Remove photo** restores the placeholder or an existing saved icon.
Photos are cropped to a 256×256 PNG and re-encoded without source photo metadata.
**Save profile** applies your changes; **Cancel** discards them. Name and photo choices
persist after relaunch. Icon and color selectors are no longer shown.

Without an account, the editor saves only on this Mac in `FocusFix/profile.json`.
Configured builds also offer email/password accounts, confirmation/recovery codes,
private account profile sync, sign-out and account deletion. The checked-in build
has blank public service settings, so online controls explain that it isn't connected.
Local and account profiles stay separate; signing in never silently uploads an old
local name/photo. Explicit Save syncs an account profile. Session tokens use Keychain;
passwords are not persisted. Automatic restoration only follows a successful sign-in
with Keep me signed in selected. Continue with saved account is also available
as an explicit action in the account form. Names and photos are excluded from research ZIPs and recording metadata.

Optional per-session research delivery uses a separate opt-in for new sessions. It sends
one ZIP per completed session to private Supabase storage while signed in and running.
Sharing requires researcher approval (50 selected participants by default) and an
explicit participant opt-in; interest requests alone share no recordings. Failed deliveries
stay local and can be exported. The integration doesn't enable billing, use email
to transport recordings, or delete the old Cloudflare service. Deployment, free-tier
limits, privacy review and end-to-end verification are in [supabase/SETUP.md](supabase/SETUP.md).

### Per-session planning and welcome preview

Starting a session opens **Before you start**, whether you use the main window or
the menu bar. The fatigue question appears only when the pre-session survey is on.
**Plan session** adds an optional work target: 30, 60 or 90 minutes, or a custom
whole number from 1–480. It opens at 60 minutes; **Remove plan** clears it. Each
start attempt begins untargeted, and cancelling discards all choices. Old global
work-target preferences are ignored. Skipping fatigue keeps your selected plan.

Work uses the daily progress clock, including quiet reading and excluding breaks,
surveys, sleep and screen lock. The timer and menu show **Planned session** separately
from the fixed daily goal. At the target, **Plan complete** offers **Stop & save**
(the normal save flow) or **Keep going**. Recording continues until stopped. Keep
going acknowledges this session's reminder without changing its work target.

Click your displayed profile name (or **Add your name**) to edit it in place, then
choose **Save profile** or **Cancel**. The photo circle opens the image picker;
**Remove photo** is available during editing. Existing icon/color appearances are
preserved, but new editing offers photos only. Account name/photo changes upload
only on Save; cancelling keeps the saved profile.

Use **Profile → Advanced → Preview welcome screen** while stopped to explore the
welcome, Create account and Log in screens. Sample fields are editable, but account
submission, recovery and saved-account restoration are disabled. The preview has no
account API, Keychain provider or persistent preferences. **Use as guest**, Escape,
or **Close preview** returns to Profile without changing real sign-in, local data or
sharing choices. No history deletion is needed. Real account creation still requires
Supabase configuration.

Manual checks passed for survey-enabled and survey-disabled start windows, the
60-minute default, invalid custom targets disabling both start actions, Remove plan,
cancel/reopen reset, inline name focus and cancellation, unsaved photo selection,
picker cancellation and removal, and light/dark layouts. Advanced retains the safe
welcome preview without global work-target controls. Synthetic tests also verify
skipping fatigue preserves the plan and disabled surveys produce no answer.

The isolated unsigned test build lacks Input Monitoring permission: live recording
through completion, Keep going and Stop & save still needs a check on a permitted
build. Synthetic tests cover the shared work clock, boundaries, snapshots and
one-time completion. These additions use no animation and respect Reduce Motion.

### Daily progress and breaks

The main window shows today's progress toward **60 minutes of work**, a weekday
streak, and the number of completed breaks. Work adds up across sessions, including
quiet reading. Breaks, break setup/check-in screens, sleep, screen lock, and time
outside a recording do not count. The session timer still shows total session time.

Monday–Friday require the goal to continue a streak. Saturdays and Sundays show
optional progress and neither increase nor break it. Today's unfinished goal keeps
the previous streak visible until a weekday is missed. Days use the Mac's local
calendar and time zone; work crossing midnight is split between days.

A break earns one count when you return after at least **one minute**, using
**I'm back** or the existing automatic return detection. Returning before or after
the planned timer is fine. Stopping a session during a break earns no count.
Completing the daily goal and returning from a qualifying break show brief inline
encouragement without opening a dialog or sending a notification.

Progress starts with this feature; old recordings aren't backfilled. It lives in
`FocusFix/progress.json` under the app's Application Support directory, separately
from session files, exports, and research uploads. Deleting a recording doesn't
remove earned progress. Progress saves atomically every 15 seconds while recording
and at phase changes, Stop, and normal quit. Unexpected termination can lose up to
15 seconds since the last successful save. Save failures show a notice and retry;
an unreadable file is backed up before starting fresh progress. No recording files
are changed during recovery.

Manual reward check: record work in two sessions and confirm their daily totals add
up; open/cancel a check-in and confirm that time does not count. Return from a
one-minute break both early relative to a longer plan and after its timer expires;
check one count and the recharge message. Stop during another break and check no
count is added. Check the menu-bar totals, relaunch persistence, light/dark layouts,
and VoiceOver's daily-goal description. Use synthetic tests for the one-hour,
weekday, midnight and daylight-saving boundaries rather than altering the Mac clock.

### Survey choices

The account icon opens **Surveys**, with separate switches for:

- Before a session: mental fatigue.
- Before a break: mental fatigue and self-reported productivity.
- The 10-minute check-in: both ratings after starting or actually returning from a break.

All three start on. The choices are remembered locally and apply to the **next session**,
even if I change them while recording. They don't require enrollment or sharing.
Turning off pre-break ratings keeps the duration/activity picker and break timer.
Turning off the 10-minute check-in removes that survey's schedule and notification,
not the normal break reminders. Saved answers aren't deleted.

Each new session records its choices under `survey_options` in `session.json`.
Disabled surveys produce no answer/prompt rows, rather than fake skipped responses.
The CSV files are still included, even if they only contain headers. I need to account
for these choices when comparing sessions; opting out can change which labels I receive.

### Optional research sharing

Open **Settings → Privacy & Research** to review a configured study, confirm
eligibility and request to join. A researcher manually approves up to 50 total
participants. Signing in or receiving approval never turns sharing on. Approved
participants must review the full versioned consent and choose **Share new sessions**.
There is no enrollment key to paste.

Each new completed session begun under the current consent is sent separately to
private, account-linked Supabase storage while signed in and running. The server
requires current approval and consent even for direct Storage calls. Receipts and
stable archive IDs prevent duplicate deliveries. Quota/offline failures keep the
original recording local; the app can export the next queued ZIP explicitly.

Turning sharing off cancels local pending deliveries and records a durable server
withdrawal. It cannot recall data already received. Use **Request deletion of
research data** for hosted copies and researcher review of downloaded datasets.
Deleting local recordings, deleting an account and handling trained models have
different effects; read the current study terms. The app does not claim anonymous
recordings or automatic model unlearning.

Research is disabled in the checked-in configuration until the institution's actual
determination and study terms are supplied. See [research operations](supabase/RESEARCH-OPERATIONS.md)
for deployment, manual approval, the lifetime cap, retention/deletion and verification.

### Session library and exports

- The library shows start/end dates, duration and status, newest first. Use Refresh
  after changing files outside the app. An unfinished session is shown as incomplete
  rather than silently treated as a complete recording.
- Export copies all session CSV files and metadata together into a folder named like
  `FocusFix Session [2026-10-17 09-00-00-2026-10-17 10-30-00]`.
  Times use the Mac's current local time zone; hyphens replace colons in filenames.
  The metadata keeps UTC times. Old sessions without an end date use start + duration.
  Incomplete sessions use `unfinished` rather than an invented end time.
- Exporting again adds `(2)`, `(3)`, etc. if needed. Original recordings and existing
  exports are not overwritten. Exports cannot be placed inside session storage.
- Delete asks for confirmation and moves the selected local session to the Mac's
  Trash, not permanent deletion. Restore it to its original location and refresh the
  library to recover it. Exported copies are unaffected.
- A session currently recording cannot be exported or deleted. Stop it first.

### Break workflow

1. After **25 minutes**, look for **two separate idle stretches of at least 5 seconds
   each within the last 60 seconds**. Only prompt while currently idle for at least
   5 seconds. A continuous 10-second pause counts once, not twice. Without a qualifying
   moment, keep waiting; 25 minutes is a minimum, not a guaranteed prompt time.
2. **Take a break** opens a setup sheet with fatigue and productivity sliders. Rate both,
   or choose **Skip ratings & start break**. Choose **5 minutes** (default), **10**, **15**,
   or a custom duration from **1–120 minutes**. Choose Stretch, Walk, Water / snack,
   Rest my eyes, Breathing or Other (custom text). **Start break** begins the timer.
   Cancelling setup doesn't start a break or count as Skip. A manual Take a break
   button is also available before a reminder is due.
3. **Skip** waits 25 more minutes from the decision; **Snooze** waits 10 more minutes.
   Both then wait for a fresh qualifying idle pattern. Neither resets the factual
   time since the last completed break. An unanswered prompt isn't repeatedly sent.
4. During the planned break, detailed keyboard, click, scroll, app-switch and mouse
   logging pauses. A minimal in-memory input check remains to detect return. The
   main screen uses a softer teal/mint theme and an **I'm back** button.
5. **I'm back** ends a break immediately. Outside FocusFix, a non-repeated key press,
   click, non-momentum scroll or at least **20 screen points of mouse travel within
   one second** also ends it early. Key releases, tiny movements, auto-repeat and app
   activation alone don't end it. Interacting with FocusFix's own windows doesn't
   count as automatic return. This is a heuristic, not proof of productive work.
6. At timer expiry, detailed logging resumes with `activity_phase=awaiting_return`.
   The break remains open until qualifying return activity or **I'm back**; that
   extra time is included in its actual duration. The first return event is logged
   as `work`. Never count the awaiting-return interval as both work and break time.
7. After returning, **Confirm activity** / **Edit activity** lets you report what you
   actually did, even if different from the plan. This is optional and doesn't force
   a popup. It edits the most recent break in the current session, before Stop.
   Unconfirmed actual activity stays blank rather than being assumed from the plan.

The session timer includes breaks. Before the first break, “since last break” uses
session start as the reference. Work reminders restart 25 minutes after actual
return, not after the planned timer deadline. User-state labels are still undecided.

During a planned break, screen/system sleep and inactive login suspend sampling but
preserve break state. The continuous monotonic clock includes this time; wake does
not itself end a break. No mouse rows are invented for suspended time. If the timer
expired while asleep, expiry is recognized and sampling resumes on wake. Sleep
outside a break still stops the session. Quit, Stop and lost permission close an
active break with a `session_*` reason: treat it as **truncated**, not an observed
return. A crash leaves the last recorded break state unfinished; no auto-restart.

### What each file does

| Source | Purpose |
| --- | --- |
| `ContentView.swift` | Minimal timer, status, Start/Stop and export interface. |
| `ActivityTracker.swift` | Permission checks, input monitors, clock, session lifecycle and library actions. |
| `RecordingData.swift` | Mouse aggregation, private in-memory key timing and buffered CSV writing. |
| `SavedSession.swift` | Reads saved-session metadata, validates file targets and names exports safely. |
| `SessionViews.swift` | Saved-session browser and separate Test tracking window. |
| `MyApp.swift` | App windows, shared appearance setting and menu-bar controls. |
| `BreakPolicy.swift` | Clock-driven reminder rules, break state and CSV lifecycle entries. |
| `BreakNotifications.swift` | Native banners, Take/Skip/Snooze actions and stale-action checks. |
| `BreakViews.swift` | Duration/activity setup, reminder controls and activity correction. |
| `Tests/RecordingDataTests.swift` | Synthetic recording, session reload and export-safety checks. |
| `Tests/BreakPolicyTests.swift` | Simulated timing, idle-gap rules, early/late return and break CSV checks. |

### Data dictionary

All CSVs use seconds relative to the same session start. Activity timestamps are callback
receipt times from a continuous monotonic clock including sleep, not hardware event timestamps. Callbacks can
be delayed; six decimal places do not imply microsecond measurement accuracy.

**events.csv — one row for each observed discrete event**

| Column | Meaning |
| --- | --- |
| `elapsed_seconds` | Seconds since Start. |
| `event_type` | `key_down`, `key_up`, `delete_down`, `delete_up`, `modifier_change`, `left_click_down/up`, `right_click_down/up`, `other_click_down/up`, `scroll`, `app_switch`, `session_start`, or `session_stop`. |
| `is_repeat` | 1 for auto-repeated key-down events, 0 for an initial down; blank for other events. |
| `key_hold_seconds` | Down-to-up duration, only on key release when its initial press was observed. |
| `scroll_delta_x` | Amount of sideways scrolling in this event. The sign distinguishes opposite directions. |
| `scroll_delta_y` | Amount of vertical scrolling in this event. The sign distinguishes opposite directions. |
| `scroll_precise` | 1 for fine-grained scrolling deltas, often from a trackpad; 0 for coarse scrolling deltas; blank on other events. Not a measure of the user's accuracy. |
| `activity_phase` | `work`, `check_in` (break setup), or `awaiting_return`. Detailed events are not recorded during the planned break. |
| `seconds_since_last_break` | Elapsed time since the last actual return (or session start before the first break); blank while awaiting return. |

Scrolling is already recorded as individual `scroll` rows, including delivered
momentum events. Scroll amounts are native deltas, not a count of pages read, and
should not be compared across devices without validation. Scrolling alongside
pauses and low typing activity could be a clue to reading, not proof of it.

Delete events replace, rather than duplicate, generic key events. Total key-downs
include `key_down` plus `delete_down`; exclude repeat rows if you want physical
presses. Click counts use down rows, not both down and up. Modifier changes do not
identify which modifier was used. No typed characters, persistent key identifiers,
app identities, window names or clipboard contents are saved. Key codes are used
only in memory for delete detection and matching releases. App switches compare
process identities in memory; switching windows within one app is not counted.

**mouse_movement.csv — one row per observed one-second interval, plus partial boundary intervals**

| Column | Meaning |
| --- | --- |
| `start_seconds`, `end_seconds` | Interval boundaries; intervals are `[start, end)`. |
| `distance_screen_points` | Sum of distances between consecutive observed cursor positions, including dragging. |
| `movement_events` | Number of observed move/drag callbacks in the interval. |
| `seconds_since_last_movement` | Time since the last observed nonzero movement, measured at interval end. Blank if none since tracking started/resumed. |
| `activity_phase` | `work`, `check_in` (break setup), or `awaiting_return`; no rows during planned breaks or suspended sampling. |
| `seconds_since_last_break` | Measured at interval end; blank while awaiting return. |

Cursor positions are discarded after updating totals. Returning to the starting
position does not cancel accumulated distance. Idle intervals have zero movement
counts and distance. Position and idle timing survive interval boundaries. A segment
crossing a boundary is assigned to the interval containing its ending callback.
Distance is screen-coordinate points, not physical mouse travel. Display geometry,
pointer speed, device type and cursor warps affect interpretation. Exact trajectories,
movement efficiency, or exact within-second idle time cannot be recovered later.

There is no separate mouse duration column: subtract `start_seconds` from
`end_seconds` if needed. The final partial interval can be excluded when analysing
full seconds. Break boundaries can also create partial intervals. Position and key
hold state reset when tracking resumes so paused time doesn't become a mouse jump
or a very long key hold. New sessions use **schema version 8**; older files are left
unchanged and remain available in the library.

**breaks.csv — append-only decisions and break lifecycle**

| Column | Meaning |
| --- | --- |
| `elapsed_seconds`, `action` | When and what happened: `prompt`, `skip`, `snooze`, `break_start`, `timer_elapsed`, `break_end`, `activity_updated`, `prompt_cancelled_session_end`, or `suspended_*` / `resumed_*`. Timer expiry uses its planned deadline even if processed later. |
| `prompt_id`, `break_id` | IDs linking decisions and updates. Manual breaks have no prompt ID. |
| `planned_seconds` | Chosen timer duration, not measured break length. |
| `start_seconds`, `end_seconds` | Actual start and detected/explicit end; end stays blank until known. |
| `actual_seconds` | End minus start, including time away after the timer; blank until known. |
| `extra_idle_seconds` | `max(0, end - planned deadline)`; an inferred away-time extension, not confirmed rest. |
| `planned_activity`, `actual_activity` | Original plan and optional later report; custom labels are CSV-escaped and protected against spreadsheet formulas. |
| `end_reason` | `explicit_return`, `outside_app_input`, or a `session_*` interruption. |
| `next_eligible_seconds` | Session-relative reminder eligibility time where applicable, not a promised delivery time. |
| `seconds_since_last_break` | Time since the prior completed break (or session start) when the entry is made. |

Multiple rows share a break ID. Use one `break_end` row per break for duration, plus
the latest `activity_updated` row for the corrected activity. Don't sum durations
across lifecycle snapshots. A start without an end is unfinished, not a zero-length
break. Custom activity text is intentional user-provided data, not captured typing.
`prompt` records the app's reminder decision, not proof that macOS displayed a
banner. Permission settings and Focus can prevent delivery; an unanswered prompt
doesn't establish that the user saw or deliberately ignored it.

**surveys.csv — short check-ins**

- Before a session I show only **Mental fatigue** above the slider.
  The scale is 0 (Not tired) to 10 (Extremely tired).
- Before each break I show that again, plus **Productivity**. The scale is
  0 (Not productive) to 10 (Extremely productive). The extra explanations and slider
  instructions are removed. There is no explicit recall period in these short labels.
  Productivity is the person's own rating, not an objective measure of output or workload.
- Both ratings are also requested once **10 minutes after starting a session** and
  once **10 minutes after each actual return from a break**. It doesn't repeat every
  ten minutes or wait for inactivity/predicted fatigue. An early or late return shifts
  the next check-in accordingly; break timer expiry alone doesn't start the wait.
- A quiet notification offers **Answer** and **Skip**. Clicking Answer or the banner
  opens the two sliders in a small in-app sheet, not inside the system notification.
  This build doesn't add a custom notification-content extension. **Check-in available**
  in the main window and **Answer check-in** in the menu bar work if banners are hidden.
- I don't send these during breaks. If another check-in is open at the due time, I
  wait until it closes. Opening break setup dismisses a pending work check-in rather
  than stacking surveys. Starting a break cancels the old work-period schedule.
  Skip/Snooze of a break reminder does not reset or remove the work check-in.
- Answering, skipping or closing the sheet uses that period's one opportunity.
  Dismissing a banner alone leaves it available in the app without repeated notifications.
  Stop/Quit cancels it. Nothing is carried into another session or work period.
- Move a slider, tap an endpoint, or press **Select 5 / 10** to deliberately select
  the midpoint. The initial thumb position is not an answer. Every check-in starts fresh.
- Skip saves blank ratings with `status=skipped`, not zero. Cancelling break setup
  saves `cancelled`, discards any draft answers and doesn't start a break. Cancelling
  the initial check-in doesn't create a session or recording.
- Rows contain `session_id`, `check_in_id`, `question_version`, `context`, `status`,
  `break_id`, UTC shown/answered times, session-relative shown/answered seconds,
  `fatigue_0_10` and `productivity_0_10`. `context` is `session_start`, `before_break`
  or `during_work`. The break ID joins to `breaks.csv` for pre-break responses; it is
  blank for cancelled setup, session start and during-work responses.
  For skipped/cancelled rows, the answered time is the decision time, not a rating.
- The initial check-in happens before recording, so its shown elapsed time is negative
  and its completion is zero. Break setup and opened work check-ins stay in total
  session time, not break duration. Their activity is marked `check_in` with
  `check_in_start`/`check_in_end` events. Waiting to answer a banner is still work.
  Exclude that interval from work predictors, even if someone uses another app while
  the sheet is open. Use behavior before the check-in, not clicks made answering it.
- Responses are saved immediately and export with the session. They are included in
  optional research uploads only after enrollment and explicit opt-in.
  Old recordings without this file still work. An interrupted session may have an
  unmatched `check_in_start`; don't invent an answer or a completion time for it.
- These are custom ratings, not a validated NASA-TLX score, diagnosis or objective
  productivity measurement. Timed check-ins add observations outside break-taking,
  but don't guarantee low fatigue or an unbiased sample. A late answer isn't a rating
  from exactly minute 10. I still need to finalize the research protocol/IRB plan and
  use consistent assessment schedules across study conditions.
- New check-ins use `focusfix_check_in_v2`. Older v1 sessions keep their original
  `workload_0_10` column and wording. I shouldn't rename or combine those scores with
  productivity ratings; they measure different things.

**survey_prompts.csv — timed check-in history**

- Records `scheduled`, `requested`, `opened`, `answered`, `skipped`, `cancelled`,
  `break_setup`, `break_started` and `session_stopped` actions.
- Each row has session/check-in IDs, action time, due time, notification-request time
  and sheet-opening time (blank until known), in session-relative seconds.
  `reference_break_id` identifies the preceding break, not a new break.
- Join responses by `check_in_id`. This is append-only history, not a separate survey
  per row. An unopened check-in has no response in surveys.csv; a skip from a banner
  is recorded here without inventing a time when the slider sheet was shown.
- `requested` isn't proof macOS delivered the banner or the person read it. Focus and
  notification settings may hide or delay it. `opened` records opening the slider sheet.
- Saved immediately and included in exports. Old sessions are unchanged. A crash can
  leave an unfinished item; missing answers are never zero ratings.

**session.json** stores the random session ID, UTC start/end, schema version, time/unit
definitions, reminder-policy description, check-in wording/scale/version, and final duration/stop reason.
Schema 7 also includes a random Keychain-backed `participant_id` when available and
`sharing_consent_id` only for sessions started while sharing is enabled. It contains
no name, email, enrollment credential or survey scores. Keep any mapping from that
pseudonymous ID to a real participant separately under the study's approved plan.

### Background behavior and limitations

- One passive Core Graphics event tap observes input across apps, including FocusFix,
  using Input Monitoring permission. No input is modified, blocked or synthesized.
  A disabled tap ends the session visibly; queued events from an old session are discarded.
- App Nap is discouraged, but system sleep is allowed. Outside breaks, sleep/screen
  sleep and inactive login stop collection. During breaks, they suspend sampling
  while keeping break timing. Lost Input Monitoring permission, Stop and Quit end the session.
- Standard macOS Secure Input can suppress keyboard events. Absence of events is
  not proof of inactivity. Mouse events may be coalesced by macOS: this is not a
  hardware-level trace. Input Monitoring permission alone does not guarantee completeness.
- Break and check-in notifications have no sound and don't force the app to the
  foreground. The timed banner is automatic; slider sheets and permission/setup/export
  dialogs follow explicit actions.
  Errors appear in the window; a recording error stops
  collection rather than silently continuing. The menu-bar indicator returns to idle.
- Files are buffered and flushed approximately every second (earlier for a large
  event buffer), and synchronized on Stop. A crash can lose buffered data; metadata
  left with `status: recording` should be treated as an unfinished session.
- Both production distribution paths use App Sandbox. Release grants user-selected
  read/write access for exports and outgoing HTTPS for optional accounts. The
  checked-in account service settings are blank and research sharing is off.
  A compiled build is not proof of App Store approval or live input-monitoring coverage.
  Fresh-Mac permission and feature checks remain required; see [RELEASE.md](RELEASE.md).
- Event timing is sensitive even without text. Obtain the required institutional
  approval/consent before recording participants. Sharing is off by default; once
  enrolled and opted in, eligible new sessions upload automatically after Stop.

### Verification

Build from the repository root:

```sh
xcodebuild -project FocusFix/FocusFix.xcodeproj -scheme FocusFix \
  -destination 'platform=macOS' -derivedDataPath /tmp/focusfix-event-build \
  CODE_SIGNING_ALLOWED=NO build
```

Run all synthetic tests from the repository root (macOS with Xcode command-line tools):

```sh
bash scripts/test.sh
```

The script compiles and runs small Swift test programs (the release-configuration
test runs twice, once with Debug enabled and once without it). A failed assertion
stops the run with a nonzero exit code. It uses generated temporary data, cleans up
its own files, and never reads participant sessions or changes system permissions.

- `QuickTourTests`: practice actions, stale/duplicate callbacks, replay, isolated values,
  caption word limits, and spotlight/caption geometry.
- `SessionWorkPlanTests`: target limits, fresh start/cancel reset, survey choices, plan snapshots, shared work
  credit across work/excluded intervals, completion boundaries and acknowledgement.
- `LaunchCoordinatorTests`: offline preview isolation plus first launch, remembered guest mode, automatic restoration,
  failed restoration, registration/profile setup, menu-bar gating and cancelled responses.
- `AccountTests`: fake signup/confirmation/sign-in, private profile sync, recovery,
  Keychain boundaries, cross-service restore rejection and deletion requests.
- `ResearchSharingTests` and `ResearchDeliveryTests`: consent snapshots, safe ZIPs,
  delivery timing, free-limit failures, stable retry paths, export and in-flight opt-out.
- `UserProfileTests`: name/avatar validation, local persistence, failed writes,
  invalid saved data, and bounded square photo import using generated images.
- `DailyProgressTests`: work accounting, weekday streaks, midnight/DST boundaries,
  break credit/deduplication, persistence, failed writes and unreadable-file recovery.
- `RecordingDataTests`: timing, CSV schemas, saving/reloading, export names and guards.
- `BreakPolicyTests`: separate idle gaps, Skip/Snooze, early/late return and break records.
- `SurveyDataTests`: rating validation, skipped/cancelled answers, timestamps,
  immediate saving, question metadata and the check-in activity phase.
- `TimedCheckInTests`: ten-minute boundaries, one opportunity per work period,
  deferral, stale/duplicate actions, early/late return, cancellation and linked CSVs.
- `SurveyPreferencesTests`: all eight switch combinations, persistence, per-session
  snapshots, enabled/disabled scheduling and matching metadata/CSV output.
- `RecordingNoticeTests`: first-use acknowledgement, cancellation/no automatic acceptance
  and asking again when the notice version changes.
- `ReleaseConfigurationTests`: Debug retains the test URL; Release has no upload URL.
- `NotificationAccessTests`: fake permission responses, denial, banners disabled,
  returning from Settings, repeated clicks, errors and retry. No real OS dialog is opened.
- `UploadPolicyTests`: eligibility, whole-session limits, HTTPS configuration, ZIP
  allowlisting, checksums and rejecting symlink inputs. Synthetic temporary files only.
- `SharingQueueTests`: opt-in, no historical backfill, opt-out during preparation,
  restart recovery, offline retries, quota delays and fail-closed settings. Fake
  identity/networking; no real Keychain access or uploads. Also checks that local-only
  builds don't read credentials, alter an existing queue or upload despite a saved opt-in.

The upload service also has eight Node tests using in-memory SQLite and fake R2:

```sh
node --test upload-service/tests/*.test.mjs
```

Use Node 22.13+ for those tests. Both test commands run in GitHub Actions.

The same command is configured in `.github/workflows/tests.yml` for pushes and pull
requests using [GitHub Actions](https://docs.github.com/en/actions/reference/workflows-and-actions/workflow-syntax).
Check the Actions tab for the remote result. This workflow tests logic and file
handling, not the full Xcode app or UI. Build the app locally using the command above.

Manual check after granting Input Monitoring permission: start a short session and complete the
fatigue check-in first. Also try Cancel (no session starts), Skip
(blank score), selecting 0 and 10, and starting from the menu bar with the main window
closed. Take two manual breaks and check that both ratings start unselected each time.
Try cancelling setup, skipping ratings, and exporting the session to inspect surveys.csv.
Check that answered break rows join to the correct break ID and setup activity is
marked `check_in`. These UI checks aren't covered by the synthetic test programs.

In the profile, turn all three surveys off, stop any current session and start a new
one. It should start directly, allow breaks without ratings and have no timed survey.
Change a switch during recording: it should only affect the next session. Relaunch
to check the choices persist, then turn surveys back on and check the original flow.

For the timed check-in, leave a session running for ten minutes with the main window
closed. Check Answer/Skip in the notification, the menu-bar fallback, and that answering
doesn't end the session. Try a manual break before minute ten (old reminder cancelled),
then return and wait ten more minutes. Verify actual banner delivery, Focus/notifications
off, stale banners after Stop, and the request/open/answer times in the exported files.

For activity tracking, type five keys
and Delete in another app, click and scroll, switch apps, move the pointer out and
back, close the collector window, then stop from the menu bar. Inspect the activity CSVs.
Confirm capture continues with the window closed and repeated Start/Stop creates
distinct sessions. Test sleep and permission revocation before a participant study.

For the session library, restart the app and check that saved sessions still appear.
Export the same session twice and confirm both copies exist. Check that active-session
export/delete controls are disabled. Test deletion only on a disposable session and
confirm it is recoverable in Trash. Switch appearance and check each app window.

Build and synthetic checks have passed. Use the manual checks above to verify
real-input recording before a participant study.

For breaks, test a manual 1-minute custom break: check counts pause, end early from
another app, repeat and stay away past expiry, then correct the activity. Inspect
`breaks.csv` and phase tags. Test screen sleep/wake, closing the window, Stop during
a break, notification permission denied, and Take/Skip/Snooze from actual macOS
banners. The synthetic tests simulate 25/10-minute timings without waiting; they
don't prove notification delivery or every sleep/permission behavior on a real Mac.

Native notification integration follows [Apple's notification delegate documentation](https://developer.apple.com/documentation/usernotifications/unusernotificationcenterdelegate).

For notification setup, check the main-window card before recording. Press Enable,
try Allow and Don't Allow on separate test installations/accounts, and verify that
declining doesn't block a session. When denied, use the settings shortcut, enable
notifications and banners, and return to FocusFix: the card should disappear.
Disable banners again and return: it should reappear. Finally test actual break
banners with Focus mode off. An automated permission test cannot prove macOS will
display a banner. Do not reset permissions or delete real sessions just to test this.

## License

Copyright (c) 2026 Kristian Janci.

FocusFix's original software and project material in this repository are
licensed under the GNU General Public License, version 3 only
(`GPL-3.0-only`). You may redistribute and modify this material under those
terms. The complete license is in [LICENSE](LICENSE).

This material is distributed without any warranty, including the implied
warranties of merchantability or fitness for a particular purpose. See the
license for details. Third-party components retain their own licenses and
notices; this grant applies only to material whose rights are held by
Kristian Janci.

## Future ML workflow (not implemented in this collector)

1. External Data is used to train the machine learning model in python.

2. Convert the trained model to Core ML to run in swift.

3. Derive features from event logs and mouse summaries. Test different time windows in Python, then match those definitions in the app for live inference.

4. THe model will give a fatigue, stress or workload prediction.

5. A seperate decision rule will use the prediction and things like time since last break to decide if it should recommend a break.

6. Later the new data can be used for retraining the model.


