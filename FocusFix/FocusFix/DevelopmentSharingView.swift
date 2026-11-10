import SwiftUI

struct DevelopmentSharingControls: View {
    @ObservedObject private var sharing = DevelopmentSharingController.shared
    @ObservedObject private var account = AccountController.shared
    @State private var consentPresented = false
    @State private var deletionPresented = false

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Help improve FocusFix").font(.headline)
            Text("Optional recording sharing is separate from recording on your Mac and from group progress.")
                .font(.callout).foregroundStyle(.secondary)
            if !sharing.available {
                Text("Recording sharing is not available in this build. Your recordings stay on this Mac unless you export them.")
                    .font(.callout).foregroundStyle(.secondary)
            } else if account.session == nil {
                Text("Sign in from Profile to check whether your account is approved for optional sharing.")
                    .font(.callout).foregroundStyle(.secondary)
            } else {
                Label(sharing.enabled ? "Sharing on" : "Sharing off",
                      systemImage: sharing.enabled ? "checkmark.shield" : "hand.raised")
                if sharing.enabled {
                    Text("New finished recordings started after you agreed may be sent to the developer. Your local copies remain on this Mac.")
                        .font(.caption).foregroundStyle(.secondary)
                    Button("Turn off sharing") { sharing.disable() }
                } else if sharing.collectionEnabled && sharing.approved {
                    Button("Review and enable sharing…") { consentPresented = true }
                        .disabled(sharing.busy || sharing.deletionPending)
                }
                Button("Refresh sharing status") { Task { await sharing.refresh() } }
                    .disabled(sharing.busy)
                Button("Request deletion of shared recordings…", role: .destructive) {
                    deletionPresented = true
                }.disabled(sharing.deletionPending)
                if sharing.busy || sharing.deletionPending { ProgressView().controlSize(.small) }
                Text(sharing.notice).font(.caption).foregroundStyle(.secondary)
                if let url = account.api?.configuration.privacyPolicyURL {
                    Link("Recording and privacy details", destination: url)
                }
            }
        }
        .task(id: account.session?.user.id) {
            if account.session != nil { await sharing.refresh() }
        }
        .sheet(isPresented: $consentPresented) {
            DevelopmentConsentView {
                consentPresented = false
                Task { await sharing.enable() }
            }
        }
        .confirmationDialog("Delete recordings shared with the developer?",
                            isPresented: $deletionPresented, titleVisibility: .visible) {
            Button("Turn off sharing and request deletion", role: .destructive) {
                Task { await sharing.requestDeletion() }
            }
            Button("Cancel", role: .cancel) { }
        } message: {
            Text("This stops new uploads and deletes hosted copies. The developer must also remove any downloaded copies. Recordings on your Mac are separate and remain under your control.")
        }
    }
}

private struct DevelopmentConsentView: View {
    let accept: () -> Void
    @Environment(\.dismiss) private var dismiss
    @ObservedObject private var sharing = DevelopmentSharingController.shared
    @ObservedObject private var account = AccountController.shared

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Label("Share recordings to improve FocusFix", systemImage: "hand.raised")
                .font(.title2.weight(.semibold))
            Text("Only accounts approved by the developer can use this option. You choose whether to share.")
            Text("After you agree, new finished recordings may be sent to private Supabase storage for FocusFix product development. They include keyboard timing, clicks, scrolling, mouse-movement summaries, work labels, tags, and breaks. They do not include typed text, app names, URLs, screenshots, account passwords, or optional study ratings.")
            Text("The developer can access these detailed recordings. They are kept until you request deletion. Turning sharing off stops future uploads; use Request deletion to remove hosted copies and ask the developer to remove downloaded copies. Your local recordings are kept.")
            Text("An automatic recording already in progress is not shared until a new recording segment starts after consent.")
                .foregroundStyle(.secondary)
            if let url = account.api?.configuration.privacyPolicyURL {
                Link("Read the privacy details", destination: url)
            }
            HStack {
                Button("Not now") { dismiss() }.keyboardShortcut(.cancelAction)
                Spacer()
                Button("I agree and enable sharing") { accept() }
                    .buttonStyle(.borderedProminent)
                    .disabled(!sharing.collectionEnabled || !sharing.approved)
            }
        }
        .font(.callout)
        .fixedSize(horizontal: false, vertical: true)
        .padding(26)
        .frame(width: 530)
    }
}
