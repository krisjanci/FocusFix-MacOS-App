import Foundation

@main @MainActor struct DevelopmentDeliveryTests {
    static func main() async throws {
        let manager = FileManager.default
        let root = manager.temporaryDirectory.appendingPathComponent("development-delivery-\(UUID())")
        defer { try? manager.removeItem(at: root) }
        let recordings = root.appendingPathComponent("Sessions")
        let sharing = root.appendingPathComponent("Sharing")
        try manager.createDirectory(at: sharing, withIntermediateDirectories: true)
        let owner = UUID(), start = Date()
        let consent = DevelopmentConsent(id: UUID(), owner: owner, origin: "https://example.invalid",
            policyVersion: "test", startedAt: start.addingTimeInterval(-1))
        var state = DevelopmentSharingState(); state.enable(consent)
        for _ in 0..<2 {
            let writer = try RecordingWriter(root: recordings, id: UUID().uuidString, startedAt: start)
            try writer.finish(startedAt: start, duration: 2, reason: "fixture")
            precondition(state.enqueue(folder: writer.folder, startedAt: start, captured: consent))
        }
        let deleted = state.pending[0].id, valid = state.pending[1].id
        try manager.removeItem(at: recordings.appendingPathComponent(deleted))
        let stateFile = sharing.appendingPathComponent("state.json")
        try JSONEncoder().encode(state).write(to: stateFile)
        var uploaded: [String] = [], offline = true, hosted = false
        let config = AccountConfiguration(url: consent.origin, publicKey: "sb_publishable_test",
            developmentSharingEnabled: true, privacyURL: "https://example.invalid/privacy")!
        let api: AccountAPI.Transport = { request in
            let path = request.url!.path
            var data = Data("[]".utf8), status = 200
            if path.contains("auth/v1/token") {
                data = try JSONEncoder().encode(AccountSession(access_token: "fake", refresh_token: "fake", expires_at: Date().timeIntervalSince1970 + 3600,
                    expires_in: 3600, user: AccountUser(id: owner, email: nil)))
            } else if path.contains("development_collection") { data = Data("[{\"enabled\":true,\"policy_version\":\"test\"}]".utf8) }
            else if path.contains("development_approvals") { data = Data("[{\"enabled\":true}]".utf8) }
            else if path.contains("development_consents") {
                data = try JSONEncoder().encode([DevelopmentServerConsent(consent_id: consent.id, policy_version: "test", withdrawn_at: nil)])
            } else if path.contains("storage/v1/object/info") {
                if offline { throw URLError(.notConnectedToInternet) }
                status = hosted ? 200 : 404; data = Data("{}".utf8)
            } else if path.contains("storage/v1/object/") {
                if offline { throw URLError(.notConnectedToInternet) }
                precondition(request.httpMethod == "POST", "Local deletion must never delete hosted data")
                uploaded.append(path); data = Data("{}".utf8)
            }
            return (data, HTTPURLResponse(url: request.url!, statusCode: status, httpVersion: nil, headerFields: nil)!)
        }
        let account = AccountController(configuration: config, transport: api, readCredential: { nil }, writeCredential: { _ in }, defaults: nil)
        await account.authenticate(email: "fixture@example.invalid", password: "fixture", create: false)
        var controller: DevelopmentSharingController? = DevelopmentSharingController(account: account, root: sharing, recordings: recordings, startTimer: false, defaults: nil)
        await controller!.refresh()
        controller!.checkDue()
        for _ in 0..<1000 {
            if controller!.notice.contains("Delivery paused") { break }
            try await Task.sleep(for: .milliseconds(2))
        }
        // Temporary network failure must retain the valid archive even if the missing head is pruned.
        precondition(controller!.state.pending.contains { $0.id == valid })
        controller = nil
        offline = false
        controller = DevelopmentSharingController(account: account, root: sharing, recordings: recordings, startTimer: false, defaults: nil)
        await controller!.refresh(); controller!.checkDue()
        for _ in 0..<1000 {
            if controller!.state.pending.isEmpty { break }
            try await Task.sleep(for: .milliseconds(2))
        }
        precondition(controller!.state.pending.isEmpty, "Deleted head blocked later upload across relaunch")
        precondition(uploaded.count == 1 && uploaded[0].contains(valid.lowercased()))
        let saved = try JSONDecoder().decode(DevelopmentSharingState.self, from: Data(contentsOf: stateFile))
        precondition(saved.pending.isEmpty)
        // A previously received archive with no local source is acknowledged without reupload/deletion.
        var received = state; received.pending = [state.pending[0]]
        controller = nil; hosted = true
        try JSONEncoder().encode(received).write(to: stateFile)
        controller = DevelopmentSharingController(account: account, root: sharing, recordings: recordings, startTimer: false, defaults: nil)
        await controller!.refresh(); controller!.checkDue()
        for _ in 0..<1000 {
            if controller!.state.pending.isEmpty { break }
            try await Task.sleep(for: .milliseconds(2))
        }
        precondition(controller!.state.pending.isEmpty && uploaded.count == 1)
        print("PASS: missing upload head, temporary network retry, persisted relaunch and hosted deduplication")
    }
}
