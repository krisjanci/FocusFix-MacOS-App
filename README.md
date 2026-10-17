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
4. Choose **Stop & save**. **Export CSVs** copies that session into a new folder at
   your chosen destination. The folder button opens the original local files.

Sessions are automatically saved under
`~/Library/Application Support/FocusFix/Sessions/<session-id>/`.
Each session has two CSVs and `session.json`. A new session never replaces an old
one. Old sessions remain in the parent Sessions folder after relaunching the app.
Keep recordings out of the repository and personal cloud storage if your study
or dataset agreement prohibits it. Git ignore rules cover these output filenames,
but renamed data could still be staged accidentally.

### What each file does

| Source | Purpose |
| --- | --- |
| `ContentView.swift` | Minimal timer, status, Start/Stop and export interface. |
| `ActivityTracker.swift` | Permission checks, input monitors, clock, menu-bar state and session lifecycle. |
| `RecordingData.swift` | Mouse aggregation, private in-memory key timing and buffered CSV writing. |
| `MyApp.swift` | Single window and menu-bar controls; closing the window does not quit. |
| `Tests/RecordingDataTests.swift` | Synthetic checks without capturing anyone's real input. |

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

**session.json** stores the random session ID, UTC start, schema version, time/unit
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
  -o /tmp/focusfix-recording-tests
/tmp/focusfix-recording-tests
```

Manual check after granting Accessibility: start a short session, type five keys
and Delete in another app, click and scroll, switch apps, move the pointer out and
back, close the collector window, then stop from the menu bar. Inspect the two CSVs.
Confirm capture continues with the window closed and repeated Start/Stop creates
distinct sessions. Test sleep and permission revocation before a participant study.

Build and synthetic checks have passed. Use the manual checks above to verify
real-input recording before a participant study.

## Future ML workflow (not implemented in this collector)

1. External Data is used to train the machine learning model in python.

2. Convert the trained model to Core ML to run in swift.

3. Derive features from event logs and mouse summaries. Test different time windows in Python, then match those definitions in the app for live inference.

4. THe model will give a fatigue, stress or workload prediction.

5. A seperate decision rule will use the prediction and things like time since last break to decide if it should recommend a break.

6. Later the new data can be used for retraining the model.


