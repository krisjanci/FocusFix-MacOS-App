import SwiftUI
import AppKit

struct SharingView: View {
    @ObservedObject var sharing = SharingController.shared
    @Environment(\.dismiss) private var dismiss
    @State private var credential = ""
    @State private var confirmSharing = false

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            HStack {
                Label("Your research profile", systemImage: "person.crop.circle").font(.title2.weight(.semibold))
                Spacer()
                Button("Done") { dismiss() }.keyboardShortcut(.cancelAction)
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
            Divider()
            Toggle("Share new sessions for research", isOn: Binding(get: { sharing.enabled }, set: { value in
                if value { confirmSharing = true } else { sharing.setEnabled(false) }
            })).disabled(!sharing.enabled && !sharing.canEnable)
            Text("Shares activity events, mouse summaries, breaks, fatigue/productivity ratings and session timing with the FocusFix researcher. No typed text or cursor paths. Uploads go to private Cloudflare storage.")
                .font(.callout).fixedSize(horizontal: false, vertical: true)
            Text("Up to 180 minutes, 50 MiB and 30 sessions per UTC day. Sessions over 180 minutes or 25 MiB compressed stay local. Recording itself has no daily limit.")
                .font(.caption).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
            Text("Turning sharing off cancels pending uploads. A transfer already received may remain on the server. To request deletion of uploaded data, contact the researcher with your participant ID. Deleting a session here only removes the local copy.")
                .font(.caption).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
            DisclosureGroup("Research enrollment") {
                VStack(alignment: .leading, spacing: 10) {
                    Text(sharing.configured ? "Service: \(UploadConfiguration.serviceURL)" : "The upload service hasn't been connected to this build yet.")
                        .font(.caption).textSelection(.enabled)
                    Text("Give your ID to the researcher, then paste the enrollment credential they provide. Only enroll after reviewing the study information and consent process.")
                        .font(.caption).fixedSize(horizontal: false, vertical: true)
                    SecureField("Enrollment credential", text: $credential)
                    Button("Save enrollment") { sharing.saveCredential(credential); credential = "" }
                        .disabled(credential.isEmpty)
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
        }.padding(26).frame(width: 510)
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
