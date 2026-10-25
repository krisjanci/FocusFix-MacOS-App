import Foundation
import Combine
import Security

nonisolated struct StoredAccount: Codable {
    let origin: String
    let session: AccountSession
}

nonisolated enum AccountKeychain {
    private static let service = "io.github.krisjanci.FocusFix.accounts"
    static func read() throws -> Data? {
        let query: [String: Any] = [kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service, kSecAttrAccount as String: "session",
            kSecReturnData as String: true, kSecMatchLimit as String: kSecMatchLimitOne]
        var result: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        if status == errSecItemNotFound { return nil }
        guard status == errSecSuccess, let data = result as? Data else {
            throw AccountFailure(message: "The saved sign-in could not be read from Keychain.")
        }
        return data
    }
    static func write(_ data: Data?) throws {
        let query: [String: Any] = [kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service, kSecAttrAccount as String: "session"]
        guard let data else {
            let status = SecItemDelete(query as CFDictionary)
            guard status == errSecSuccess || status == errSecItemNotFound else {
                throw AccountFailure(message: "The saved sign-in could not be removed from Keychain.")
            }
            return
        }
        let status = SecItemUpdate(query as CFDictionary, [kSecValueData as String: data] as CFDictionary)
        if status == errSecItemNotFound {
            var item = query
            item[kSecValueData as String] = data
            item[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
            guard SecItemAdd(item as CFDictionary, nil) == errSecSuccess else {
                throw AccountFailure(message: "The sign-in could not be saved in Keychain.")
            }
        } else if status != errSecSuccess { throw AccountFailure(message: "The saved sign-in could not be updated.") }
    }
}

@MainActor
final class AccountController: ObservableObject {
    static let shared = AccountController(configuration: .bundled)
    let api: AccountAPI?
    @Published private(set) var session: AccountSession?
    @Published private(set) var profile: UserProfile?
    @Published private(set) var profileLoaded = false
    @Published private(set) var busy = false
    @Published private(set) var notice: String?
    @Published private(set) var needsConfirmation = false
    @Published private(set) var recovering = false
    @Published private(set) var enrollment: ResearchEnrollment?
    private let readCredential: () throws -> Data?
    private let writeCredential: (Data?) throws -> Void
    @Published private(set) var remembersSignIn: Bool
    private(set) var isNewAccount = false
    private var pendingRegistration = false
    private var rememberSession = false
    private let defaults: UserDefaults
    private static let rememberKey = "focusfix.account.keepSignedIn"
    private var authenticationTask: Task<AccountSession?, Error>?
    private var refreshTask: Task<AccountSession, Error>?
    private var generation = UUID()

    var configured: Bool { api != nil }
    var researchEnrolled: Bool { enrollment?.enabled == true && !(enrollment?.consent_version.isEmpty ?? true) }
    var researchAvailable: Bool { api?.configuration.researchSharingEnabled == true }

    init(configuration: AccountConfiguration?, transport: @escaping AccountAPI.Transport = AccountAPI.send,
         readCredential: @escaping () throws -> Data? = AccountKeychain.read,
         writeCredential: @escaping (Data?) throws -> Void = AccountKeychain.write,
         defaults: UserDefaults = .standard) {
        api = configuration.map { AccountAPI(configuration: $0, transport: transport) }
        self.defaults = defaults
        remembersSignIn = defaults.bool(forKey: Self.rememberKey)
        self.readCredential = readCredential
        self.writeCredential = writeCredential
        // Construction performs no Keychain or network work; the coordinator restores opted-in sign-ins later.
    }

    func authenticate(email: String, password: String, create: Bool, remember: Bool = true) async {
        guard !busy, let api, session == nil else { return }
        let email = email.trimmingCharacters(in: .whitespacesAndNewlines)
        guard email.contains("@"), password.count >= (create ? 8 : 1) else {
            notice = "Enter an email address and a password\(create ? " of at least 8 characters" : "")."
            return
        }
        let token = beginAuthentication()
        defer { finishAuthentication(token) }
        pendingRegistration = create
        rememberSession = remember
        do {
            let task = Task<AccountSession?, Error> {
                if create { return try await api.signUp(email: email, password: password) }
                return try await api.signIn(email: email, password: password)
            }
            authenticationTask = task
            let result = try await task.value
            guard token == generation, !Task.isCancelled else { return }
            needsConfirmation = create && result == nil
            if let result { await accept(result, token: token, newAccount: create) }
            else { notice = "Check your email for a confirmation code. If you already have an account, sign in instead." }
        } catch { if token == generation { notice = error.localizedDescription } }
    }

    func restore(remember: Bool = true) async {
        guard !busy, let api, session == nil else { return }
        let token = beginAuthentication()
        defer { finishAuthentication(token) }
        rememberSession = remember
        do {
            guard let data = try readCredential() else { notice = "No saved sign-in. Enter your email and password."; return }
            let stored = try JSONDecoder().decode(StoredAccount.self, from: data)
            guard stored.origin == api.configuration.origin.absoluteString else {
                throw AccountFailure(message: "The saved sign-in belongs to another account service. Sign in again.")
            }
            let task = Task<AccountSession?, Error> { try await api.refresh(stored.session.refresh_token) }
            authenticationTask = task
            let refreshed = try await task.value
            guard token == generation, !Task.isCancelled, let refreshed else { return }
            await accept(refreshed, token: token, newAccount: false)
        } catch { if token == generation { notice = error.localizedDescription } }
    }

    private func beginAuthentication() -> UUID {
        generation = UUID()
        busy = true
        notice = nil
        return generation
    }

    private func finishAuthentication(_ token: UUID) {
        guard token == generation else { return }
        busy = false
        authenticationTask = nil
    }

    // Guest selection never opens Keychain. Cancelled responses cannot publish a session.
    func continueAsGuest() {
        authenticationTask?.cancel()
        authenticationTask = nil
        clearSession()
        rememberSession = false
        setRemembered(false)
        busy = false
        notice = nil
    }

    private func setRemembered(_ value: Bool) {
        remembersSignIn = value
        defaults.set(value, forKey: Self.rememberKey)
    }

    private func accept(_ value: AccountSession, token: UUID, newAccount: Bool) async {
        guard token == generation else { return }
        isNewAccount = newAccount
        profile = nil
        profileLoaded = false
        needsConfirmation = false
        pendingRegistration = false
        notice = nil
        // Persist the choice before publishing the session to the launch coordinator.
        do { try persist(value); setRemembered(rememberSession) }
        catch { setRemembered(false); notice = "Signed in for this launch; Keychain could not save the sign-in." }
        session = value
        await loadProfile()
        guard token == generation else { return }
        if researchAvailable { _ = await refreshResearchAccess() }
    }

    func validSession() async throws -> AccountSession {
        guard let current = session, let api else { throw AccountFailure(message: "Sign in to continue.") }
        if current.expiresAt.timeIntervalSinceNow > 60 { return current }
        let token = generation
        let task: Task<AccountSession, Error>
        if let existing = refreshTask { task = existing }
        else {
            task = Task { try await api.refresh(current.refresh_token) }
            refreshTask = task
        }
        defer { if token == generation { refreshTask = nil } }
        let refreshed = try await task.value
        guard token == generation, refreshed.user.id == current.user.id else {
            throw AccountFailure(message: "The account changed. Try again after signing in.")
        }
        session = refreshed
        try persist(refreshed)
        return refreshed
    }

    private func persist(_ value: AccountSession) throws {
        guard rememberSession, let api else { return }
        try writeCredential(JSONEncoder().encode(StoredAccount(origin: api.configuration.origin.absoluteString, session: value)))
    }

    func loadProfile() async {
        guard let api, session != nil else { return }
        let token = generation
        do {
            let value = try await api.profile(session: validSession())
            guard token == generation else { return }
            profile = value
            profileLoaded = true
        } catch { if token == generation { notice = "Signed in, but your profile could not load. Retry before editing. \(error.localizedDescription)" } }
    }

    func saveProfile(_ draft: UserProfile) async -> Bool {
        guard !busy, let api, profileLoaded else { return false }
        busy = true
        defer { busy = false }
        do {
            let valid = try draft.validated()
            try await api.saveProfile(valid, session: validSession())
            profile = valid
            notice = "Profile saved to your account."
            return true
        } catch { notice = error.localizedDescription; return false }
    }

    func requestRecovery(email: String) async {
        guard !busy, let api, session == nil, email.contains("@") else { return }
        let token = beginAuthentication()
        defer { finishAuthentication(token) }
        do {
            try await api.resetPassword(email: email.trimmingCharacters(in: .whitespacesAndNewlines))
            guard token == generation, !Task.isCancelled else { return }
            recovering = true
            notice = "If the account exists, a recovery code will arrive by email."
        } catch { if token == generation { notice = error.localizedDescription } }
    }

    func verify(email: String, code: String, newPassword: String, remember: Bool? = nil) async {
        guard !busy, let api, session == nil else { return }
        guard !recovering || newPassword.count >= 8 else { notice = "Choose a new password of at least 8 characters."; return }
        let token = beginAuthentication()
        defer { finishAuthentication(token) }
        if let remember { rememberSession = remember }
        let recovery = recovering
        let newAccount = pendingRegistration && !recovery
        do {
            let task = Task<AccountSession?, Error> {
                let value = try await api.verify(email: email.trimmingCharacters(in: .whitespacesAndNewlines),
                    code: code.trimmingCharacters(in: .whitespacesAndNewlines), recovery: recovery)
                try Task.checkCancellation()
                if recovery { try await api.changePassword(newPassword, session: value) }
                return value
            }
            authenticationTask = task
            let value = try await task.value
            guard token == generation, !Task.isCancelled, let value else { return }
            recovering = false
            await accept(value, token: token, newAccount: newAccount)
        } catch { if token == generation { notice = error.localizedDescription } }
    }

    @discardableResult
    func refreshResearchAccess() async -> Bool {
        guard let api, researchAvailable, session != nil else { enrollment = nil; return false }
        let token = generation
        do {
            let result = try await api.researchEnrollment(session: validSession())
            guard token == generation else { return false }
            enrollment = result
            return researchEnrolled
        } catch {
            if token == generation { enrollment = nil; notice = "Research approval could not be checked. Uploads are paused." }
            return false
        }
    }

    func requestResearchParticipation() async {
        guard !busy, let api, session != nil else { return }
        busy = true
        defer { busy = false }
        do {
            try await api.requestResearch(session: validSession())
            notice = "Your interest was recorded. The researcher will select participants and provide the approved consent process. No recordings are shared yet."
        } catch { notice = error.localizedDescription }
    }

    func signOut() async {
        guard !busy else { return }
        busy = true
        defer { busy = false }
        let old = session
        rememberSession = false
        setRemembered(false)
        clearSession()
        var errorText: String?
        do { try writeCredential(nil) } catch { errorText = error.localizedDescription }
        if let api, let old {
            do { try await api.signOut(session: old) }
            catch { errorText = "Signed out on this Mac. The server could not revoke this session; it will expire normally." }
        }
        notice = errorText ?? "Signed out. Your local recordings are kept."
    }

    func deleteAccount() async {
        guard !busy, let api else { return }
        busy = true
        defer { busy = false }
        do {
            try await api.deleteAccount(session: validSession())
            rememberSession = false
            setRemembered(false)
            clearSession()
            try writeCredential(nil)
            notice = "Account deleted. Local recordings and your local profile are kept."
        } catch { notice = error.localizedDescription }
    }

    private func clearSession() {
        generation = UUID()
        refreshTask?.cancel()
        refreshTask = nil
        session = nil
        profile = nil
        profileLoaded = false
        enrollment = nil
        needsConfirmation = false
        pendingRegistration = false
        isNewAccount = false
        recovering = false
    }
}
