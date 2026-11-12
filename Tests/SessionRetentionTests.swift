import Foundation

// Real recording files and a persisted daily ledger, with synthetic time and no input monitoring.
@main
struct SessionRetentionTests {
    static func main() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("retention-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: root) }
        let sessions = root.appendingPathComponent("Sessions")
        let store = ProgressStore(url: root.appendingPathComponent("progress.json"))
        let start = Date(timeIntervalSince1970: 1_790_000_000)
        let calendar = DailyProgress.calendar(timeZone: TimeZone(secondsFromGMT: 0)!)
        var progress = DailyProgress()
        var total: Double = 0
        var savedCount = 0
        for (index, duration) in [0.0, 60, 899.999, 900, 1200, 540.001].enumerated() {
            var writer: RecordingWriter? = try RecordingWriter(root: SessionFiles.pendingRoot(in: sessions),
                id: "session-\(index)", startedAt: start)
            let folder = writer!.folder
            let before = try SessionFiles.list(in: sessions)
            precondition(before.count == savedCount)
            var clock = ProgressClock()
            clock.update(&progress, elapsed: 0, date: start, working: true, calendar: calendar)
            clock.update(&progress, elapsed: duration, date: start.addingTimeInterval(duration),
                         working: true, calendar: calendar)
            clock.update(&progress, elapsed: duration, date: start.addingTimeInterval(duration),
                         working: false, calendar: calendar)
            try writer!.finish(startedAt: start, duration: duration, reason: "user_stop")
            writer = nil
            let retained = try SessionFiles.retainRecording(folder, duration: duration, root: sessions)
            if duration >= 0 {
                savedCount += 1
                precondition(retained != nil)
                let saved = try SavedSession(folder: retained!)
                precondition(saved.duration == duration)
                precondition(FileManager.default.fileExists(atPath: retained!.appendingPathComponent("events.csv").path))
            } else {
                precondition(retained == nil)
            }
            precondition(!FileManager.default.fileExists(atPath: folder.path))
            total += duration
            clock.update(&progress, elapsed: duration, date: start.addingTimeInterval(duration),
                         working: false, calendar: calendar)
            try store.save(progress)
            progress = try store.load()
            precondition(abs(progress.day(at: start, calendar: calendar).workSeconds - total) < 0.00001)
            let history = try SessionFiles.list(in: sessions)
            precondition(history.count == savedCount)
        }
        precondition(abs(total - DailyProgress.goalSeconds) < 0.00001)
        precondition(progress.day(at: start, calendar: calendar).workSeconds >= DailyProgress.goalSeconds)
        for invalid in [-1.0, Double.nan, Double.infinity] {
            precondition(!SessionFiles.qualifies(duration: invalid))
        }
        let exported = try SessionFiles.exportAll(to: root, root: sessions, active: nil)
        precondition(exported.count == 6)
        // Reopening the library reads the same six recordings from disk.
        let reopened = try SessionFiles.list(in: sessions)
        precondition(reopened.count == 6)
        let grouped = SessionDay.groups(reopened, calendar: calendar)
        precondition(grouped.count == 1 && grouped[0].sessions.count == 6)
        let dayFolders = try FileManager.default.contentsOfDirectory(at: exported.folder, includingPropertiesForKeys: nil)
        precondition(dayFolders.count == 1 && dayFolders[0].lastPathComponent.hasPrefix("FocusFix Day ["))
        let dayContents = try FileManager.default.contentsOfDirectory(at: dayFolders[0], includingPropertiesForKeys: nil)
        precondition(dayContents.count == 6)
        // An automatic/unknown recording on another day stays a single entry.
        let nextDay = start.addingTimeInterval(24 * 3600)
        var automatic: RecordingWriter? = try RecordingWriter(root: SessionFiles.pendingRoot(in: sessions),
            id: "next-day-automatic", startedAt: nextDay, mode: .automatic)
        let automaticFolder = automatic!.folder
        try automatic!.finish(startedAt: nextDay, duration: 60, reason: "user_stop")
        automatic = nil
        _ = try SessionFiles.retainRecording(automaticFolder, duration: 60, root: sessions)
        let mixed = try SessionFiles.list(in: sessions)
        let mixedGroups = SessionDay.groups(mixed, calendar: calendar)
        precondition(mixedGroups.count == 2 && mixedGroups[0].sessions.count == 1 && mixedGroups[1].sessions.count == 6)
        let mixedExport = try SessionFiles.exportAll(to: root, root: sessions, active: nil)
        let mixedContents = try FileManager.default.contentsOfDirectory(at: mixedExport.folder, includingPropertiesForKeys: nil)
        precondition(mixedExport.count == 7 && mixedContents.count == 2)
        precondition(mixedContents.contains { $0.lastPathComponent.hasPrefix("FocusFix Session [") })
        precondition(mixedContents.contains { $0.lastPathComponent.hasPrefix("FocusFix Day [") })
        let originalCount = try SessionFiles.list(in: sessions).count
        precondition(originalCount == 7) // Export grouping never moves or rewrites originals.
        // Calendar-day grouping uses local start dates even over a DST transition.
        let local = DailyProgress.calendar(timeZone: TimeZone(identifier: "America/New_York")!)
        precondition(SessionDay.groups(mixed, calendar: local).reduce(0) { $0 + $1.sessions.count } == 7)
        print("Session retention, day folders, mixed manual/automatic exports and original-file preservation passed")
    }
}
