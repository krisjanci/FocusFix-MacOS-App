import Foundation

@main @MainActor
struct AccountTests {
    static func main() async throws {
        let config = AccountConfiguration(url: "https://example.supabase.co", publicKey: "sb_publishable_test")!
        precondition(AccountConfiguration(url: "http://example.com", publicKey: "sb_publishable_test") == nil)
        precondition(AccountConfiguration(url: "https://example.com/path", publicKey: "sb_publishable_test") == nil)
        precondition(AccountConfiguration(url: "https://user:password@example.com", publicKey: "sb_publishable_test") == nil)
        precondition(AccountConfiguration(url: "https://example.com", publicKey: "sb_secret_bad") == nil)
        let encodedRole = Data("{\"role\":\"service_role\"}".utf8).base64EncodedString().replacingOccurrences(of: "=", with: "")
        precondition(AccountConfiguration(url: "https://example.com", publicKey: "header.\(encodedRole).signature") == nil)
        let suite = "focusfix.test.account.\(UUID().uuidString)"
        let preferences = UserDefaults(suiteName: suite)!
        defer { preferences.removePersistentDomain(forName: suite) }
        let owner = UUID()
        let remote = UserProfile(name: "Test user", symbol: "leaf.fill", color: "teal")
        let session = AccountSession(access_token: "test-access", refresh_token: "test-refresh",
            expires_at: Date().addingTimeInterval(3600).timeIntervalSince1970, expires_in: 3600,
            user: AccountUser(id: owner, email: "test@example.invalid"))
        var requests: [URLRequest] = []
        var stored: Data?
        var reads = 0
        var signupConfirmed = false
        var failProfile = false
        var statusOverride: Int?
        let transport: AccountAPI.Transport = { request in
            requests.append(request)
            precondition(request.url!.scheme == "https")
            precondition(request.value(forHTTPHeaderField: "apikey") == config.publicKey)
            var data = Data("{}".utf8)
            var status = 200
            if request.url!.path.contains("account_profiles") {
                precondition(request.value(forHTTPHeaderField: "Authorization") == "Bearer test-access")
                if failProfile { status = 503 }
                else if request.httpMethod == "GET" {
                    precondition(URLComponents(url: request.url!, resolvingAgainstBaseURL: false)!.queryItems!.contains {
                        $0.name == "user_id" && $0.value == "eq.\(owner.uuidString.lowercased())"
                    })
                    data = try JSONEncoder().encode([AccountProfileRow(user_id: owner, profile: remote)])
                }
            } else if request.url!.path == "/auth/v1/signup" {
                if signupConfirmed { data = try JSONEncoder().encode(session) }
            } else if request.url!.path == "/auth/v1/token" || request.url!.path == "/auth/v1/verify" {
                data = try JSONEncoder().encode(session)
            }
            return (data, HTTPURLResponse(url: request.url!, statusCode: statusOverride ?? status, httpVersion: nil, headerFields: nil)!)
        }
        let controller = AccountController(configuration: config, transport: transport,
            readCredential: { reads += 1; return stored }, writeCredential: { stored = $0 }, defaults: preferences)
        precondition(reads == 0 && requests.isEmpty) // Launch never touches Keychain or network.
        await controller.authenticate(email: "bad", password: "short", create: true)
        precondition(requests.isEmpty)
        await controller.authenticate(email: "test@example.invalid", password: "test-password", create: true)
        precondition(controller.needsConfirmation && controller.session == nil)
        await controller.verify(email: "test@example.invalid", code: "123456", newPassword: "")
        precondition(controller.session?.user.id == owner && controller.profile == remote && controller.profileLoaded)
        precondition(stored != nil)
        let saved = await controller.saveProfile(UserProfile(name: "Updated name"))
        precondition(saved)
        let profileBody = try JSONDecoder().decode(AccountProfileRow.self, from: requests.last!.httpBody!)
        precondition(profileBody.user_id == owner && profileBody.profile.name == "Updated name")
        await controller.signOut()
        precondition(controller.session == nil && controller.profile == nil && stored == nil)
        failProfile = true
        await controller.authenticate(email: "test@example.invalid", password: "test-password", create: false)
        precondition(controller.session != nil && !controller.profileLoaded)
        let beforeFailedSave = requests.count
        let blocked = await controller.saveProfile(remote)
        precondition(!blocked && requests.count == beforeFailedSave)
        failProfile = false
        await controller.loadProfile()
        precondition(controller.profileLoaded)
        await controller.signOut()
        let wrong = StoredAccount(origin: "https://another.supabase.co", session: session)
        stored = try JSONEncoder().encode(wrong)
        let count = requests.count
        await controller.restore()
        precondition(controller.session == nil && requests.count == count && reads == 1)
        stored = try JSONEncoder().encode(StoredAccount(origin: config.origin.absoluteString, session: session))
        await controller.restore()
        precondition(controller.session?.user.id == owner && reads == 2)
        statusOverride = 429
        let api = AccountAPI(configuration: config, transport: transport)
        do { _ = try await api.signIn(email: "test@example.invalid", password: "test-password"); preconditionFailure("Expected quota failure") }
        catch { precondition(!error.localizedDescription.contains("test-password")) }
        statusOverride = nil
        await controller.deleteAccount()
        precondition(controller.session == nil && stored == nil)
        precondition(requests.contains { $0.url!.path == "/functions/v1/delete-account" })
        signupConfirmed = true
        await controller.authenticate(email: "test@example.invalid", password: "test-password", create: true)
        precondition(controller.session != nil && !controller.needsConfirmation)
        await controller.signOut()
        await controller.requestRecovery(email: "test@example.invalid")
        precondition(controller.recovering)
        await controller.verify(email: "test@example.invalid", code: "654321", newPassword: "replacement-password")
        precondition(controller.session != nil && !controller.recovering)
        precondition(requests.contains { $0.url!.path == "/auth/v1/user" && $0.httpMethod == "PUT" })
        print("Account configuration, fake authentication, private profile sync, recovery and sign-out passed")
    }
}
