import SwiftUI
import AppKit
import UniformTypeIdentifiers

struct AccountControls: View {
    @ObservedObject var account = AccountController.shared
    @State private var confirmDeletion = false

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Account").font(.headline)
            if !account.configured {
                Text("Online accounts are not connected in this build. You can still create a profile on this Mac.")
                    .font(.callout).foregroundStyle(.secondary)
            } else if let session = account.session {
                Text("Signed in as \(session.user.email ?? "your account")").font(.callout)
                if !account.profileLoaded {
                    Button("Retry loading profile") { Task { await account.loadProfile() } }.disabled(account.busy)
                }
                HStack {
                    Button("Sign out") { Task { await account.signOut() } }
                    Button("Delete account…", role: .destructive) { confirmDeletion = true }
                }.disabled(account.busy)
                Text("Account profiles sync privately. Creating an account does not enable research sharing or publish your activity.")
                    .font(.caption).foregroundStyle(.secondary)
            } else {
                AccountSignInForm(account: account)
            }
            if account.session != nil {
                if account.busy { ProgressView().controlSize(.small) }
                if let notice = account.notice { Text(notice).font(.caption).foregroundStyle(.secondary).textSelection(.enabled) }
            }
        }
        .disabled(account.busy)
        .confirmationDialog("Delete your online account?", isPresented: $confirmDeletion, titleVisibility: .visible) {
            Button("Delete account", role: .destructive) { Task { await account.deleteAccount() } }
            Button("Cancel", role: .cancel) { }
        } message: {
            Text("This permanently deletes your online account, profile and research ZIPs still held in this service. Copies already downloaded by the researcher and recordings on this Mac are not deleted.")
        }
    }
}


struct AccountSignInForm: View {
    @ObservedObject var account: AccountController
    @State private var email = ""
    @State private var password = ""
    @State private var code = ""
    @State private var creating: Bool
    @State private var remember = true
    private let onModeChange: (Bool) -> Void

    init(account: AccountController, create: Bool = false, onModeChange: @escaping (Bool) -> Void = { _ in }) {
        self.account = account
        self.onModeChange = onModeChange
        _creating = State(initialValue: create)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            TextField("Email", text: $email).textFieldStyle(.roundedBorder)
                .accessibilityLabel("Email address")
            if !account.recovering {
                SecureField("Password", text: $password).textFieldStyle(.roundedBorder)
            }
            Toggle("Keep me signed in", isOn: $remember)
            Text("Saved sign-in uses macOS Keychain and restores automatically next time. macOS may ask for Keychain access.")
                .font(.caption).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
            if account.needsConfirmation || account.recovering {
                TextField("Code from your email", text: $code).textFieldStyle(.roundedBorder)
                if account.recovering {
                    SecureField("New password (at least 8 characters)", text: $password).textFieldStyle(.roundedBorder)
                }
                Button(account.recovering ? "Verify & reset password" : "Confirm email") {
                    Task {
                        await account.verify(email: email, code: code, newPassword: password, remember: remember)
                        password = ""; code = ""
                    }
                }.disabled(code.isEmpty)
            }
            HStack {
                Button(creating ? "Create account" : "Log in") {
                    Task {
                        await account.authenticate(email: email, password: password, create: creating, remember: remember)
                        password = ""
                    }
                }.buttonStyle(.borderedProminent).disabled(email.isEmpty || password.isEmpty)
                Button(creating ? "Use existing account" : "Create an account") {
                    creating.toggle()
                    onModeChange(creating)
                }
            }
            HStack {
                Button("Continue with saved account") { Task { await account.restore(remember: remember) } }
                Button("Forgot password?") { Task { await account.requestRecovery(email: email) } }.disabled(email.isEmpty)
            }
            if account.busy { ProgressView().controlSize(.small) }
            if let notice = account.notice { Text(notice).font(.caption).foregroundStyle(.secondary).textSelection(.enabled) }
        }.disabled(account.busy)
    }
}

struct ResearchSharingControls: View {
    @ObservedObject var research = ResearchSharingController.shared
    @ObservedObject var account = AccountController.shared
    @State private var confirm = false

    var body: some View {
        if account.researchAvailable {
            VStack(alignment: .leading, spacing: 10) {
                Text("Research participation").font(.headline)
                if let study = account.api?.configuration.studyInformationURL {
                    Link("Read study information", destination: study)
                }
                if account.session != nil && !account.researchEnrolled {
                    Text("Research sharing requires selection by the researcher and completion of the study consent process. Requesting to join sends your account ID, not recordings.")
                        .font(.caption).foregroundStyle(.secondary)
                    HStack {
                        Button("I'm interested in the study") { Task { await account.requestResearchParticipation() } }
                        Button("Check approval") { Task { _ = await account.refreshResearchAccess() } }
                    }.disabled(account.busy)
                }
                Toggle("Share new sessions for research", isOn: Binding(get: { research.enabled }, set: {
                    if $0 { confirm = true } else { research.disable() }
                })).disabled(account.session == nil || !account.researchEnrolled)
                Text("Shares activity timing, mouse summaries, breaks, survey answers and session metadata with the FocusFix researcher in private Supabase storage. Profile names and photos are excluded from ZIPs; the receiving service can associate uploads with your account.")
                    .font(.caption).foregroundStyle(.secondary)
                Text("Only finished sessions started after opt-in are eligible. Each completed session uploads while FocusFix is open and signed in; offline deliveries wait until it runs again. Free storage is limited—failed deliveries stay local. Turning this off cancels pending deliveries; already received copies may remain with the researcher. This choice does not replace study consent.")
                    .font(.caption).foregroundStyle(.secondary)
                Text("\(research.state.sessions.count) sessions queued").font(.caption)
                HStack {
                    Button("Deliver now") { research.deliver() }.disabled(!research.enabled || research.state.sessions.isEmpty)
                    Button("Export next ZIP…") { export() }.disabled(research.state.sessions.isEmpty)
                }.disabled(research.busy)
                if research.busy { ProgressView().controlSize(.small) }
                Text(research.notice).font(.caption).foregroundStyle(.secondary)
            }
            .confirmationDialog("Share new recordings with the FocusFix researcher?", isPresented: $confirm,
                                titleVisibility: .visible) {
                Button("Enable research sharing") { research.enable() }
                Button("Cancel", role: .cancel) { }
            } message: {
                Text("Detailed recording data will be sent automatically after you opt in. Review the study information first. Existing sessions are not backfilled. You can stop sharing at any time.")
            }
        }
    }

    private func export() {
        let panel = NSSavePanel()
        panel.title = "Export research research ZIP"
        panel.nameFieldStringValue = "FocusFix-research-\(Date().formatted(.iso8601.year().month().day().dateSeparator(.dash))).zip"
        panel.allowedContentTypes = [.zip]
        guard panel.runModal() == .OK, let url = panel.url else { return }
        Task {
            let access = url.startAccessingSecurityScopedResource()
            defer { if access { url.stopAccessingSecurityScopedResource() } }
            do { try await research.export(to: url) } catch { research.report(error) }
        }
    }
}
