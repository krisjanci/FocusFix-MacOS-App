# FocusFix for macOS

FocusFix is a personal macOS app for recording computer activity, marking work time, taking breaks, and reviewing sessions. It is under development and is separate from the developer’s N-of-1 study. It is not a medical device or a validated measure of productivity or fatigue.

## Getting started

1. Open FocusFix and choose whether to enable recording. Grant macOS Input Monitoring access if you want activity capture.
2. Select **Start work** for a manual session, or choose **Task** to open projects and use **Work on this**, or choose **Work target** and confirm **Start work**.
3. Use **Take a break** and **I’m back** for explicit breaks. **End work** saves a manual session.
4. Open **Sessions** to review, export, or delete local recordings. Days with multiple recordings appear as expandable folders. Batch exports use the same day folders; days with one recording stay as single entries.
5. Open **Quick tour** for a nine-step practice flow. The tour uses demo data and changes no settings or recordings.

Automatic recording is optional in **Settings → Privacy & Data Sharing** and has its own acknowledgement. It may include non-work computer use, begins with an **Unknown** label, and continues while the menu-bar app runs. **Pause recording** or **Quit** stops capture. Closing a window alone may leave it running. The visible status shows whether recording is active. Five minutes of continuous idle time, sleep/lock, or loss of Input Monitoring permission also stop capture.

FocusFix records timing and counts for generic keyboard activity, delete-key use, clicks, scrolling, app switches, and one-second mouse movement summaries. It does not save typed words, individual letter keys, app names, window titles, URLs, screenshots, or exact cursor paths. Detailed timing can still be sensitive. See the [privacy page](https://krisjanci.github.io/FocusFix-Website/privacy.html).

## Start of day survey

In **Profile → Privacy & Data Sharing settings**, enable **Start of day survey** (off by default). On the first opening of the main FocusFix screen each local calendar day, a full-window check-in asks when you went to bed and woke up, how rested you feel, mental fatigue, and current stress. It works independently of recording, accounts, and the timed check-ins, including when FocusFix launches at login. Onboarding and open dialogs finish first. Each slider requires an explicit response; the sleep dates can be adjusted for overnight or daytime sleep. Time in bed is not a measurement of time asleep.

**Skip today**, answering, or an unanswered prompt followed by a relaunch will not prompt again that day. A running app checks again when its main window is reopened or activated on another day. Merely crossing midnight does not interrupt your work. Turning the option off closes the prompt and keeps saved responses.

Responses stay in a separate local `start-of-day.json` file and are not added to recording uploads. **Export daily surveys** saves a CSV with local day, time zone, UTC timestamps, time in bed, and ratings, so it can be compared with activity exports and personal fatigue/productivity check-ins. Unanswered ratings remain blank. **Delete daily surveys** removes the local responses while retaining today's prompt marker; exported copies remain separate. This supplies context for future correlation analysis; it does not generate fatigue or productivity predictions.

## Personal survey check-ins

Open **Settings → Privacy & Data Sharing** and turn on **Survey check-ins**. The **Prompts per day** slider selects 1–5 (default 2). Surveys start off; the frequency controls appear only when check-ins are enabled. Each optional check-in asks for mental fatigue and self-reported productivity using two sliders.

FocusFix saves random opportunities across the remainder of each local calendar day. It requests up to your chosen number while recording and outside breaks, with at least 30 minutes between new check-ins, including across midnight and app restarts. Missed times coalesce into one opportunity rather than a burst. Days with limited recording time may have fewer prompts. Requested prompts count even if skipped or unanswered. Changing the count preserves requests already made that day; turning surveys off immediately clears pending and open check-ins. Settings and today's schedule survive relaunches.

Personal check-ins do not enroll you in a study or enable sharing. Existing recording and sharing choices still apply. The separate reviewed-study configuration remains gated.

## Accounts and optional sharing

Guest use keeps recordings on the Mac. An optional account supports a saved profile and private groups. Signing in never opts you into recording sharing.

For product development, the developer can manually approve a signed-in account and enable collection in Supabase. The user must then separately review the sharing details and opt in. Only completed recording segments started after consent may upload. A user can turn sharing off and request deletion of hosted recordings in **Settings → Privacy & Data Sharing**. Local files, exports, and backups are separate. The older research uploader remains disabled.

The server configuration starts with collection **off**, no approved accounts, a private bucket, and a default limit of ten archives per approved account. The desktop app contains a publishable Supabase client key, never a service-role key. See [development sharing operations](supabase/DEVELOPMENT-SHARING.md) before enabling the service.

## Build and verification

Open `FocusFix/FocusFix.xcodeproj` in Xcode on macOS 14 or later. Run `bash scripts/test.sh` for local tests and `npm test` plus `npm run test:database` in the `supabase` directory for service tests. Release packaging and content checks are in `scripts/verify-release.sh` and `scripts/package-website.sh`.

A public download is not posted yet. A release still needs the database migration and deletion function deployed, a disposable-project upload/deletion check, a signed and notarized package, a fresh-Mac run, and final App Store privacy answers. A passing source build alone does not complete those checks.

## Source and support

Source is licensed under [GPL-3.0-only](LICENSE). [Open a GitHub issue](https://github.com/krisjanci/FocusFix-MacOS-App/issues) for general support. Issues are public; do not post recordings, credentials, or personal information. Technical recording details are in [RECORDING-CONTRACT.md](RECORDING-CONTRACT.md).

Completed Saturday and Sunday goals add a day to work and healthy-habit streaks. Missed weekends stay optional and use no freezes. Group scores require the `202611150002_count_qualifying_weekends.sql` migration; saved qualifying weekend history counts on recalculation.

Group work streaks sync observed declared-work intervals with retry-safe replacements, including historical corrections. Positive, unfrozen streaks have a gentle burning animation that respects Reduce Motion. Account buttons use FocusFix teal. Group rows show the same shared thumbnail to you and other members. Newly added account photos default to sharing with group members. Change **Show my profile photo to members of my groups** in **Settings → Privacy & Data Sharing**; changes to existing photos save immediately. You can also turn sharing off before adding a photo, and that account-specific choice is remembered on this Mac. Existing photos retain their saved visibility when replaced. Photo visibility and survey controls live in Privacy & Data Sharing; the profile window links to Settings. Imports prepare the private photo and bounded 64-pixel thumbnail together, so failed imports cannot leave mismatched images. Group photos update on the next group refresh.

Groups include **Work streak**, **Healthy habits**, and **Chat** tabs in both the side panel and the Groups window. Chat displays **Coming soon** only: it adds no requests, subscriptions, database tables, or message storage.

Groups and Analytics share one right-side panel. The bottom-right **Analytics** button shows blurred illustrative charts and **Coming soon**; switching panels keeps the same window width. Appearance is an icon-only button beside the recording status; each click cycles System → Light → Dark → System, with no menu.

The full-width **Badges** button at the bottom of Analytics opens a collection with one large badge per row. Earn permanent work-streak badges at 5, 10, 20, 30, 50, 75, and 100 completed days. Each day requires 60 minutes of declared work; completed weekends count, and the existing weekend and freeze rules protect continuity. **Joined FocusFix** unlocks after account sign-up/sign-in and stays locked for guests. Work achievements follow the local progress card and do not sync across devices. Existing qualifying history is backfilled without a burst of old celebrations or alerts.

New awards show a full-window badge celebration over a blurred background and send **You've gained a badge!** through macOS when notifications are allowed. Click to dismiss: the badge shrinks along an arc toward Analytics; Reduce Motion uses a fade. Red circles on Analytics and its Badges entry stay until the collection is opened. Earned badge details and celebrations include **Share to LinkedIn** with its logo; clicking prepares a 1200 × 1200 badge PNG and opens the default browser to LinkedIn’s post composer with a suggested one-line caption. Attach the image manually before publishing. The sharing panel offers **Show badge image**, **Copy caption**, and **Open LinkedIn**; use Copy caption if LinkedIn ignores the browser prefill. No post is published automatically. Click elsewhere or press Escape to dismiss details. Future badges remain visible in grey with their unlock requirements.

Activity labels now follow **Start work** and **End work**, including timer-card setup and menu-bar equivalents. Automatic recording outside declared work is **Unknown**. Manual context menus and history corrections are no longer offered. Breaks remain separate from activity context. Local exports map historical `non_work` context fields to `unknown` in intervals, revision history, reminder requests, and study check-in prompts. Export notes explain this conversion; saved originals and hosted uploads are unchanged.

The timer card offers **Task** (a document icon) and **Work target**. Task replaces the main content with projects and checklists inside the same window, without changing its dimensions or the Groups/Analytics panel. The profile, app logo/title, recording-status statement, streak, appearance control, and large work buttons are hidden to give the checklist more space. One bordered back arrow, matching Badges, sits beside Projects or the current project name; it returns one level at a time. Projects are optional: the normal timer’s Start work records without a project when none is selected; there is no separate no-project action in the projects list. Create a project with a custom color, add and reorder tasks, then use a task’s small rounded teal play button (**Work on this**) or the project’s **Untasked Work** action. These actions start work when idle or switch assignments during work without resetting the timer or work target, then return straight to the main timer after success. Permission prompts or save failures keep the task page available for attention. Browsing and editing never start recording.

Every catalog includes **Random Tasks**, a default project whose name is fixed and which cannot be deleted; its color and tasks remain editable. Existing catalogs gain this folder without changing other IDs or tasks. An existing Random Tasks folder is adopted in place. Projects move to the top when you explicitly start or switch work on them, not when opened, renamed, or checked off. Drag projects to arrange them manually; accessible **Move up / Move down** actions are also available. A teal insertion line shows whether the row will be placed above or below its target before release. Manual order survives relaunch and stays in effect until another work action promotes a project.

Projects and project headings use a 23-point rounded semibold title, just below the main FocusFix title’s 25 points. **Edit** switches the page into editing mode: red **×** controls replace task play buttons and appear beside removable projects. Click a name to rename it inline, then press Enter, choose the checkmark, or select **Done** to save. Invalid names keep the editor open with an error. Escape cancels the name draft or leaves editing mode. Project color controls are available in Edit; Random Tasks keeps its protected name and lock. Project deletion asks for confirmation; task deletion removes the task from its checklist while preserving recorded history. No three-dot menus remain on project/task rows.

While working on a task, the timer also offers a green outlined **Finished task** chip beside Work target. It checks off the active task and immediately continues as Untasked Work in the same project, preserving time and target credit. It is hidden during breaks and when no task is active.

Checking a task shows a green tick immediately. Three seconds later it shrinks to 85%, becomes muted, and slides to the completed rows at the bottom. Unchecking restores its canonical checklist position; drag ordering or accessible Move up/Move down actions update that order. Teal placement guides appear for both unfinished and completed task rows. Tasks move within their current section, so dragging never checks or unchecks a task. Completed tasks can be manually reordered; the next newly completed task still appends to the end. Completing the active task immediately continues as Untasked Work in the same project. Unchecking does not resume it automatically. Reduce Motion uses a brief fade. Completed tasks remain visible and editable.

Project colors use the timer’s existing background tint. Each assignment change preserves earlier time; breaks and Unknown activity are excluded. New work periods begin without a project, while breaks retain the assignment. Renaming or deleting projects/tasks preserves historical name/color snapshots. Deleting the active task switches to Untasked Work; deleting its project switches to no project.

Projects and tasks save privately on this Mac in `projects.json`. Recording assignment history lives separately in `work_assignments.json`, appears in Sessions, and is included in local exports. Neither file is included in shared recording uploads. Older tags remain readable in session history and exports; new work uses projects instead. There are no due dates, priorities, subtasks, notes, or account sync in this version.

When idle, confirming **Work target** with **Start work** begins work, including when automatic capture is Unknown. During work, **Done** changes the target without restarting or losing credit already earned. Cancel leaves recording unchanged.

Unanswered personal check-ins repeat their notification every 10 minutes while recording and outside breaks, until answered or explicitly skipped. Repeats belong to the same check-in and do not use another daily slot; the 30-minute minimum applies to new check-ins. The same question and **Answer**/**Skip** actions appear directly below **Start work**/**End work**. Opening the survey pauses repeats; closing it without answering leaves it pending and starts another ten-minute wait. Breaks defer the pending reminder. Stopping recording or turning check-ins off cancels it.

The timer’s **+Conditions** button opens a quick Conditions window. Choose one reusable label per category: Location, Music, and Work setting come with starter choices. Every category is optional. Add your own categories and labels, or use **Edit** to rename/remove catalog entries. Catalog edits save independently; Cancel discards only the session selection. **Start work** confirms conditions and begins work when idle; **Done** updates conditions during work without resetting time or the work target. New work periods start without conditions. Selected conditions appear beneath the timer controls and can also be edited in recording history.

Conditions describe the whole recording segment, rather than timed changes. Saved names are snapshots: renaming or removing reusable choices does not rewrite history. Conditions remain in local recording metadata and exports, and are included in eligible shared recording archives under the existing sharing choices.

For an isolated native conditions preview, run `bash scripts/preview-conditions.sh` and open the printed app path. It uses temporary synthetic data and does not link the real recorder or account services. See [session conditions verification](verification/session-conditions.md) for checks and runtime boundaries.
