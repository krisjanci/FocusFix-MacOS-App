import Foundation

// Synthetic histories only. Timing is informational; correctness assertions do not
// depend on machine speed. Compile with -O for comparable before/after measurements.
@main @MainActor struct RecordingEfficiencyTests {
    static func main() async throws {
        let calendar = DailyProgress.calendar(timeZone: TimeZone(identifier: "America/New_York")!)
        let end = Date(timeIntervalSince1970: 1795000000)
        let start = calendar.date(byAdding: .day, value: -3650, to: end)!
        var progress = DailyProgress(); progress.reconcile(at: start, calendar: calendar)
        for day in 0..<3650 {
            progress.addWork(seconds: 3600, endingAt: calendar.date(byAdding: .day, value: day, to: start)!.addingTimeInterval(7200), calendar: calendar)
        }
        var cold = progress
        var before = Date()
        for _ in 0..<20 { cold.frozenDays = []; cold.reconcile(at: end, calendar: calendar) }
        let coldMS = Date().timeIntervalSince(before) * 1000 / 20
        progress.reconcile(at: end, calendar: calendar)
        let passes = progress.reconciliationPasses
        before = Date()
        for _ in 0..<20 { progress.reconcile(at: end, calendar: calendar) }
        let cachedMS = Date().timeIntervalSince(before) * 1000 / 20
        precondition(progress == cold && progress.reconciliationPasses == passes)
        print(String(format: "PERF ten-year history: full %.3f ms, cached %.3f ms per reconcile", coldMS, cachedMS))

        let manager = FileManager.default
        let root = manager.temporaryDirectory.appendingPathComponent("recording-efficiency-\(UUID())")
        defer { try? manager.removeItem(at: root) }
        let owner = UUID(), origin = "https://efficiency.invalid"
        let configuration = AccountConfiguration(url: origin, publicKey: "sb_publishable_test")!
        let account = AccountController(configuration: configuration, transport: { request in
            let data: Data
            if request.url!.path.contains("auth/v1/token") {
                data = try JSONEncoder().encode(AccountSession(access_token: "fake", refresh_token: "fake", expires_at: Date().timeIntervalSince1970 + 3600,
                    expires_in: 3600, user: AccountUser(id: owner, email: nil)))
            } else if request.url!.path.contains("account_profiles") { data = Data("[]".utf8) }
            else { throw URLError(.notConnectedToInternet) }
            return (data, HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!)
        }, readCredential: { nil }, writeCredential: { _ in }, defaults: nil)
        await account.authenticate(email: "synthetic@example.invalid", password: "fake", create: false)
        var ledger = SocialLedger(timezone: "America/New_York")
        let stamp = end.timeIntervalSince1970
        for index in 0..<2000 {
            let segment = UUID()
            let value = DeclaredWorkPending(ownerID: owner, origin: origin, segmentID: segment, contractVersion: 2,
                days: ["2026-11-17": 60], startedAt: stamp - Double(index + 1) * 100,
                observedThrough: stamp - Double(index + 1) * 100 + 60,
                intervals: [.init(start: stamp - Double(index + 1) * 100, end: stamp - Double(index + 1) * 100 + 60)])
            precondition(ledger.stageDeclaredWork(value, owner: owner, origin: origin))
        }
        let key = "\(origin)|\(owner)"
        let name = Data(key.utf8).base64EncodedString().replacingOccurrences(of: "/", with: "_").replacingOccurrences(of: "+", with: "-")
        let file = root.appendingPathComponent("FocusFix/Social/\(name).json")
        try manager.createDirectory(at: file.deletingLastPathComponent(), withIntermediateDirectories: true)
        try JSONEncoder().encode(ledger).write(to: file, options: .atomic)
        let segment = UUID()
        func update(_ second: Int) -> DeclaredWorkPending {
            DeclaredWorkPending(ownerID: owner, origin: origin, segmentID: segment, contractVersion: 2,
                days: ["2026-11-18": Double(second)], startedAt: stamp, observedThrough: stamp + Double(second),
                intervals: [.init(start: stamp, end: stamp + Double(second))])
        }
        var baseline = ledger, baselineBytes = 0
        let baselineFile = root.appendingPathComponent("baseline.json")
        before = Date()
        for second in 1...30 {
            precondition(baseline.stageDeclaredWork(update(second), owner: owner, origin: origin))
            let bytes = try JSONEncoder().encode(baseline); baselineBytes += bytes.count
            try bytes.write(to: baselineFile, options: .atomic)
        }
        let baselineMS = Date().timeIntervalSince(before) * 1000 / 30
        let controller = SocialController(account: account, storageDirectory: root, selectionDefaults: nil)
        await controller.refresh() // Alignment, including the initial full snapshot, is outside timing.
        let fullBefore = try Data(contentsOf: file)
        var journalBytes = 0
        before = Date()
        for second in 1...30 {
            let value = update(second)
            controller.stageDeclaredWork(segmentID: segment, days: value.days, capturedOwner: owner, capturedOrigin: origin,
                startedAt: value.startedAt, observedThrough: value.observedThrough, intervals: value.intervals)
            journalBytes += try Data(contentsOf: file.appendingPathExtension("work").appendingPathComponent(segment.uuidString + ".json")).count
        }
        let journalMS = Date().timeIntervalSince(before) * 1000 / 30
        let fullAfter = try Data(contentsOf: file)
        precondition(fullAfter == fullBefore, "Live work rewrote the full ledger")
        let journalFile = file.appendingPathExtension("work").appendingPathComponent(segment.uuidString + ".json")
        let latestJournal = try Data(contentsOf: journalFile)
        let recovered = SocialController(account: account, storageDirectory: root, selectionDefaults: nil)
        await recovered.refresh()
        precondition(recovered.ledger?.declaredWorkPending?[segment.uuidString]?.revision == 30)
        precondition(recovered.ledger?.declaredWorkPending?[segment.uuidString]?.days == ["2026-11-18": 30])
        // Simulate a crash after the acknowledged full snapshot was saved but before
        // its journal directory was removed. Equal revisions must not resurrect work.
        var acknowledged = recovered.ledger!
        let sent = acknowledged.declaredWorkPending![segment.uuidString]!
        acknowledged.acknowledgeDeclaredWork([.init(segmentID: segment, revision: 30)], sent: [sent])
        try JSONEncoder().encode(acknowledged).write(to: file, options: .atomic)
        try manager.createDirectory(at: journalFile.deletingLastPathComponent(), withIntermediateDirectories: true)
        try latestJournal.write(to: journalFile, options: .atomic)
        let afterAcknowledgement = SocialController(account: account, storageDirectory: root, selectionDefaults: nil)
        await afterAcknowledgement.refresh()
        precondition(afterAcknowledgement.ledger?.declaredWorkPending?[segment.uuidString] == nil)
        afterAcknowledgement.discardCache(userID: owner, origin: configuration.origin)
        precondition(!manager.fileExists(atPath: file.path) && !manager.fileExists(atPath: file.appendingPathExtension("work").path))
        print(String(format: "PERF 2,000-segment ledger, main-actor work: full %.3f ms, journal %.3f ms/update", baselineMS, journalMS))
        print("PERF 30 updates: full ledger replacements 30 -> 0; durable segment replacements 0 -> 30; encoded bytes \(baselineBytes) -> \(journalBytes)")
        print("PASS: equivalent progress, durable latest work after replay and no full-ledger writes during live work")
    }
}
