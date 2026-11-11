# FocusFix for macOS

FocusFix is a personal macOS app for recording computer activity, marking work time, taking breaks, and reviewing sessions. It is under development and is separate from the developer’s N-of-1 study. It is not a medical device or a validated measure of productivity or fatigue.

## Getting started

1. Open FocusFix and choose whether to enable recording. Grant macOS Input Monitoring access if you want activity capture.
2. Select **Start work** for a manual session, or **Plan session…** to set a target first.
3. Use **Take a break** and **I’m back** for explicit breaks. **End work** saves a manual session.
4. Open **Sessions** to review, correct work labels, export, or delete local recordings.
5. Open **Quick tour** for a nine-step practice flow. The tour uses demo data and changes no settings or recordings.

Automatic recording is optional in **Settings → Privacy & Data Sharing** and has its own acknowledgement. It may include non-work computer use, begins with an **Unknown** label, and continues while the menu-bar app runs. **Pause recording** or **Quit** stops capture. Closing a window alone may leave it running. The visible status shows whether recording is active. Five minutes of continuous idle time, sleep/lock, or loss of Input Monitoring permission also stop capture.

FocusFix records timing and counts for generic keyboard activity, delete-key use, clicks, scrolling, app switches, and one-second mouse movement summaries. It does not save typed words, individual letter keys, app names, window titles, URLs, screenshots, or exact cursor paths. Detailed timing can still be sensitive. See the [privacy page](https://krisjanci.github.io/FocusFix-Website/privacy.html).

## Accounts and optional sharing

Guest use keeps recordings on the Mac. An optional account supports a saved profile and private groups. Signing in never opts you into recording sharing.

For product development, the developer can manually approve a signed-in account and enable collection in Supabase. The user must then separately review the sharing details and opt in. Only completed recording segments started after consent may upload. A user can turn sharing off and request deletion of hosted recordings in **Settings → Privacy & Data Sharing**. Local files, exports, and backups are separate. The older research uploader remains disabled.

The server configuration starts with collection **off**, no approved accounts, a private bucket, and a default limit of ten archives per approved account. The desktop app contains a publishable Supabase client key, never a service-role key. See [development sharing operations](supabase/DEVELOPMENT-SHARING.md) before enabling the service.

## Build and verification

Open `FocusFix/FocusFix.xcodeproj` in Xcode on macOS 14 or later. Run `bash scripts/test.sh` for local tests and `npm test` plus `npm run test:database` in the `supabase` directory for service tests. Release packaging and content checks are in `scripts/verify-release.sh` and `scripts/package-website.sh`.

A public download is not posted yet. A release still needs the database migration and deletion function deployed, a disposable-project upload/deletion check, a signed and notarized package, a fresh-Mac run, and final App Store privacy answers. A passing source build alone does not complete those checks.

## Source and support

Source is licensed under [GPL-3.0-only](LICENSE). [Open a GitHub issue](https://github.com/krisjanci/FocusFix-MacOS-App/issues) for general support. Issues are public; do not post recordings, credentials, or personal information. Technical recording details are in [RECORDING-CONTRACT.md](RECORDING-CONTRACT.md). Historical project notes were moved to the local `CS 600/FocusFix-App-Archive-2026-11-10` folder.
