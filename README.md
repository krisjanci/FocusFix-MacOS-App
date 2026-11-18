# FocusFix for macOS

FocusFix is a personal macOS app for recording computer activity, marking work time, taking breaks, and reviewing sessions. It is under development and is separate from the developer’s N-of-1 study. It is not a medical device or a validated measure of productivity or fatigue.

## Getting started

1. Open FocusFix and choose whether to enable recording. Grant macOS Input Monitoring access if you want activity capture.
2. Select **Start work** for a manual session, or choose **Add tags** or **Work target** in the timer card and confirm **Start work**.
3. Use **Take a break** and **I’m back** for explicit breaks. **End work** saves a manual session.
4. Open **Sessions** to review, export, or delete local recordings. Days with multiple recordings appear as expandable folders. Batch exports use the same day folders; days with one recording stay as single entries.
5. Open **Quick tour** for a nine-step practice flow. The tour uses demo data and changes no settings or recordings.

Automatic recording is optional in **Settings → Privacy & Data Sharing** and has its own acknowledgement. It may include non-work computer use, begins with an **Unknown** label, and continues while the menu-bar app runs. **Pause recording** or **Quit** stops capture. Closing a window alone may leave it running. The visible status shows whether recording is active. Five minutes of continuous idle time, sleep/lock, or loss of Input Monitoring permission also stop capture.

FocusFix records timing and counts for generic keyboard activity, delete-key use, clicks, scrolling, app switches, and one-second mouse movement summaries. It does not save typed words, individual letter keys, app names, window titles, URLs, screenshots, or exact cursor paths. Detailed timing can still be sensitive. See the [privacy page](https://krisjanci.github.io/FocusFix-Website/privacy.html).

## Personal survey check-ins

Click your profile picture and turn on **Survey check-ins**, or use the same control in Settings. The **Prompts per day** slider selects 1–5 (default 2). Surveys start off; the frequency controls appear only when check-ins are enabled. Each optional check-in asks for mental fatigue and self-reported productivity using two sliders.

FocusFix saves random opportunities across the remainder of each local calendar day. It requests up to your chosen number while recording and outside breaks, with at least 30 minutes between requests, including across midnight and app restarts. Missed times coalesce into one opportunity rather than a burst. Days with limited recording time may have fewer prompts. Requested prompts count even if skipped or unanswered. Changing the count preserves requests already made that day; turning surveys off immediately clears pending and open check-ins. Settings and today's schedule survive relaunches.

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

Group work streaks sync observed declared-work intervals with retry-safe replacements, including historical corrections. Positive, unfrozen streaks have a gentle burning animation that respects Reduce Motion. Account buttons use FocusFix teal. Group rows show the same shared thumbnail to you and other members. Newly added account photos default to sharing with group members. Change **Show my profile photo to members of my groups** in **Settings → Privacy & Data Sharing**; changes to existing photos save immediately. You can also turn sharing off before adding a photo, and that account-specific choice is remembered on this Mac. Existing photos retain their saved visibility when replaced. The profile displays current visibility and links to Settings. Imports prepare the private photo and bounded 64-pixel thumbnail together, so failed imports cannot leave mismatched images. Group photos update on the next group refresh.

Groups include **Work streak**, **Healthy habits**, and **Chat** tabs in both the side panel and the Groups window. Chat displays **Coming soon** only: it adds no requests, subscriptions, database tables, or message storage.

Groups and Analytics share one right-side panel. The bottom-right **Analytics** button shows blurred illustrative charts and **Coming soon**; switching panels keeps the same window width. Appearance is an icon-only button beside the recording status; each click cycles System → Light → Dark → System, with no menu.

Activity labels now follow **Start work** and **End work**, including timer-card setup and menu-bar equivalents. Automatic recording outside declared work is **Unknown**. Manual context menus and history corrections are no longer offered. Breaks remain separate from activity context. Local exports map historical `non_work` context fields to `unknown` in intervals, revision history, reminder requests, and study check-in prompts. Export notes explain this conversion; saved originals and hosted uploads are unchanged.

The timer card offers matching **Add tags** and **Work target** controls. When you are not working, confirming either editor with **Start work** begins work, including when automatic capture is currently Unknown. Cancel leaves recording unchanged. During work, **Done** saves the edit without restarting; target changes retain credit already earned in that work period. Library tag edits remain edits to saved recordings.
