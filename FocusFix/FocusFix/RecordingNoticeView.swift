// MARK: - FF: PRIVACY
// Explain system-wide collection before the first recording, without adding clutter to the timer.

import SwiftUI

struct PrivacyNoticeDetails: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("While a session is recording, FocusFix observes keyboard timing, delete-key events, clicks, scrolling, app-switch events and one-second mouse movement summaries across apps. It also saves break timing and any survey answers you choose to give.")
            Text("It does not save typed text, individual letter keys, app names, window titles, screenshots or cursor paths. Detailed activity timing can still be sensitive. Stop recording before doing anything you don't want included.")
            Text("Sessions stay in FocusFix's private storage on this Mac until you delete them. Use Sessions → Show in Finder to locate them. They are not separately encrypted by FocusFix. Exports and Mac backups can contain copies. Deleting a session moves the local folder to Trash; empty Trash when you want to remove that copy.")
            Text("Input Monitoring permission lets the app observe keyboard and mouse activity across apps without changing or blocking your input. You can stop with Stop & save or Quit, and revoke access in System Settings. macOS may withhold keyboard events during secure input, such as password entry. Such gaps are not proof of inactivity. During a planned break detailed logging pauses; it resumes when the break timer ends or you return early.")
            Text(UploadConfiguration.researchUploadsAllowed
                ? "This development build supports optional research sharing after separate enrollment and opt-in. This notice is not study consent. Turning sharing off does not delete data already received; contact the researcher privately with your participant ID."
                : "This build cannot enroll in research or upload recordings. Exporting a session is a separate action you control.")
            Text("Custom break-activity labels are saved exactly as entered. Avoid including personal or sensitive information in them.")
            Text("FocusFix is an experimental activity tool, not a medical device or a validated fatigue or productivity detector.")
        }
        .font(.callout).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
    }
}

struct RecordingNoticeView: View {
    @ObservedObject var tracker: ActivityTracker
    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            Label("Before recording", systemImage: "hand.raised").font(.title2.weight(.semibold))
            ScrollView { PrivacyNoticeDetails() }
            Text("After closing this notice, press Start session when you're ready.")
                .font(.caption).foregroundStyle(.secondary)
            HStack {
                Button("Not now") { tracker.recordingNoticePresented = false }.keyboardShortcut(.cancelAction)
                Spacer()
                Button("I understand") { tracker.acceptRecordingNotice() }
                    .buttonStyle(.borderedProminent)
            }
        }.padding(26).frame(width: 510, height: 520)
    }
}
