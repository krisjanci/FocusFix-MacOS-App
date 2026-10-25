import Foundation

@main
struct ResearchSharingTests {
    static func main() throws {
        let owner = UUID()
        let now = Date()
        let first = UUID().uuidString
        let second = UUID().uuidString
        var state = ResearchSharingState()
        precondition(!state.enqueue(id: first, startedAt: now, endedAt: now, captured: nil))
        state.enable(owner: owner, origin: "https://example.supabase.co", at: now, studyVersion: "test-consent-v1")
        let consent = state.consent!
        precondition(!state.enqueue(id: first, startedAt: now.addingTimeInterval(-1), endedAt: now, captured: consent))
        precondition(!state.enqueue(id: "../unsafe", startedAt: now, endedAt: now, captured: consent))
        precondition(state.enqueue(id: first, startedAt: now, endedAt: now.addingTimeInterval(60), captured: consent))
        precondition(!state.enqueue(id: first, startedAt: now, endedAt: now, captured: consent))
        precondition(state.enqueue(id: second, startedAt: now, endedAt: now, captured: consent))
        let batch = ResearchBatch(id: UUID(), sessionIDs: [first])
        state.batch = batch
        let reloaded = try JSONDecoder().decode(ResearchSharingState.self, from: JSONEncoder().encode(state))
        precondition(reloaded == state)
        state.acknowledge(batchID: UUID(), at: now)
        precondition(state.sessions.count == 2)
        state.acknowledge(batchID: batch.id, at: now)
        precondition(state.sessions.map(\.id) == [second])
        state.disable()
        precondition(state.consent == nil && state.sessions.isEmpty && state.batch == nil)
        state.enable(owner: UUID(), origin: "https://example.supabase.co", at: now, studyVersion: "test-consent-v1")
        precondition(!state.enqueue(id: first, startedAt: now, endedAt: now, captured: consent))

        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let sessions = root.appendingPathComponent("Sessions")
        let folder = sessions.appendingPathComponent(first)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        for name in ResearchArchive.files { try Data("synthetic fixture".utf8).write(to: folder.appendingPathComponent(name)) }
        try Data("private name and photo".utf8).write(to: folder.appendingPathComponent("profile.json"))
        let records = [ResearchSession(id: first, consentID: consent.id, startedAt: now, endedAt: now)]
        let ids = try ResearchArchive.select(records, root: sessions)
        precondition(ids == [first])
        let destination = root.appendingPathComponent("week.zip")
        let zip = try ResearchArchive.prepare(ids: ids, root: sessions, destination: destination)
        precondition(!zip.isEmpty)
        let pipe = Pipe()
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/unzip")
        process.arguments = ["-Z1", destination.path]
        process.standardOutput = pipe
        try process.run()
        let listing = String(data: pipe.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8)!
        process.waitUntilExit()
        precondition(process.terminationStatus == 0)
        precondition(Set(listing.split(separator: "\n").map(String.init)) == Set(ResearchArchive.files.map { "\(first)/\($0)" }))
        precondition(!listing.contains("profile.json"))
        let linkID = UUID().uuidString
        try FileManager.default.createSymbolicLink(at: sessions.appendingPathComponent(linkID), withDestinationURL: folder)
        do { _ = try ResearchArchive.prepare(ids: [linkID], root: sessions, destination: destination); preconditionFailure("Symlink accepted") } catch { }
        let event = folder.appendingPathComponent("events.csv")
        try FileManager.default.removeItem(at: event)
        try FileManager.default.createSymbolicLink(at: event, withDestinationURL: folder.appendingPathComponent("profile.json"))
        do { _ = try ResearchArchive.prepare(ids: [first], root: sessions, destination: destination); preconditionFailure("Symlink file accepted") } catch { }
        precondition(FileManager.default.fileExists(atPath: folder.appendingPathComponent("profile.json").path))
        print("Research consent snapshots, cancellation, retry batches and ZIP allowlisting passed")
    }
}
