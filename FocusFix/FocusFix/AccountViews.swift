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
    private let isPreview: Bool

    init(account: AccountController, create: Bool = false, isPreview: Bool = false, onModeChange: @escaping (Bool) -> Void = { _ in }) {
        self.account = account
        self.isPreview = isPreview
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
                }.disabled(isPreview || code.isEmpty)
            }
            HStack {
                Button(creating ? "Create account" : "Log in") {
                    Task {
                        await account.authenticate(email: email, password: password, create: creating, remember: remember)
                        password = ""
                    }
                }.buttonStyle(.borderedProminent).disabled(isPreview || email.isEmpty || password.isEmpty)
                Button(creating ? "Use existing account" : "Create an account") {
                    creating.toggle()
                    onModeChange(creating)
                }
            }
            HStack {
                Button("Continue with saved account") { Task { await account.restore(remember: remember) } }.disabled(isPreview)
                Button("Forgot password?") { Task { await account.requestRecovery(email: email) } }.disabled(isPreview || email.isEmpty)
            }
            if account.busy { ProgressView().controlSize(.small) }
            if let notice = account.notice { Text(notice).font(.caption).foregroundStyle(.secondary).textSelection(.enabled) }
        }.disabled(account.busy)
    }
}

struct ResearchSharingControls: View {
    @ObservedObject var research = ResearchSharingController.shared
    @ObservedObject var account = AccountController.shared
    @State private var consentPresented = false
    @State private var applying = false
    @State private var deletionConfirmation = false

    private var status: String {
        if research.enabled { return "Sharing on" }
        if research.withdrawalPending { return "Sharing off · withdrawal pending" }
        if account.researchInterest?.status == "withdrawn" { return "Withdrawn" }
        if account.researchEnrolled { return "Approved · sharing off" }
        if account.researchInterest?.status == "not_selected" { return "Not selected" }
        if account.cohortFull { return "Study full" }
        if account.researchInterest != nil { return "Awaiting review" }
        return "Not joined"
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Optional research participation").font(.headline)
            Label(status, systemImage: research.enabled ? "checkmark.shield" : "hand.raised")
            if !account.researchAvailable {
                Text("Research participation is not open in this build. Local recording and all guest features remain available.")
                    .font(.callout).foregroundStyle(.secondary)
            } else if account.session == nil {
                Text("Sign in from Profile to review the study and request to join. Signing in does not share recordings.")
                    .font(.callout).foregroundStyle(.secondary)
            } else {
                Button("Refresh participation status") { Task { _ = await account.refreshResearchAccess() } }
                    .disabled(account.busy || research.busy)
                if let study = account.study, study.complete {
                    Text(study.eligibility_text).font(.callout)
                    if study.allegheny_only { Text("This study is restricted to eligible Allegheny students.").font(.callout) }
                    if let url = study.informationURL { Link("Study information and researcher contact", destination: url) }
                    if account.researchInterest == nil && !account.cohortFull && study.recruitment_enabled {
                        HStack {
                            Button("Request to join") { applying = true; consentPresented = true }
                            Button("No thanks") { UserDefaults.standard.set(true, forKey: "focusfix.research.invitationDeclined") }
                        }
                    }
                    Toggle("Share new sessions", isOn: Binding(get: { research.enabled }, set: { value in
                        if value { applying = false; consentPresented = true } else { research.disable() }
                    })).disabled(!research.enabled && (!account.researchEnrolled || research.busy || research.synchronizingWithdrawal))
                    Text("Only finished sessions started under your current consent are uploaded. Old sessions stay local. You can turn sharing off at any time.")
                        .font(.caption).foregroundStyle(.secondary)
                } else {
                    Text("Study details are unavailable or incomplete. Recruitment and uploads are paused.")
                        .font(.callout).foregroundStyle(.secondary)
                }
                Text("\(research.state.sessions.count) sessions queued").font(.caption)
                HStack {
                    Button("Deliver now") { research.deliver() }.disabled(!research.enabled || research.state.sessions.isEmpty || research.busy)
                    Button("Export next ZIP…") { export() }.disabled(research.state.sessions.isEmpty || research.busy)
                }
                Button("Request deletion of research data…", role: .destructive) { deletionConfirmation = true }
                    .disabled(research.deletionPending)
                if research.busy || research.synchronizingWithdrawal || research.deletionPending { ProgressView().controlSize(.small) }
                Text(research.notice).font(.caption).foregroundStyle(.secondary)
                if let notice = account.notice { Text(notice).font(.caption).foregroundStyle(.secondary) }
            }
        }
        .task { if account.researchAvailable && account.session != nil { _ = await account.refreshResearchAccess() } }
        .sheet(isPresented: $consentPresented) {
            if let study = account.study {
                StudyConsentView(study: study, applying: applying) {
                    consentPresented = false
                    Task {
                        if applying { await account.requestResearchParticipation(adultUS: true, eligible: true, reviewedStudy: study) }
                        else { await research.enable(reviewedStudy: study) }
                    }
                }
            }
        }
        .confirmationDialog("Request deletion of research data?", isPresented: $deletionConfirmation, titleVisibility: .visible) {
            Button("Stop sharing and request deletion", role: .destructive) { Task { await research.requestDeletion() } }
            Button("Cancel", role: .cancel) { }
        } message: {
            Text("Stops sharing and requests deletion of hosted recordings. The researcher must also review downloaded copies and training datasets under the study policy. This does not delete local recordings or automatically undo trained models. Retry if the request fails.")
        }
    }

    private func export() {
        let panel = NSSavePanel()
        panel.title = "Export research ZIP"
        panel.nameFieldStringValue = "FocusFix-research.zip"
        panel.allowedContentTypes = [.zip]
        guard panel.runModal() == .OK, let url = panel.url else { return }
        Task {
            let access = url.startAccessingSecurityScopedResource()
            defer { if access { url.stopAccessingSecurityScopedResource() } }
            do { try await research.export(to: url) } catch { research.report(error) }
        }
    }
}

private struct StudyConsentView: View {
    let study: ResearchStudy
    let applying: Bool
    let accept: () -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var adultUS = false
    @State private var eligible = false
    @State private var understood = false

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text(applying ? "Review the study" : "Consent to share new sessions").font(.title2.weight(.semibold))
            ScrollView {
                VStack(alignment: .leading, spacing: 14) {
                    Text("Purpose").font(.headline)
                    Text(study.purpose)
                    Text("Participation and eligibility").font(.headline)
                    Text(study.duration)
                    Text(study.eligibility_text)
                    if study.allegheny_only { Text("Only eligible Allegheny students may participate.") }
                    Text("Data and confidentiality").font(.headline)
                    Text("Completed recordings include activity timing, delete-key events, mouse summaries, breaks, optional survey answers and session metadata. Private Supabase storage associates uploads with your account. Profile names, photos and account credentials are excluded from recording ZIPs. Participation does not affect local app features.")
                    Text("Risks and benefits").font(.headline)
                    Text(study.risks)
                    Text("Retention and future use").font(.headline)
                    Text(study.retention_policy)
                    Text(study.future_training ? "This study permits future model training as described in its purpose and retention policy." : "This study does not permit future model training.")
                    Text("Withdrawal and deletion").font(.headline)
                    Text(study.withdrawal_policy)
                    Text("Turning sharing off cancels pending uploads. Data already received is handled under the study policy. Deletion of recordings does not automatically remove their influence from trained models.")
                    Text("Questions: \(study.researcher_contact)")
                    if let url = study.informationURL { Link("Full study information", destination: url) }
                    Text("Consent version: \(study.version)").font(.caption)
                }.frame(maxWidth: .infinity, alignment: .leading)
            }
            Toggle("I am 18 or older and reside in the United States", isOn: $adultUS)
            Toggle("I meet the study eligibility requirements", isOn: $eligible)
            Toggle(applying ? "I have reviewed the study and want researcher review" : "I consent to the disclosed uses and automatic uploads of new sessions", isOn: $understood)
            HStack {
                Button("No thanks", role: .cancel) { dismiss() }
                Spacer()
                Button(applying ? "Request to join" : "Agree and enable sharing", action: accept)
                    .buttonStyle(.borderedProminent)
                    .disabled(!study.complete || !adultUS || !eligible || !understood)
            }
        }.padding(26).frame(width: 560, height: 680)
    }
}
