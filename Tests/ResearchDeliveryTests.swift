import Foundation

@main @MainActor
struct ResearchDeliveryTests {
    static func waitUntil(_ predicate: () -> Bool) async {
        for _ in 0..<500 {
            if predicate() { return }
            try? await Task.sleep(nanoseconds: 10_000_000)
        }
        preconditionFailure("Synthetic delivery did not finish")
    }

    static func main() async throws {
        let owner = UUID()
        let configuration = AccountConfiguration(url: "https://example.supabase.co", publicKey: "sb_publishable_test", researchSharingEnabled: true, studyURL: "https://example.invalid/study")!
        let session = AccountSession(access_token: "test-access", refresh_token: "test-refresh",
            expires_at: Date().addingTimeInterval(3600).timeIntervalSince1970, expires_in: 3600,
            user: AccountUser(id: owner, email: "test@example.invalid"))
        var approved = false
        var uploads: [URLRequest] = []
        var receipts = Set<String>()
        var uploadStatus = 200
        var pause = false
        var pending: CheckedContinuation<(Data, HTTPURLResponse), Error>?
        let account = AccountController(configuration: configuration, transport: { request in
            let path = request.url!.path
            var data = Data("{}".utf8)
            if path.contains("/storage/") {
                uploads.append(request)
                precondition(request.value(forHTTPHeaderField: "Content-Type") == "application/zip")
                precondition(request.value(forHTTPHeaderField: "Authorization") == "Bearer test-access")
                precondition(path.hasPrefix("/storage/v1/object/research-sessions/\(owner.uuidString.lowercased())/"))
                precondition(request.httpBody!.starts(with: [0x50, 0x4b]))
                if pause { return try await withCheckedThrowingContinuation { pending = $0 } }
                return (data, HTTPURLResponse(url: request.url!, statusCode: uploadStatus, httpVersion: nil, headerFields: nil)!)
            } else if path == "/rest/v1/research_upload_receipts" {
                let id = URLComponents(url: request.url!, resolvingAgainstBaseURL: false)!.queryItems!.first { $0.name == "archive_id" }!.value!.dropFirst(3)
                data = try JSONEncoder().encode(receipts.contains(String(id)) ? [["archive_id": String(id)]] : [])
            } else if path == "/rest/v1/rpc/confirm_research_upload" {
                let body = try JSONSerialization.jsonObject(with: request.httpBody!) as! [String: String]
                receipts.insert(body["p_archive_id"]!)
            } else if path == "/rest/v1/research_enrollments" {
                data = try JSONEncoder().encode(approved ? [ResearchEnrollment(user_id: owner, enabled: true, consent_version: "test-consent-v1")] : [])
            } else if path == "/auth/v1/token" { data = try JSONEncoder().encode(session) }
            else if path.contains("account_profiles") { data = Data("[]".utf8) }
            return (data, HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!)
        }, readCredential: { nil }, writeCredential: { _ in })
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let recordings = root.appendingPathComponent("Sessions")
        let queue = root.appendingPathComponent("Queue")
        let research = ResearchSharingController(account: account, root: queue, recordings: recordings, startTimer: false)
        precondition(!research.enabled && uploads.isEmpty)
        await account.authenticate(email: "test@example.invalid", password: "test-password", create: false)
        precondition(!research.enabled) // Signing in is never research consent.
        research.enable()
        precondition(!research.enabled) // No selection/approval means no sharing.
        await account.requestResearchParticipation()
        precondition(uploads.isEmpty && !research.enabled)
        approved = true
        _ = await account.refreshResearchAccess()
        research.enable()
        precondition(research.enabled)
        let consent = research.capturedConsent!
        func enqueue() throws {
            let id = UUID().uuidString
            let folder = recordings.appendingPathComponent(id)
            try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
            for name in ResearchArchive.files { try Data("synthetic".utf8).write(to: folder.appendingPathComponent(name)) }
            research.finished(folder: folder, startedAt: Date(), captured: consent)
        }
        try enqueue()
        await waitUntil { !research.busy } // Finishing the session starts delivery immediately.
        precondition(uploads.count == 1 && research.state.sessions.isEmpty)
        precondition(research.state.batch == nil)
        precondition(FileManager.default.fileExists(atPath: recordings.path))
        approved = false
        _ = await account.refreshResearchAccess()
        let uploadsBeforeRevocation = uploads.count
        research.deliver()
        precondition(uploads.count == uploadsBeforeRevocation && !research.enabled)
        approved = true
        _ = await account.refreshResearchAccess()
        uploadStatus = 402
        try enqueue()
        await waitUntil { !research.busy }
        precondition(research.state.sessions.count == 1 && research.state.batch != nil)
        let pathBeforeRetry = uploads.last!.url!.path
        let restored = ResearchSharingController(account: account, root: queue, recordings: recordings, startTimer: false)
        precondition(restored.state.sessions.count == 1 && restored.state.batch == research.state.batch)
        let exported = root.appendingPathComponent("review.zip")
        try await restored.export(to: exported)
        precondition(FileManager.default.fileExists(atPath: exported.path))
        precondition(restored.state.sessions.count == 1)
        uploadStatus = 200
        restored.deliver()
        await waitUntil { !restored.busy }
        precondition(uploads.last!.url!.path == pathBeforeRetry) // Same object key across retries/relaunch.
        precondition(restored.state.sessions.isEmpty)
        let countAfterReceipt = uploads.count
        research.deliver() // Old queue snapshot after remote cleanup: receipt must suppress re-upload.
        await waitUntil { !research.busy }
        precondition(uploads.count == countAfterReceipt && research.state.sessions.isEmpty)
        // Use the restored instance from now on; queue creation is synthetic and scoped to this consent.
        let id = UUID().uuidString
        let folder = recordings.appendingPathComponent(id)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        for name in ResearchArchive.files { try Data("synthetic".utf8).write(to: folder.appendingPathComponent(name)) }
        pause = true
        restored.finished(folder: folder, startedAt: Date(), captured: consent)
        await waitUntil { pending != nil }
        restored.disable()
        pending!.resume(returning: (Data("{}".utf8), HTTPURLResponse(url: uploads.last!.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!))
        pending = nil
        try? await Task.sleep(nanoseconds: 50_000_000)
        precondition(!restored.enabled && restored.state.sessions.isEmpty)
        precondition(!restored.notice.contains("delivered")) // Late success cannot reinstate an opted-out queue.
        await account.signOut()
        precondition(!research.enabled && !restored.enabled)
        print("Per-session delivery, approval checks, quota failures, durable retry keys, export and in-flight opt-out passed")
    }
}
