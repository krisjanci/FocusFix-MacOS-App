import Foundation

@main @MainActor
struct LaunchCoordinatorTests {
    static func waitUntil(_ condition: () -> Bool) async {
        for _ in 0..<300 {
            if condition() { return }
            try? await Task.sleep(nanoseconds: 10_000_000)
        }
        preconditionFailure("Startup did not reach its expected state")
    }

    static func main() async throws {
        let suite = "focusfix.test.launch.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }
        let config = AccountConfiguration(url: "https://example.supabase.co", publicKey: "sb_publishable_test")!
        let value = AccountSession(access_token: "test-access", refresh_token: "test-refresh",
            expires_at: Date().addingTimeInterval(3600).timeIntervalSince1970, expires_in: 3600,
            user: AccountUser(id: UUID(), email: "test@example.invalid"))
        var stored: Data?
        var reads = 0
        var writes = 0
        var requests = 0
        var pause = false
        var fail = false
        var pending: CheckedContinuation<(Data, HTTPURLResponse), Error>?
        let transport: AccountAPI.Transport = { request in
            requests += 1
            let path = request.url!.path
            if path == "/auth/v1/token", pause {
                return try await withCheckedThrowingContinuation { pending = $0 }
            }
            let data: Data
            if path == "/auth/v1/token" || path == "/auth/v1/verify" { data = try JSONEncoder().encode(value) }
            else if path == "/rest/v1/account_profiles" { data = Data("[]".utf8) }
            else { data = Data("{}".utf8) }
            return (data, HTTPURLResponse(url: request.url!, statusCode: fail ? 503 : 200, httpVersion: nil, headerFields: nil)!)
        }
        func account(configured: Bool = true) -> AccountController {
            AccountController(configuration: configured ? config : nil, transport: transport,
                readCredential: { reads += 1; return stored },
                writeCredential: { stored = $0; writes += 1 }, defaults: defaults)
        }
        defaults.set(true, forKey: "focusfix.account.keepSignedIn")
        let first = account(configured: false)
        let firstLaunch = LaunchCoordinator(account: first, defaults: defaults)
        firstLaunch.begin()
        precondition(firstLaunch.page == .welcome && requests == 0 && reads == 0)
        var starts = 0
        var shows = 0
        firstLaunch.requestStart(start: { starts += 1 }, showWindow: { shows += 1 })
        precondition(starts == 0 && shows == 1)
        firstLaunch.useGuest()
        precondition(firstLaunch.page == .app && reads == 0 && writes == 0)
        firstLaunch.requestStart(start: { starts += 1 }, showWindow: { shows += 1 })
        precondition(starts == 1)
        let guestRelaunch = LaunchCoordinator(account: account(), defaults: defaults)
        guestRelaunch.begin()
        precondition(guestRelaunch.page == .app && requests == 0 && reads == 0)

        let signedIn = account()
        let signupLaunch = LaunchCoordinator(account: signedIn, defaults: defaults)
        signupLaunch.showAccount(create: true)
        await signedIn.authenticate(email: "test@example.invalid", password: "test-password", create: true)
        precondition(signedIn.needsConfirmation && signedIn.session == nil && signupLaunch.page == .createAccount)
        await signedIn.verify(email: "test@example.invalid", code: "123456", newPassword: "")
        precondition(signupLaunch.page == .profileSetup && stored != nil && signedIn.remembersSignIn)
        signupLaunch.finishProfileSetup()
        precondition(signupLaunch.canRecord)
        let returning = account()
        let returningLaunch = LaunchCoordinator(account: returning, defaults: defaults)
        precondition(reads == 0) // Creating the coordinator doesn't read Keychain.
        returningLaunch.begin()
        await waitUntil { returningLaunch.page == .app && !returning.busy }
        precondition(returning.session != nil && reads == 1)
        let afterRestore = requests
        returningLaunch.begin()
        precondition(requests == afterRestore) // Closing/reopening the window doesn't restore twice.
        await returning.signOut()
        precondition(returningLaunch.page == .app && !returning.remembersSignIn && stored == nil)

        // An unchecked preference never saves or auto-restores a token.
        let transient = account()
        await transient.authenticate(email: "test@example.invalid", password: "test-password", create: false, remember: false)
        precondition(transient.session != nil && stored == nil && !transient.remembersSignIn)

        // A saved-account failure falls back to welcome rather than trapping the user.
        stored = try JSONEncoder().encode(StoredAccount(origin: config.origin.absoluteString, session: value))
        defaults.set(true, forKey: "focusfix.account.keepSignedIn")
        defaults.set(false, forKey: "focusfix.launch.guest")
        fail = true
        let offline = account()
        let offlineLaunch = LaunchCoordinator(account: offline, defaults: defaults)
        offlineLaunch.begin()
        await waitUntil { offlineLaunch.page == .welcome && !offline.busy }
        precondition(offline.session == nil && offline.notice != nil)
        offlineLaunch.useGuest()
        precondition(offlineLaunch.canRecord)
        fail = false

        // Guest cancels a slow saved restoration. Even a transport ignoring cancellation cannot sign in later.
        defaults.set(true, forKey: "focusfix.account.keepSignedIn")
        defaults.set(false, forKey: "focusfix.launch.guest")
        pause = true
        let delayed = account()
        let delayedLaunch = LaunchCoordinator(account: delayed, defaults: defaults)
        delayedLaunch.begin()
        await waitUntil { pending != nil }
        let writesBeforeGuest = writes
        delayedLaunch.useGuest()
        pending!.resume(returning: (try JSONEncoder().encode(value), HTTPURLResponse(url: config.origin, statusCode: 200, httpVersion: nil, headerFields: nil)!))
        pending = nil
        try? await Task.sleep(nanoseconds: 30_000_000)
        precondition(delayed.session == nil && !delayed.busy && !delayed.remembersSignIn)
        precondition(delayedLaunch.page == .app && writes == writesBeforeGuest)

        // The same protection applies to a login started from the welcome form.
        let login = account()
        let loginLaunch = LaunchCoordinator(account: login, defaults: defaults)
        loginLaunch.showAccount(create: false)
        let loginTask = Task { await login.authenticate(email: "test@example.invalid", password: "test-password", create: false) }
        await waitUntil { pending != nil }
        loginLaunch.useGuest()
        pending!.resume(returning: (try JSONEncoder().encode(value), HTTPURLResponse(url: config.origin, statusCode: 200, httpVersion: nil, headerFields: nil)!))
        pending = nil
        await loginTask.value
        precondition(login.session == nil && loginLaunch.canRecord && writes == writesBeforeGuest)
        // Preview reuses navigation but has no API, credentials or persistent preferences.
        let preferencesBeforePreview = defaults.dictionaryRepresentation() as NSDictionary
        let tokenBeforePreview = stored
        let sessionBeforePreview = transient.session?.access_token
        let countersBeforePreview = [reads, writes, requests]
        let preview = LaunchCoordinator.preview()
        precondition(preview.isPreview && !preview.account.configured && preview.account.api == nil)
        preview.begin()
        preview.restore()
        precondition(preview.page == .welcome)
        preview.showAccount(create: true)
        precondition(preview.page == .createAccount)
        await preview.account.authenticate(email: "sample@example.invalid", password: "sample-password", create: true)
        await preview.account.verify(email: "sample@example.invalid", code: "123456", newPassword: "")
        preview.showWelcome()
        preview.showAccount(create: false)
        precondition(preview.page == .login)
        await preview.account.authenticate(email: "sample@example.invalid", password: "sample-password", create: false)
        await preview.account.requestRecovery(email: "sample@example.invalid")
        await preview.account.restore()
        preview.useGuest()
        precondition(preview.page == .app && preview.account.session == nil)
        let startsBeforePreview = starts
        preview.requestStart(start: { starts += 1 }, showWindow: {})
        precondition(starts == startsBeforePreview)
        precondition(LaunchCoordinator.preview().page == .welcome)
        precondition(countersBeforePreview == [reads, writes, requests])
        precondition(defaults.dictionaryRepresentation() as NSDictionary == preferencesBeforePreview)
        precondition(stored == tokenBeforePreview && transient.session?.access_token == sessionBeforePreview)
        print("Offline preview navigation preserved real account, preferences and credentials")
        print("First launch, guest persistence, registration, remembered sign-in, menu gating and cancellation passed")
    }
}
