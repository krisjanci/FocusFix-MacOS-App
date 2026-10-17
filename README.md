![FocusFix logo](Assets/FocusFixLong.png)

# FocusFix-MacOS-App
Evaluating Personalized Microbreaks to Reduce Mental Fatigue While Maintaining Productivity

## Current app: local activity collector

This version collects behavior only. It does not predict fatigue, show surveys,
recommend breaks or send data anywhere. Survey collection is still undecided.

### Run it

1. Open `FocusFix/FocusFix.xcodeproj` in Xcode. Select FocusFix → My Mac and Run.
2. Press **Start session**. If prompted in the app, choose **Allow Accessibility
   Access** and enable FocusFix in System Settings → Privacy & Security → Accessibility.
   Then press Start again. If macOS does not recognize a rebuilt app, quit and relaunch it.
3. Work normally. Close the window if you like: recording continues, with controls
   in the menu bar. Nothing starts automatically on launch.
4. Choose **Stop & save**. Sessions are saved automatically; you don't need to export
   after every recording. Open **Sessions** to browse previous recordings, select one,
   then choose **Export…**, **Show in Finder**, or **Delete…**.
5. **Test tracking** opens a separate window with live individual-event and
   mouse-interval counts. It doesn't start a separate recording; testing during a
   session adds events to that session. Close it when you're done checking.
6. Use the appearance menu in the main window to choose **System**, **Light**, or
   **Dark**. The choice is remembered and applies to all FocusFix windows.

Sessions are automatically saved under
`~/Library/Application Support/FocusFix/Sessions/<session-id>/`.
Each session has two CSVs and `session.json`. A new session never replaces an old
one. Old sessions appear in the Sessions window after relaunching the app.
Keep recordings out of the repository and personal cloud storage if your study
or dataset agreement prohibits it. Git ignore rules cover these output filenames,
but renamed data could still be staged accidentally.

### Session library and exports

- The library shows start/end dates, duration and status, newest first. Use Refresh
  after changing files outside the app. An unfinished session is shown as incomplete
  rather than silently treated as a complete recording.
- Export copies the two CSV files and metadata together into a folder named like
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

### What each file does

| Source | Purpose |
| --- | --- |
| `ContentView.swift` | Minimal timer, status, Start/Stop and export interface. |
| `ActivityTracker.swift` | Permission checks, input monitors, clock, session lifecycle and library actions. |
| `RecordingData.swift` | Mouse aggregation, private in-memory key timing and buffered CSV writing. |
| `SavedSession.swift` | Reads saved-session metadata, validates file targets and names exports safely. |
| `SessionViews.swift` | Saved-session browser and separate Test tracking window. |
| `MyApp.swift` | App windows, shared appearance setting and menu-bar controls. |
| `Tests/RecordingDataTests.swift` | Synthetic recording, session reload and export-safety checks. |

### Data dictionary

Both CSVs use seconds relative to the same session start. Timestamps are callback
receipt times from a monotonic clock, not hardware event timestamps. Callbacks can
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

**mouse_movement.csv — one row per one-second interval, plus a final partial interval**

| Column | Meaning |
| --- | --- |
| `start_seconds`, `end_seconds` | Interval boundaries; intervals are `[start, end)`. |
| `distance_screen_points` | Sum of distances between consecutive observed cursor positions, including dragging. |
| `movement_events` | Number of observed move/drag callbacks in the interval. |
| `seconds_since_last_movement` | Time since the last observed nonzero movement, measured at interval end. Blank if none has occurred since Start. |

Cursor positions are discarded after updating totals. Returning to the starting
position does not cancel accumulated distance. Idle intervals have zero movement
counts and distance. Position and idle timing survive interval boundaries. A segment
crossing a boundary is assigned to the interval containing its ending callback.
Distance is screen-coordinate points, not physical mouse travel. Display geometry,
pointer speed, device type and cursor warps affect interpretation. Exact trajectories,
movement efficiency, or exact within-second idle time cannot be recovered later.

There is no separate mouse duration column: subtract `start_seconds` from
`end_seconds` if needed. The final partial interval can be excluded when analysing
full seconds. New sessions use schema version 2; older files are left unchanged.

**session.json** stores the random session ID, UTC start/end, schema version, time/unit
definitions, and final duration/stop reason. It contains no participant identity or
survey scores. If needed, keep a consented participant-to-session mapping separately.

### Background behavior and limitations

- Local and global monitors observe FocusFix and other apps without modifying input.
- App Nap is discouraged during recording, but system sleep is allowed. Collection
  stops and saves on sleep/screen sleep, inactive login session, lost Accessibility
  permission, Stop or normal Quit. It never restarts automatically.
- Standard macOS Secure Input can suppress keyboard events. Absence of events is
  not proof of inactivity. Mouse events may be coalesced by macOS: this is not a
  hardware-level trace. Accessibility permission alone does not guarantee completeness.
- No notifications or surveys interrupt work. Permission and export dialogs appear
  only after explicit actions. Errors appear in the window; a recording error stops
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

Run the synthetic tests:

```sh
xcrun swiftc -module-cache-path /tmp/focusfix-swift-module-cache \
  FocusFix/FocusFix/RecordingData.swift Tests/RecordingDataTests.swift \
  FocusFix/FocusFix/SavedSession.swift \
  -o /tmp/focusfix-recording-tests
/tmp/focusfix-recording-tests
```

Manual check after granting Accessibility: start a short session, type five keys
and Delete in another app, click and scroll, switch apps, move the pointer out and
back, close the collector window, then stop from the menu bar. Inspect the two CSVs.
Confirm capture continues with the window closed and repeated Start/Stop creates
distinct sessions. Test sleep and permission revocation before a participant study.

For the session library, restart the app and check that saved sessions still appear.
Export the same session twice and confirm both copies exist. Check that active-session
export/delete controls are disabled. Test deletion only on a disposable session and
confirm it is recoverable in Trash. Switch appearance and check each app window.

Build and synthetic checks have passed. Use the manual checks above to verify
real-input recording before a participant study.

## Future ML workflow (not implemented in this collector)

1. External Data is used to train the machine learning model in python.

2. Convert the trained model to Core ML to run in swift.

3. Derive features from event logs and mouse summaries. Test different time windows in Python, then match those definitions in the app for live inference.

4. THe model will give a fatigue, stress or workload prediction.

5. A seperate decision rule will use the prediction and things like time since last break to decide if it should recommend a break.

6. Later the new data can be used for retraining the model.


