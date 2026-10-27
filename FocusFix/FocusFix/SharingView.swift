// Profile contains identity and practice tools. Recording and participation live in Settings.
import SwiftUI

struct SharingView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.openWindow) private var openWindow
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                HStack {
                    Label("Your profile", systemImage: "person.crop.circle").font(.title2.weight(.semibold))
                    Spacer()
                    Button("Done") { dismiss() }.keyboardShortcut(.cancelAction)
                }
                ProfileEditor()
                Divider()
                AccountControls()
                Divider()
                HStack(spacing: 16) {
                    Button {
                        dismiss()
                        Task { @MainActor in
                            await Task.yield()
                            openWindow(id: "tracking")
                            NSApp.activate(ignoringOtherApps: true)
                        }
                    } label: { Label("Test tracking", systemImage: "keyboard") }
                    QuickTourButton(beforeOpen: { dismiss() })
                }
                SettingsLink { Label("Privacy & Research settings", systemImage: "hand.raised") }
                Text("Your profile is private. Signing in never enables recording or research sharing.")
                    .font(.caption).foregroundStyle(.secondary)
            }.padding(26)
        }.frame(width: 510, height: 540)
    }
}

struct PrivacyResearchSettings: View {
    @ObservedObject private var tracker = ActivityTracker.shared
    @ObservedObject private var surveys = SurveyPreferences.shared
    @State private var recordingEnabled = RecordingNotice().enabled
    @State private var recordingConsentPresented = false

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                Label("Privacy & Research", systemImage: "hand.raised").font(.title2.weight(.semibold))
                Toggle("Allow activity recording", isOn: Binding(get: { recordingEnabled }, set: { value in
                    if value { recordingConsentPresented = true }
                    else { tracker.disableRecording(); recordingEnabled = false }
                }))
                Text("Recording starts only when you press Start session. Turning this off stops the current session and keeps your saved recordings.")
                    .font(.caption).foregroundStyle(.secondary)
                Button("Manage Input Monitoring") { tracker.requestPermission() }.disabled(!recordingEnabled)
                DisclosureGroup("What is recorded and where it is stored") { PrivacyNoticeDetails().padding(.top, 8) }
                Divider()
                ResearchSharingControls()
                Divider()
                Text("Optional surveys").font(.headline)
                Toggle("Before a session · mental fatigue", isOn: $surveys.beforeSession)
                Toggle("Before a break · fatigue & productivity", isOn: $surveys.beforeBreak)
                Toggle("10-minute check-in · fatigue & productivity", isOn: $surveys.duringWork)
                Text("Survey changes apply to your next session.").font(.caption).foregroundStyle(.secondary)
                Divider()
                QuickTourButton()
                AdvancedSettingsView(tracker: tracker)
                if let privacy = AppLinks.privacy { Link("Privacy policy", destination: privacy) }
                Link("Support on GitHub", destination: AppLinks.support)
                Text("Support issues are public. Never post recordings, credentials, or personal information.")
                    .font(.caption).foregroundStyle(.secondary)
            }.padding(26)
        }.frame(width: 560, height: 650)
        .sheet(isPresented: $recordingConsentPresented, onDismiss: { recordingEnabled = RecordingNotice().enabled }) {
            RecordingNoticeView(tracker: tracker).interactiveDismissDisabled()
        }
        .onAppear { recordingEnabled = RecordingNotice().enabled }
    }
}
