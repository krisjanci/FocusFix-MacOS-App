![FocusFix logo](Assets/FocusFixLong.png)

# FocusFix-MacOS-App
Evaluating Personalized Microbreaks to Reduce Mental Fatigue While Maintaining Productivity

## Current app: activity collector and rule-based breaks

This version collects local behavior data and recommends breaks using a timing/idle
rule. It collects brief fatigue/workload check-ins. It does not predict fatigue with
ML or upload data.
The reminder rule is a prototype to evaluate, not evidence that fatigue is reduced.

### Run it

1. Open `FocusFix/FocusFix.xcodeproj` in Xcode. Select FocusFix → My Mac and Run.
2. Press **Start session**. If prompted in the app, choose **Allow Accessibility
   Access** and enable FocusFix in System Settings → Privacy & Security → Accessibility.
   Then press Start again. If macOS does not recognize a rebuilt app, quit and relaunch it.
3. Rate how mentally tired you feel before starting, or choose **Skip & start**.
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

Sessions are automatically saved under
`~/Library/Application Support/FocusFix/Sessions/<session-id>/`.
Each new session has four CSVs and `session.json`. A new session never replaces an old
one. Old sessions appear in the Sessions window after relaunching the app.
Keep recordings out of the repository and personal cloud storage if your study
or dataset agreement prohibits it. Git ignore rules cover these output filenames,
but renamed data could still be staged accidentally.

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
2. **Take a break** opens a setup sheet with fatigue and workload sliders. Rate both,
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
or a very long key hold. New sessions use **schema version 4**; older files are left
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

- Before a session I ask only **How mentally tired do you feel right now?**
  The scale is 0 (Not tired) to 10 (Extremely tired).
- Before each break I ask that again, plus **How mentally demanding was your work
  in the last 5 minutes?** The scale is 0 (Not demanding) to 10 (Extremely demanding).
  Fatigue means a tired mind; workload means the thinking/focus/effort the task needed.
- Move a slider, tap an endpoint, or press **Select 5 / 10** to deliberately select
  the midpoint. The initial thumb position is not an answer. Every check-in starts fresh.
- Skip saves blank ratings with `status=skipped`, not zero. Cancelling break setup
  saves `cancelled`, discards any draft answers and doesn't start a break. Cancelling
  the initial check-in doesn't create a session or recording.
- Rows contain `session_id`, `check_in_id`, `question_version`, `context`, `status`,
  `break_id`, UTC shown/answered times, session-relative shown/answered seconds,
  `fatigue_0_10` and `workload_0_10`. `context` is `session_start` or `before_break`.
  The break ID joins to `breaks.csv`; it is blank for cancelled setup or session start.
  For skipped/cancelled rows, the answered time is the decision time, not a rating.
- The initial check-in happens before recording, so its shown elapsed time is negative
  and its completion is zero. Break setup stays in total session time, but not break
  duration. Its activity is marked `check_in` with `check_in_start`/`check_in_end` events.
  Exclude that interval from work predictors, even if someone uses another app while
  the sheet is open. Use behavior before the check-in, not clicks made answering it.
- Responses are saved immediately and export with the session. Nothing is uploaded.
  Old recordings without this file still work. An interrupted session may have an
  unmatched `check_in_start`; don't invent an answer or a completion time for it.
- These are custom ratings, not a validated NASA-TLX score, diagnosis or objective
  productivity measurement. This version asks at session start and breaks only—not
  every 30 minutes or after breaks. Break-triggered answers alone aren't a balanced
  sample of all work states. I still need to finalize the research protocol/IRB plan.

**session.json** stores the random session ID, UTC start/end, schema version, time/unit
definitions, reminder-policy description, check-in wording/scale/version, and final duration/stop reason. It contains no participant identity or
survey scores. If needed, keep a consented participant-to-session mapping separately.

### Background behavior and limitations

- Local and global monitors observe FocusFix and other apps without modifying input.
- App Nap is discouraged, but system sleep is allowed. Outside breaks, sleep/screen
  sleep and inactive login stop collection. During breaks, they suspend sampling
  while keeping break timing. Lost Accessibility, Stop and Quit end the session.
- Standard macOS Secure Input can suppress keyboard events. Absence of events is
  not proof of inactivity. Mouse events may be coalesced by macOS: this is not a
  hardware-level trace. Accessibility permission alone does not guarantee completeness.
- Break notifications have no sound and don't force the app to the foreground.
  Permission/setup/export dialogs and check-ins follow explicit actions; there are
  no extra scheduled survey notifications.
  Errors appear in the window; a recording error stops
  collection rather than silently continuing. The menu-bar indicator returns to idle.
- Files are buffered and flushed approximately every second (earlier for a large
  event buffer), and synchronized on Stop. A crash can lose buffered data; metadata
  left with `status: recording` should be treated as an unfinished session.
- The native app is configured without App Sandbox for global monitoring. Run only
  trusted builds; this is a local research prototype, not an App Store release.
- Event timing is sensitive even without text. Obtain the required institutional
  approval/consent before recording participants. Nothing is uploaded automatically.

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

The script compiles and runs four small Swift test programs. A failed assertion
stops the run with a nonzero exit code. It uses generated temporary data, cleans up
its own files, and never reads participant sessions or changes system permissions.

- `RecordingDataTests`: timing, CSV schemas, saving/reloading, export names and guards.
- `BreakPolicyTests`: separate idle gaps, Skip/Snooze, early/late return and break records.
- `SurveyDataTests`: rating validation, skipped/cancelled answers, timestamps,
  immediate saving, question metadata and the check-in activity phase.
- `NotificationAccessTests`: fake permission responses, denial, banners disabled,
  returning from Settings, repeated clicks, errors and retry. No real OS dialog is opened.

The same command is configured in `.github/workflows/tests.yml` for pushes and pull
requests using [GitHub Actions](https://docs.github.com/en/actions/reference/workflows-and-actions/workflow-syntax).
Check the Actions tab for the remote result. This workflow tests logic and file
handling, not the full Xcode app or UI. Build the app locally using the command above.

Manual check after granting Accessibility: start a short session and complete the
fatigue check-in first. Also try Cancel (no session starts), Skip
(blank score), selecting 0 and 10, and starting from the menu bar with the main window
closed. Take two manual breaks and check that both ratings start unselected each time.
Try cancelling setup, skipping ratings, and exporting the session to inspect surveys.csv.
Check that answered break rows join to the correct break ID and setup activity is
marked `check_in`. These UI checks aren't covered by the synthetic test programs.

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

## Future ML workflow (not implemented in this collector)

1. External Data is used to train the machine learning model in python.

2. Convert the trained model to Core ML to run in swift.

3. Derive features from event logs and mouse summaries. Test different time windows in Python, then match those definitions in the app for live inference.

4. THe model will give a fatigue, stress or workload prediction.

5. A seperate decision rule will use the prediction and things like time since last break to decide if it should recommend a break.

6. Later the new data can be used for retraining the model.


