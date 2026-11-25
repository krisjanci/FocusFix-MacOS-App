import Foundation

@main struct SessionStorageTests {
    static func expect(_ value: @autoclosure () throws -> Bool) throws { let result = try value(); precondition(result) }
    static func fails(_ body: () throws -> Void) { do { try body(); preconditionFailure("Expected failure") } catch {} }
    static func main() throws {
        let fm = FileManager.default
        let root = fm.temporaryDirectory.appendingPathComponent("storage-tests-\(UUID())")
        try fm.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? fm.removeItem(at: root) }
        let start = Date(timeIntervalSince1970: 1_800_000_000.125)
        let assignment = WorkAssignment(projectID: UUID(), projectName: "Private project", taskID: UUID(), taskTitle: "Task")
        let writer = try RecordingWriter(root: root, id: UUID().uuidString, startedAt: start)
        try writer.selectAssignment(assignment, at: 0)
        for index in 0..<10000 {
            try writer.event(time: Double(index) / 100, type: "key_down", repeated: false)
        }
        writer.append((0..<100).map { MouseSummary(start: Double($0), end: Double($0 + 1), distance: 0, events: 0, secondsSinceMovement: nil) })
        try writer.checkpoint(at: 100)
        let activeCompact = try SessionStorage.compact(writer.folder)
        try expect(!activeCompact)
        try writer.finish(startedAt: start, duration: 100, reason: "test")
        var originals: [String: Data] = [:]
        for name in try SessionStorage.names(in: writer.folder) { originals[name] = try SessionStorage.data(name, in: writer.folder, limit: 512 * 1024 * 1024) }
        let saved = try SavedSession(folder: writer.folder), before = try RecordingCoverage.load(session: saved)
        let assignmentsBefore = try saved.assignmentHistory()
        enum Injected: Error { case failure }
        fails { _ = try SessionStorage.compact(writer.folder, beforeCommit: { throw Injected.failure }) }
        try expect(!SessionStorage.isArchived(writer.folder))
        for (name, bytes) in originals { try expect(tryData(name, writer.folder) == bytes) }
        let raw = originals.values.reduce(0) { $0 + $1.count }
        let compacted = try SessionStorage.compact(writer.folder)
        try expect(compacted && SessionStorage.isArchived(writer.folder))
        let contents = try fm.contentsOfDirectory(at: writer.folder, includingPropertiesForKeys: [.fileSizeKey])
        let size = try contents.reduce(0) { $0 + (try $1.resourceValues(forKeys: [.fileSizeKey]).fileSize ?? 0) }
        try expect(size < raw && contents.count == 2)
        print("PERF lossless fixture: \(raw) -> \(size) bytes, \(Int(100 * (1 - Double(size) / Double(raw))))% smaller")
        for (name, bytes) in originals {
            try expect(tryData(name, writer.folder) == bytes)
            try expect(!fm.fileExists(atPath: writer.folder.appendingPathComponent(name).path))
        }
        let reopened = try SavedSession(folder: writer.folder)
        try expect(reopened.startedAt == saved.startedAt && reopened.recordingContract == saved.recordingContract)
        let assignmentsAfter = try reopened.assignmentHistory()
        try expect(tryCoverage(reopened) == before && assignmentsAfter == assignmentsBefore)
        let taskTotal = try SavedSession.totalTaskWork(project: assignment.projectID!, task: assignment.taskID!, through: start.addingTimeInterval(100), root: root)
        try expect(taskTotal == 100)
        try SessionFiles.updateTags(["New tag"], for: reopened, root: root, active: nil)
        let tagged = try SavedSession(folder: writer.folder)
        try expect(tagged.tags == ["New tag"] && SessionStorage.isArchived(writer.folder))
        try expect(tryData("events.csv", writer.folder) == originals["events.csv"])
        try expect(tryCoverage(tagged) == before)
        // Interrupted cleanup: marker already committed, stale source bytes remain.
        try originals["events.csv"]!.write(to: writer.folder.appendingPathComponent("events.csv"))
        _ = try SessionStorage.compact(writer.folder)
        try expect(!fm.fileExists(atPath: writer.folder.appendingPathComponent("events.csv").path))
        // Existing upload format and file allowlist are unchanged by local compaction.
        let consent = DevelopmentConsent(id: UUID(), owner: UUID(), origin: "https://example.invalid", policyVersion: "test", startedAt: start)
        let zip = root.appendingPathComponent("development.zip")
        _ = try DevelopmentArchive.prepare(id: saved.id, root: root, consent: consent, destination: zip)
        let process = Process(), pipe = Pipe()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/unzip")
        process.arguments = ["-Z1", zip.path]; process.standardOutput = pipe
        try process.run(); let listing = String(decoding: pipe.fileHandleForReading.readDataToEndOfFile(), as: UTF8.self); process.waitUntilExit()
        try expect(Set(listing.split(separator: "\n").map { URL(fileURLWithPath: String($0)).lastPathComponent }) == Set(DevelopmentArchive.files + ["sharing_manifest.json"]))
        try expect(!listing.contains(WorkAssignmentJournal.filename) && !listing.contains(SessionStorage.marker))
        // Corruption cannot silently return changed activity.
        let manifest = try JSONDecoder().decode(SessionStorage.Manifest.self, from: Data(contentsOf: writer.folder.appendingPathComponent(SessionStorage.marker)))
        let archive = writer.folder.appendingPathComponent(manifest.archive)
        let archiveBytes = try Data(contentsOf: archive)
        try Data("broken ZIP".utf8).write(to: archive)
        fails { _ = try SessionStorage.data("events.csv", in: writer.folder) }
        try archiveBytes.write(to: archive)
        // A malformed manifest must fail closed rather than treat missing raw files as an empty session.
        let markerBytes = try Data(contentsOf: writer.folder.appendingPathComponent(SessionStorage.marker))
        try Data("{}".utf8).write(to: writer.folder.appendingPathComponent(SessionStorage.marker))
        fails { _ = try SavedSession(folder: writer.folder) }
        try markerBytes.write(to: writer.folder.appendingPathComponent(SessionStorage.marker))
        let old = try RecordingWriter(root: root, id: UUID().uuidString, startedAt: start)
        try old.finish(startedAt: start, duration: 0, reason: "test")
        try fm.removeItem(at: old.folder.appendingPathComponent(SessionStorage.pendingMarker))
        let oldNames = try fm.contentsOfDirectory(atPath: old.folder.path).sorted()
        SessionStorage.resumeCompaction(in: root)
        // No marker identifies existing sessions for automatic compaction.
        try expect(try fm.contentsOfDirectory(atPath: old.folder.path).sorted() == oldNames)
        let selected = try SessionFiles.deleteSelected([tagged], root: root, active: nil, remove: { try fm.removeItem(at: $0) })
        try expect(selected.deleted.count == 1 && !fm.fileExists(atPath: writer.folder.path))
        print("PASS: exact archive recovery, rollback, mixed storage, edits, task history, upload allowlist, corruption and deletion")
    }
    static func tryData(_ name: String, _ folder: URL) -> Data { try! SessionStorage.data(name, in: folder, limit: 512 * 1024 * 1024) }
    static func tryCoverage(_ saved: SavedSession) -> RecordingCoverage { try! RecordingCoverage.load(session: saved) }
}
