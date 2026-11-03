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
    @ObservedObject private var automatic = AutomaticRecordingPreferences.shared
    @StateObject private var login = LoginLaunch()
    @AppStorage("focusfix.screenUseReminders") private var screenUseReminders = false
    @State private var automaticConsentPresented = false
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
                Text("Manual recording starts with Start work. Automatic recording is a separate choice below. Turning all recording off stops both modes and keeps saved recordings.")
                    .font(.caption).foregroundStyle(.secondary)
                Button("Manage Input Monitoring") { tracker.requestPermission() }.disabled(!recordingEnabled)
                Toggle("Enable automatic recording", isOn: Binding(get: { automatic.enabled }, set: { value in
                    if value { automaticConsentPresented = true } else { automatic.disable() }
                })).disabled(!recordingEnabled)
                Text("Includes unknown and non-work computer use while FocusFix is running. Work labels are optional. Pause recording or Quit to stop capture.")
                    .font(.caption).foregroundStyle(.secondary)
                Toggle("Screen-use break reminders outside declared work", isOn: $screenUseReminders)
                    .onChange(of: screenUseReminders) { _, _ in tracker.reminderPreferenceChanged() }
                Text("Off by default. These are screen-use reminders during Unknown or Not working activity, without inferring work. ‘I’m not working’ labels from now and keeps recording; edit earlier labels in Sessions.")
                    .font(.caption).foregroundStyle(.secondary)
                Toggle("Launch at login", isOn: Binding(get: { login.requested }, set: { login.setEnabled($0) }))
                Text(login.explanation).font(.caption).foregroundStyle(.secondary)
                if let error = login.error { Text(error).font(.caption).foregroundStyle(.red) }
                DisclosureGroup("What is recorded and where it is stored") { PrivacyNoticeDetails().padding(.top, 8) }
                Divider()
                ResearchSharingControls()
                Divider()
                Text("Optional study check-ins").font(.headline)
                Toggle("Optional study check-ins", isOn: Binding(get: { surveys.studyCheckInsEnabled }, set: { surveys.setStudyCheckInsEnabled($0) }))
                Text("Off by default, including after upgrades. These optional fatigue/productivity ratings are separate from research sharing. Prompts also require a complete reviewed study configuration; none is supplied in this build. Turning this off cancels pending prompts. Missing ratings stay missing.")
                    .font(.caption).foregroundStyle(.secondary)
                Toggle("Before a session · mental fatigue", isOn: $surveys.beforeSession).disabled(!surveys.studyCheckInsEnabled)
                Toggle("Before a break · fatigue & productivity", isOn: $surveys.beforeBreak).disabled(!surveys.studyCheckInsEnabled)
                Toggle("Scheduled study check-ins across activity contexts", isOn: $surveys.duringWork).disabled(!surveys.studyCheckInsEnabled)
                Text("Reviewed schedules are frozen for a recording. Enabling/changing options applies to the next recording; turning study check-ins off cancels them immediately.").font(.caption).foregroundStyle(.secondary)
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
        .sheet(isPresented: $automaticConsentPresented) {
            AutomaticRecordingNoticeView(onEnable: { automatic.enable() })
        }
        .onAppear { recordingEnabled = RecordingNotice().enabled; login.refresh() }
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in login.refresh() }
    }
}
