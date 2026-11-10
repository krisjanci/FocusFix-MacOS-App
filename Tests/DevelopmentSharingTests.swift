import Foundation

@main struct DevelopmentSharingTests {
    static func main() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let start = Date(timeIntervalSince1970: 100)
        let writer = try RecordingWriter(root: root, id: UUID().uuidString, startedAt: start, mode: .automatic)
        try writer.event(time: 1, type: "left_click_down")
        try writer.finish(startedAt: start, duration: 30, reason: "fixture")
        let consent = DevelopmentConsent(id: UUID(), owner: UUID(), origin: "https://example.invalid",
            policyVersion: "development-v1", startedAt: Date(timeIntervalSince1970: 99))
        var state = DevelopmentSharingState()
        state.enable(consent)
        precondition(!state.enqueue(folder: writer.folder, startedAt: Date(timeIntervalSince1970: 98), captured: consent))
        precondition(!state.enqueue(folder: writer.folder, startedAt: start, captured: nil))
        precondition(state.enqueue(folder: writer.folder, startedAt: start, captured: consent))
        precondition(!state.enqueue(folder: writer.folder, startedAt: start, captured: consent))
        let names = try DevelopmentArchive.sources(id: writer.folder.lastPathComponent, root: root).map(\.lastPathComponent)
        precondition(names == DevelopmentArchive.files)
        try Data("private credential".utf8).write(to: writer.folder.appendingPathComponent("credentials.json"))
        let destination = root.appendingPathComponent("test.zip")
        let data = try DevelopmentArchive.prepare(id: writer.folder.lastPathComponent, root: root,
                                                  consent: consent, destination: destination)
        precondition(!data.isEmpty)
        let process = Process(), pipe = Pipe()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/unzip")
        process.arguments = ["-Z1", destination.path]
        process.standardOutput = pipe
        try process.run()
        let listing = String(decoding: pipe.fileHandleForReading.readDataToEndOfFile(), as: UTF8.self)
        process.waitUntilExit()
        precondition(process.terminationStatus == 0)
        precondition(listing.contains("events.csv") && listing.contains("sharing_manifest.json"))
        precondition(!listing.contains("credentials") && !listing.contains("surveys.csv") &&
                     !listing.contains("research_eligibility"))
        state.disable()
        precondition(state.consent == nil && state.pending.isEmpty && state.pendingWithdrawals == [consent])
        do {
            _ = try DevelopmentArchive.sources(id: "../invalid", root: root)
            preconditionFailure("Invalid path was accepted")
        } catch { }
        print("PASS: consent boundary, deduplication, archive allowlist and path safety")
    }
}
