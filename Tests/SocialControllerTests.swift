import Foundation

@main @MainActor struct SocialControllerTests {
    static func main() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("social-test-\(UUID())")
        defer { try? FileManager.default.removeItem(at: root) }
        let owner = UUID(), other = UUID()
        var active = owner
        var offline = false
        var block = false
        var continuation: CheckedContinuation<Void, Never>?
        var bodies: [[String: Any]] = []
        let config = AccountConfiguration(url: "https://example.supabase.co", publicKey: "sb_publishable_test")!
        let transport: AccountAPI.Transport = { request in
            var data = Data("{}".utf8)
            if request.url!.path.contains("auth/v1/token") {
                data = try JSONEncoder().encode(AccountSession(access_token: active.uuidString, refresh_token: "fake-refresh",
                    expires_at: Date().timeIntervalSince1970 + 3600, expires_in: 3600,
                    user: AccountUser(id: active, email: nil)))
            } else if request.url!.path.contains("account_profiles") { data = Data("[]".utf8) }
            else if request.url!.path.contains("social_state") {
                if offline { throw URLError(.notConnectedToInternet) }
                let object = try JSONSerialization.jsonObject(with: request.httpBody!) as! [String: Any]
                bodies.append(object)
                if block { await withCheckedContinuation { continuation = $0 } }
                var progress = DailyProgress()
                progress.reconcile(at: Date(), calendar: DailyProgress.calendar(timeZone: TimeZone(secondsFromGMT: 0)!))
                data = try JSONEncoder().encode(SocialState(timezone: "UTC", progress: progress, groups: []))
            }
            return (data, HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!)
        }
        let account = AccountController(configuration: config, transport: transport,
            readCredential: { nil }, writeCredential: { _ in }, defaults: nil)
        let social = SocialController(account: account, storageDirectory: root)
        social.record(kind: "work", seconds: 60)
        precondition(!social.enabled && bodies.isEmpty)
        await account.authenticate(email: "test@example.invalid", password: "test-password", create: false)
        await social.refresh()
        precondition(!social.enabled && bodies.isEmpty) // No implicit opt-in or guest history.
        await social.enable()
        precondition(social.enabled && bodies.count == 1 && social.ledger?.timezone == "UTC")
        offline = true
        social.record(kind: "work", seconds: 60, at: Date().addingTimeInterval(61))
        await social.refresh()
        precondition(social.ledger?.pending.count == 1 && social.pendingConfirmation)
        // A fresh process reloads the same durable outbox, scoped to account and origin.
        let restored = SocialController(account: account, storageDirectory: root)
        await restored.refresh()
        precondition(restored.ledger?.pending.count == 1)
        let submittedID = restored.ledger!.pending[0].id
        offline = false; block = true
        let request = Task { await restored.refresh() }
        while continuation == nil { await Task.yield() }
        restored.record(kind: "work", seconds: 1, at: Date().addingTimeInterval(62))
        precondition(restored.ledger?.pending.count == 2)
        precondition(restored.ledger!.pending[0].id == submittedID)
        precondition(restored.ledger!.pending[0].seconds == 60)
        await account.signOut()
        active = other
        await account.authenticate(email: "other@example.invalid", password: "test-password", create: false)
        restored.record(kind: "work", seconds: 60)
        precondition(!restored.enabled && restored.groups.isEmpty)
        continuation?.resume(); continuation = nil
        await request.value
        precondition(!restored.enabled && restored.groups.isEmpty) // Old response cannot repopulate another account.
        block = false
        await restored.enable()
        let payload = bodies.last!["p_payload"] as! [String: Any]
        precondition((payload["events"] as! [[String: Any]]).isEmpty)
        await account.signOut(); active = owner
        await account.authenticate(email: "test@example.invalid", password: "test-password", create: false)
        await restored.refresh()
        let ownPayload = bodies.last!["p_payload"] as! [String: Any]
        precondition((ownPayload["events"] as! [[String: Any]]).count == 2)
        precondition(restored.ledger?.pending.isEmpty == true)
        restored.discardCache(userID: owner, origin: config.origin)
        precondition(!restored.enabled)
        let afterDeletion = SocialController(account: account, storageDirectory: root)
        await afterDeletion.refresh()
        precondition(!afterDeletion.enabled)
        print("Social opt-in, durable offline outbox, account isolation, stale responses and retry acknowledgement passed")
    }
}
