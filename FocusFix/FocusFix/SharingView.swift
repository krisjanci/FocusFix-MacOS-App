// MARK: - FF: SHARING
// Shows the participant ID, enrollment and explicit sharing choice, with limits and opt-out caveats.

import SwiftUI
import AppKit

struct SharingView: View {
    @ObservedObject var account = AccountController.shared
    @ObservedObject var sharing = SharingController.shared
    @ObservedObject var surveys = SurveyPreferences.shared
    @Environment(\.dismiss) private var dismiss
    @State private var credential = ""
    @State private var confirmSharing = false
    @State private var enrollmentExpanded = false

    // Show enrollment, consent controls and queue status; require confirmation before sharing starts.
    var body: some View {
        // Keep enrollment controls reachable even when setup help needs extra space.
        ScrollView {
        VStack(alignment: .leading, spacing: 18) {
            HStack {
                Label("Your profile", systemImage: "person.crop.circle").font(.title2.weight(.semibold))
                Spacer()
                Button("Done") { dismiss() }.keyboardShortcut(.cancelAction)
            }
            AccountControls()
            Divider()
            ProfileEditor()
            if account.researchAvailable {
                Divider()
                ResearchSharingControls()
            }
            if sharing.researchAvailable {
            Divider()
            if !sharing.researchAccessLoaded {
                Button("Unlock research setup") {
                    sharing.loadResearchAccess()
                    sharing.resume()
                }
                Text("Only needed for research enrollment and uploads. macOS may ask for Keychain access. This restores your saved sharing choice and resumes pending uploads if you had sharing on.")
                    .font(.caption).foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Text("Participant ID").font(.headline)
            HStack {
                Text(sharing.participantID.isEmpty ? "Unavailable" : sharing.participantID)
                    .font(.system(.caption, design: .monospaced)).textSelection(.enabled)
                Spacer()
                Button { NSPasteboard.general.clearContents(); NSPasteboard.general.setString(sharing.participantID, forType: .string) }
                    label: { Image(systemName: "doc.on.doc") }
                    .help("Copy participant ID").disabled(sharing.participantID.isEmpty)
            }
            Text("This random ID links your sessions on this Mac. It isn't your name or a login.")
                .font(.caption).foregroundStyle(.secondary)
            }
            Divider()
            Text("Surveys").font(.headline)
            Toggle("Before a session · mental fatigue", isOn: $surveys.beforeSession)
            Toggle("Before a break · fatigue & productivity", isOn: $surveys.beforeBreak)
            Toggle("10-minute check-in · fatigue & productivity", isOn: $surveys.duringWork)
            Text("The 10-minute check-in happens after starting or returning from a break. Changes apply to your next session. Saved answers are kept.")
                .font(.caption).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
            Divider()
            DisclosureGroup("Recording & privacy") {
                PrivacyNoticeDetails().padding(.top, 8)
            }
            Link("Support on GitHub", destination: AppLinks.support)
            Text("Support issues are public. Do not post recordings or personal information.")
                .font(.caption).foregroundStyle(.secondary)
            if sharing.researchAvailable {
            Toggle("Share new sessions for research", isOn: Binding(get: { sharing.enabled }, set: { value in
                if value { confirmSharing = true } else { sharing.setEnabled(false) }
            })).disabled(!sharing.enabled && !sharing.canEnable)
            if let blocker = sharing.setupBlocker {
                Label(blocker, systemImage: "info.circle")
                    .font(.callout).foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Text("Shares activity events, mouse summaries, breaks, fatigue/productivity ratings and session timing with the FocusFix researcher. No typed text or cursor paths. Uploads go to private Cloudflare storage.")
                .font(.callout).fixedSize(horizontal: false, vertical: true)
            Text("Up to 180 minutes, 50 MiB and 30 sessions per UTC day. Sessions over 180 minutes or 25 MiB compressed stay local. Recording itself has no daily limit.")
                .font(.caption).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
            Text("Turning sharing off cancels pending uploads. A transfer already received may remain on the server. To request deletion of uploaded data, contact the researcher with your participant ID. Deleting a session here only removes the local copy.")
                .font(.caption).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
            DisclosureGroup("Research enrollment", isExpanded: $enrollmentExpanded) {
                VStack(alignment: .leading, spacing: 10) {
                    Text(sharing.configured ? "Service: \(UploadConfiguration.serviceURL)" : "The upload service hasn't been connected to this build yet.")
                        .font(.caption).textSelection(.enabled)
                    Text("Give your ID to the researcher, then paste the enrollment credential they provide. Only enroll after reviewing the study information and consent process.")
                        .font(.caption).fixedSize(horizontal: false, vertical: true)
                    Text("This is a separate enrollment code, not your Mac or Cloudflare password. The researcher must register it with the upload service first.")
                        .font(.caption).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
                    SecureField("Enrollment credential", text: $credential)
                    Button("Save enrollment") { sharing.saveCredential(credential); credential = "" }
                        .disabled(credential.isEmpty || !sharing.researchAccessLoaded)
                    if sharing.hasCredential { Label("Enrollment saved", systemImage: "key.fill").font(.caption) }
                }.padding(.top, 8)
            }
            Text(sharing.notice).font(.caption).foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            HStack {
                Text("\(sharing.settings.items.filter { $0.state == "uploaded" }.count) uploaded · \(sharing.settings.items.filter { $0.state == "waiting" || $0.state == "uploading" }.count) pending")
                    .font(.caption)
                Spacer()
                Button("Check pending uploads") { sharing.retryPending() }
                    .disabled(!sharing.enabled || sharing.uploading)
            }
            } else if !account.researchAvailable {
                Label("Research uploads unavailable in this build", systemImage: "internaldrive")
                    .font(.callout).foregroundStyle(.secondary)
            }
        }.padding(26)
        }.frame(width: 510, height: 650)
            // Make the missing step visible instead of hiding it behind a closed section.
            .onAppear { enrollmentExpanded = !sharing.hasCredential }
            .onChange(of: sharing.hasCredential) { _, saved in
                if !saved { enrollmentExpanded = true }
            }
            .tint(Color(red: 0.02, green: 0.60, blue: 0.54))
            .confirmationDialog("Share new sessions with the FocusFix researcher?", isPresented: $confirmSharing,
                                titleVisibility: .visible) {
                Button("Turn on sharing") { sharing.setEnabled(true) }
                Button("Cancel", role: .cancel) { }
            } message: {
                Text("Only sessions started after you turn this on are eligible. Your random ID links these recordings. This setting does not replace the study's informed-consent process.")
            }
    }
}
