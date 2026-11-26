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
    @Published private(set) var study: ResearchStudy?
    @Published private(set) var serverResearchConsent: ResearchServerConsent?
    @Published private(set) var researchInterest: ResearchInterest?
    @Published private(set) var cohortFull = false
    private let readCredential: () throws -> Data?
    private let writeCredential: (Data?) throws -> Void
    @Published private(set) var remembersSignIn: Bool
    private(set) var isNewAccount = false
    private var pendingRegistration = false
    private var rememberSession = false
    private struct ProfileCache: Codable {
        let checkedAt: Date
        let state: AccountProfileState
    }
    private var cachedProfile: ProfileCache?
    private var loadingProfile = false
    private var nextProfileRetry = Date.distantPast
    private let now: () -> Date
    private let defaults: UserDefaults?
    private static let rememberKey = "focusfix.account.keepSignedIn"
    private var authenticationTask: Task<AccountSession?, Error>?
    private var refreshTask: Task<AccountSession, Error>?
    private var generation = UUID()

    // Persist the onboarding request so closing during profile setup cannot lose it.
    private func tourKey(_ id: UUID) -> String {
        "focusfix.account.firstTour.\(api?.configuration.origin.absoluteString ?? "").\(id)"
    }
    var needsFirstAccountTour: Bool {
        guard let id = session?.user.id else { return false }
        return defaults?.bool(forKey: tourKey(id)) == true
    }
    func didPresentFirstAccountTour() {
        guard let id = session?.user.id else { return }
        defaults?.set(false, forKey: tourKey(id))
    }

    var configured: Bool { api != nil }
    var researchEnrolled: Bool {
        enrollment?.enabled == true && study?.complete == true && study?.collection_enabled == true &&
            enrollment?.consent_version == study?.version
    }
    var researchAvailable: Bool { api?.configuration.researchSharingEnabled == true }

    init(configuration: AccountConfiguration?, transport: @escaping AccountAPI.Transport = AccountAPI.send,
         readCredential: @escaping () throws -> Data? = AccountKeychain.read,
         writeCredential: @escaping (Data?) throws -> Void = AccountKeychain.write,
         defaults: UserDefaults? = .standard, now: @escaping () -> Date = Date.init) {
        api = configuration.map { AccountAPI(configuration: $0, transport: transport) }
        self.now = now
        self.defaults = defaults
        remembersSignIn = defaults?.bool(forKey: Self.rememberKey) ?? false
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
            let task = Task<AccountSession?, Error> {
                if stored.session.expiresAt.timeIntervalSinceNow > 60 { return stored.session }
                return try await api.refresh(stored.session.refresh_token)
            }
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
        defaults?.set(value, forKey: Self.rememberKey)
    }

    private func accept(_ value: AccountSession, token: UUID, newAccount: Bool) async {
        guard token == generation else { return }
        isNewAccount = newAccount
        if newAccount { defaults?.set(true, forKey: tourKey(value.user.id)) }
        profile = nil
        profileLoaded = false
        needsConfirmation = false
        pendingRegistration = false
        notice = nil
        // Persist the choice before publishing the session to the launch coordinator.
        do { try persist(value); setRemembered(rememberSession) }
        catch { setRemembered(false); notice = "Signed in for this launch; Keychain could not save the sign-in." }
        session = value
        await loadProfile(force: false)
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

    private var profileCacheKey: String? {
        guard let session, let api else { return nil }
        return "focusfix.account.profileCache.\(api.configuration.origin.absoluteString)|\(session.user.id)"
    }
    func refreshProfileIfDue() async {
        guard session != nil, now() >= nextProfileRetry else { return }
        await loadProfile(force: false)
    }
    func loadProfile(force: Bool = true) async {
        guard !loadingProfile, let api, session != nil else { return }
        if cachedProfile == nil, let key = profileCacheKey, let data = defaults?.data(forKey: key),
           let saved = try? JSONDecoder().decode(ProfileCache.self, from: data),
           saved.checkedAt <= now(), (try? saved.state.profile?.validated()) != nil || saved.state.profile == nil {
            cachedProfile = saved
        }
        if let cache = cachedProfile {
            profile = cache.state.profile; profileLoaded = true
            if !force && now().timeIntervalSince(cache.checkedAt) < 4 * 60 * 60 { return }
        }
        let token = generation
        loadingProfile = true
        defer { if token == generation { loadingProfile = false } }
        do {
            let value = try await api.profileState(session: validSession(), version: cachedProfile?.state.version)
            guard token == generation else { return }
            if !value.unchanged { profile = value.profile }
            profileLoaded = true
            cachedProfile = ProfileCache(checkedAt: now(), state: AccountProfileState(version: value.version, unchanged: false, profile: profile))
            persistProfileCache()
            nextProfileRetry = .distantPast
        } catch {
            if token == generation {
                nextProfileRetry = now().addingTimeInterval(max(300, (error as? AccountFailure)?.retryAfter ?? 0))
                notice = "Signed in, but your profile could not load. Retry before editing. \(error.localizedDescription)"
            }
        }
    }
    private func persistProfileCache() {
        guard let key = profileCacheKey, let cache = cachedProfile, let data = try? JSONEncoder().encode(cache) else { return }
        defaults?.set(data, forKey: key)
    }

    func saveProfile(_ draft: UserProfile) async -> Bool {
        guard !busy, let api, profileLoaded else { return false }
        let token = generation
        busy = true
        defer { if token == generation { busy = false } }
        do {
            let valid = try draft.validated()
            try await api.saveProfile(valid, session: validSession())
            guard token == generation else { return false }
            profile = valid
            cachedProfile = ProfileCache(checkedAt: now(), state: AccountProfileState(version: nil, unchanged: false, profile: valid))
            persistProfileCache()
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
            let session = try await validSession()
            async let result = api.researchEnrollment(session: session)
            async let study = api.researchStudy(session: session)
            async let consent = api.researchConsent(session: session)
            async let interest = api.researchInterest(session: session)
            async let full = api.researchCohortFull(session: session)
            let values = try await (result, study, consent, interest, full)
            guard token == generation else { return false }
            self.study = values.1
            serverResearchConsent = values.2
            researchInterest = values.3
            cohortFull = values.4
            enrollment = values.0
            return researchEnrolled
        } catch {
            if token == generation {
                enrollment = nil; study = nil; serverResearchConsent = nil; researchInterest = nil
                notice = "Research access could not be checked. Uploads are paused."
            }
            return false
        }
    }

    func requestResearchParticipation(adultUS: Bool = false, eligible: Bool = false, reviewedStudy: ResearchStudy? = nil) async {
        guard !busy, researchAvailable, let api, session != nil,
              let study, study.complete, study.recruitment_enabled, adultUS, eligible else { return }
        guard reviewedStudy == nil || reviewedStudy == study else {
            notice = "Study details changed. Review the current study before applying."
            return
        }
        let token = generation
        busy = true
        defer { busy = false }
        do {
            try await api.requestResearch(version: study.version, adultUS: adultUS, eligible: eligible, session: validSession())
            guard token == generation else { return }
            _ = await refreshResearchAccess()
            notice = "Your request is awaiting researcher review. No recordings are shared."
        } catch { if token == generation { notice = error.localizedDescription } }
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
            let deleting = try await validSession()
            try await api.deleteAccount(session: deleting)
            NotificationCenter.default.post(name: Notification.Name("FocusFixAccountDeleted"), object: nil,
                userInfo: ["userID": deleting.user.id, "origin": api.configuration.origin])
            rememberSession = false
            setRemembered(false)
            clearSession()
            try writeCredential(nil)
            notice = "Account deleted. Local recordings and your local profile are kept."
        } catch { notice = error.localizedDescription }
    }

    private func clearSession() {
        if let key = profileCacheKey { defaults?.removeObject(forKey: key) }
        cachedProfile = nil; loadingProfile = false; nextProfileRetry = .distantPast
        generation = UUID()
        refreshTask?.cancel()
        refreshTask = nil
        session = nil
        profile = nil
        profileLoaded = false
        enrollment = nil
        study = nil
        serverResearchConsent = nil
        researchInterest = nil
        cohortFull = false
        needsConfirmation = false
        pendingRegistration = false
        isNewAccount = false
        recovering = false
    }
}
