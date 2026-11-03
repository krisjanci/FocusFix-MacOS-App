import Foundation
import CoreGraphics

@main struct AutomaticTrackingIntegrationTests {
    static func main() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let exports = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root); try? FileManager.default.removeItem(at: exports) }
        try FileManager.default.createDirectory(at: exports, withIntermediateDirectories: true)
        let date = Date(timeIntervalSince1970: 100)
        var lifecycle = RecordingLifecycle()
        lifecycle.recordingAllowed = true; lifecycle.automaticEnabled = true
        precondition(lifecycle.reconcile(recording: false, mode: .automatic, idle: 0) == .none)
        lifecycle.permissionAvailable = true
        precondition(lifecycle.reconcile(recording: false, mode: .automatic, idle: 0) == .start)
        let writer = try RecordingWriter(root: SessionFiles.pendingRoot(in: root), id: UUID().uuidString, startedAt: date, mode: .automatic)
        try writer.changeContext(.work, at: 5, effectiveAt: date.addingTimeInterval(5), source: .userAction)
        var policy = BreakPolicy()
        let begin = policy.begin(at: 20, seconds: 60, activity: "Synthetic break")!
        try writer.logBreak(begin)
        let end = policy.finish(at: 80, reason: "explicit_return")!
        try writer.logBreak(end)
        for second in 0..<100 where !(20..<80).contains(second) {
            writer.append([MouseSummary(start: Double(second), end: Double(second + 1), distance: 0, events: 0, secondsSinceMovement: nil)])
        }
        try writer.checkpoint(at: 100)
        let previousWork = writer.contract.intervals.last!
        var reminder = ReminderEligibility()
        let request = reminder.schedule(token: "synthetic-prompt", recordingID: writer.contract.recordingID,
            interval: previousWork, elapsed: 100, monotonic: 1500, date: date, screenUseEnabled: false)!
        try writer.finish(startedAt: date, duration: 100, reason: "local_day_rotation")
        let savedURL = try SessionFiles.retainRecording(writer.folder, duration: 100, root: root)!
        let saved = try SavedSession(folder: savedURL)
        let coverage = try RecordingCoverage.load(session: saved)
        precondition(coverage.unknown == 5 && coverage.work == 35 && coverage.explicitBreak == 60 && coverage.unavailable == 0)
        var progress = DailyProgress()
        let allocation = DailyProgress.declaredAllocation(slices: coverage.workSlices, startedAt: saved.startedAt, origin: 0, calendar: DailyProgress.calendar(timeZone: TimeZone(secondsFromGMT: 0)!))
        try progress.replaceDeclaredWork(segmentID: saved.recordingContract!.segmentID.uuidString, days: allocation)
        let continued = RecordingContract(recordingID: writer.contract.recordingID, mode: .automatic, startedAt: date.addingTimeInterval(100), elapsedOrigin: 100, continuing: previousWork)
        precondition(reminder.accepts(token: request.id, recordingID: continued.recordingID, contextID: continued.intervals[0].logicalID, active: true))
        precondition(reminder.cooldownUntil == 3000)
        precondition(!ResearchArchiveContract.eligibleForDelivery(folder: savedURL, current: nil, dailyUsedSeconds: 0))
        let rawURL = savedURL.appendingPathComponent("mouse_movement.csv")
        let raw = try Data(contentsOf: rawURL)
        try SessionFiles.correctContext(.nonWork, start: 5, end: 10, for: saved, root: root, active: nil, expectedRevision: 0)
        let corrected = try SavedSession(folder: savedURL)
        let correctedCoverage = try RecordingCoverage.load(session: corrected)
        precondition(correctedCoverage.work == 30 && correctedCoverage.nonWork == 5)
        let unchanged = try Data(contentsOf: rawURL); precondition(unchanged == raw)
        let copy = try SessionFiles.export(corrected, to: exports, root: root, active: nil)
        let copied = try Data(contentsOf: copy.appendingPathComponent("mouse_movement.csv")); precondition(copied == raw)
        lifecycle.userPaused = true
        precondition(lifecycle.reconcile(recording: true, mode: .automatic, idle: 0) == .stop("user_pause"))
        precondition(lifecycle.reconcile(recording: false, mode: .automatic, idle: 0) == .none)
        let resumed = RecordingContract(mode: .automatic, startedAt: date.addingTimeInterval(200))
        precondition(resumed.currentContext == .unknown && resumed.recordingID != continued.recordingID)
        // Corrupt new metadata cannot silently turn into compatible legacy data or hide good history.
        let bad = root.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: bad, withIntermediateDirectories: true)
        try Data("corrupt".utf8).write(to: bad.appendingPathComponent("session.json"))
        try Data("{}".utf8).write(to: bad.appendingPathComponent("context_intervals.json"))
        do { _ = try SavedSession(folder: bad); preconditionFailure("Malformed new schema accepted as legacy") } catch { }
        let listing = try SessionFiles.inspect(in: root)
        precondition(listing.sessions.count == 1 && listing.unreadable == 1)
        do { _ = try SessionFiles.exportAll(to: exports, root: root, active: nil); preconditionFailure("Partial Export All accepted") } catch { }
        print("PASS: generated consent/permission lifecycle, mixed context, break/coverage scoring, rotation IDs/cooldown, edits, byte-preserving export, pause/resume, research rejection and quarantined malformed history")
    }
}
