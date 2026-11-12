// MARK: - FF: PRIVACY
// Explain system-wide collection before the first recording, without adding clutter to the timer.

import SwiftUI

struct PrivacyNoticeDetails: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("While recording manually or automatically, FocusFix observes keyboard timing, delete-key events, clicks, scrolling, app-switch events and one-second mouse movement summaries across apps. It also saves break timing and user-declared work/non-work/unknown labels. Automatic recording can include non-work computer use.")
            Text("It does not save typed text, individual letter keys, app names, window titles, URLs, screenshots or exact cursor paths. Detailed activity timing can still be sensitive. Disable recording in Settings before doing anything you don't want included.")
            Text("Sessions stay in FocusFix's private storage on this Mac until you delete them. Use Sessions → Show in Finder to locate them. They are not separately encrypted by FocusFix. Exports and Mac backups can contain copies. Deleting a session moves the local folder to Trash; empty Trash when you want to remove that copy.")
            Text("Input Monitoring permission lets the app observe keyboard and mouse activity across apps without changing or blocking your input. You can stop by disabling recording in Settings or choosing Quit, and revoke access in System Settings. macOS may withhold keyboard events during secure input, such as password entry. Such gaps are not proof of inactivity. During a planned break detailed logging pauses; it resumes when the break timer ends or you return early.")
            Text(AccountConfiguration.bundled?.developmentSharingEnabled == true
                ? "With separate consent, an approved signed-in account can share new finished recordings with the developer through private Supabase storage to improve FocusFix. Signing in and allowing local recording do not enable sharing. Turn sharing off or request deletion in Settings → Privacy & Data Sharing. Uploaded data can be associated with your account; it is not anonymous."
                : "This build does not upload detailed recordings. Exporting a recording is a separate action you control.")
            Text("An optional account profile sends your chosen name and avatar to the configured account service when you save it. A local profile stays on this Mac. Neither kind of profile is required to record sessions.")
            Text("Groups are optional and separate from detailed recording sharing. Enabling group progress sync sends declared-work time intervals and qualifying-break summaries to your account service, with your scoring timezone and streak freeze decisions. Creating or joining a private group shares only your display name, standard avatar and two current weekday streaks with its current members. You can also choose to share a small profile-photo thumbnail with group members. Existing photos remain private until you turn on sharing. Email addresses and recordings are never shown in groups. Leaving removes your group score; deleting your account removes your social summaries and owned groups.")
            Text("Custom break-activity labels are saved exactly as entered. Avoid including personal or sensitive information in them.")
            Text("FocusFix is an experimental activity tool, not a medical device or a validated fatigue or productivity detector.")
        }
        .font(.callout).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
    }
}

struct RecordingNoticeView: View {
    @ObservedObject var tracker: ActivityTracker
    @Environment(\.dismiss) private var dismiss
    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            Label("Your activity, your choice", systemImage: "hand.raised").font(.title2.weight(.semibold))
            ScrollView { PrivacyNoticeDetails() }
            Text("After closing this notice, Start work begins manual capture. Automatic recording needs a separate explicit choice in Privacy & Data Sharing.")
                .font(.caption).foregroundStyle(.secondary)
            HStack {
                Button("Not now") { tracker.declineRecordingNotice(); dismiss() }.keyboardShortcut(.cancelAction)
                Spacer()
                Button("Enable recording") { tracker.acceptRecordingNotice(); dismiss() }
                    .buttonStyle(.borderedProminent)
            }
        }.padding(26).frame(width: 510, height: 520)
    }
}


struct AutomaticRecordingNoticeView: View {
    let onEnable: () -> Void
    @Environment(\.dismiss) private var dismiss
    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            Label("Automatic recording", systemImage: "record.circle").font(.title2.weight(.semibold))
            Text("If you enable this, FocusFix can record computer use while it is running, including non-work activity. Start work is optional; automatic activity begins Unknown.")
            Text("It records keyboard timing, delete events, clicks, scrolling, app-switch counts and one-second mouse summaries. It does not save typed text, letter identities, app names, URLs, window titles, screenshots or exact cursor paths. Secure Input and other capture gaps remain possible.")
            Text("The menu bar shows recording status. Disable recording in Settings or choose Quit to stop. Closing a window keeps the menu-bar app running. Login launch, Input Monitoring and optional developer sharing are separate choices.")
            Text("Input Monitoring must already be available before automatic capture can start. You can set it up with Manage Input Monitoring after this choice; opening Settings does not request it.")
                .font(.callout).foregroundStyle(.secondary)
            HStack {
                Button("Not now") { dismiss() }.keyboardShortcut(.cancelAction)
                Spacer()
                Button("Enable automatic recording") { onEnable(); dismiss() }.buttonStyle(.borderedProminent)
            }
        }.padding(26).frame(width: 530)
    }
}
