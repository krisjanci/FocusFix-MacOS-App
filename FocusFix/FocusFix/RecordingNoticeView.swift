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
            Text(AccountConfiguration.bundled?.researchSharingEnabled == true
                ? "This build supports optional per-session research sharing with the FocusFix researcher through private Supabase storage after manual researcher approval and separate, versioned consent. Signing in does not enable sharing. Received data can be associated with your account; ZIPs exclude profile names and photos. Review the full study consent in Settings → Privacy & Research before enabling sharing. Turning sharing off cancels pending deliveries but cannot recall copies already received."
                : "This build cannot enroll in research or upload recordings. Exporting a session is a separate action you control.")
            Text("An optional account profile sends your chosen name and avatar to the configured account service when you save it. A local profile stays on this Mac. Neither kind of profile is required to record sessions.")
            Text("Groups are optional and separate from research. Enabling group progress sync sends work-duration and qualifying-break summaries to your account service, with your scoring timezone and streak freeze decisions. Creating or joining a private group shares only your display name, standard avatar and two daily-point totals with its current members. Email addresses, profile photos, recordings and surveys are never shown in groups. Leaving removes your group score; deleting your account removes your social summaries and owned groups.")
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
            Text("After closing this notice, press Start session when you're ready.")
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
