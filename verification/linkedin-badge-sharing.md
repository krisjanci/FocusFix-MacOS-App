# LinkedIn badge sharing — 2026-11-18

## Implemented

- Both earned-badge details and celebrations pass their selected badge to the shared LinkedIn button. Locked details have no share action.
- Clicking renders the existing badge artwork into a 1200 × 1200 PNG under the user's cache directory and opens the default browser with the one-line caption in LinkedIn's composer URL.
- The joining caption uses “habits”; work badges use their actual streak threshold.
- The sharing panel offers Copy caption, Show badge image, Open LinkedIn, and Done. Image preparation and browser-opening failures have retry paths. The panel background matches its text appearance.
- Image attachment remains manual. The app never publishes a post or connects to the LinkedIn API.

## Verified

- Debug app build passed with code signing disabled. Final log: `/tmp/focusfix-linkedin-build.log`.
- Complete synthetic test suite passed, including BadgeSharingTests. Log: `/tmp/focusfix-linkedin-tests-visual.log`.
- Sharing tests check joining/streak captions, URL parameter round trips including punctuation, all eight PNG dimensions and filenames, repeated exports, and export failure when the destination is a file.
- Joining and 100-day PNGs were visually inspected at full size; artwork and text fit without clipping.
- Isolated native preview exercised sharing from a celebration and from Joined FocusFix details, Copy caption feedback, and Done returning to the celebration. The final light sharing panel was inspected after the contrast correction.
- Live default-browser handoff opened Chrome using its existing LinkedIn login. LinkedIn navigated to `/sharing/compose`, and its editable post field contained the complete 5-day caption. The Post button was not pressed. That test tab was closed.
- Each changed file was committed separately; the later contrast correction was committed as its own iteration.

## Remaining manual check

Computer use was stopped twice during the Show badge image/Finder check. Its handler calls `NSWorkspace.shared.activateFileViewerSelecting` with the prepared PNG URL, but Finder selection and attaching that image to a draft have not been visually verified. Do not treat that end-to-end image handoff as passed. Browser-prefill support may change; Copy caption is the fallback.

No release, packaging, deployment, or publishing command was run.

## Share-card visual revision

The exported card now shows the badge name once below the artwork, without the repeated description. The header reuses `FocusFixLaunchLogo(ready: true)` at 48 points beside the rounded FocusFix wordmark. A pale blue/mint/lilac background adds sparse stars, an orbital arc, and an outlined planet around the edges. Dark header/title lettering and a light central area preserve contrast across badge colors.

The revised exporter passed BadgeSharingTests for all eight badges, and the Debug app build passed with code signing disabled (`/tmp/focusfix-badge-restyle-build.log`). The joining and 100-day exports were visually inspected at 1200 × 1200: the logo, one-line badge name, and full artwork are visible without clipping or decorative overlap. Preview images: `/tmp/focusfix-restyled-badges/FocusFix-joined.png` and `/tmp/focusfix-restyled-badges/FocusFix-work-100.png`. No release was made. The earlier Finder handoff limitation is separate from this visual revision.
