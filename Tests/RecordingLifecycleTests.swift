import Foundation

@main struct RecordingLifecycleTests {
    static func main() throws {
        precondition(RecordingLifecycle.observedEnd(now: 10000, lastSamplingTick: 10, lastObserved: 11) == 11)
        precondition(RecordingLifecycle.observedEnd(now: 11, lastSamplingTick: 10, lastObserved: 10) == 11)
        precondition(SystemIdleTime.anyInputEventType.rawValue == UInt32.max)
        precondition(SystemIdleTime.anyInputEventType != .null)
        var invalidIdle = RecordingLifecycle()
        precondition(invalidIdle.reconcile(recording: true, mode: .automatic, idle: .nan) == .stop("idle_status_unavailable"))
        var lifecycle = RecordingLifecycle()
        precondition(lifecycle.reconcile(recording: false, mode: .automatic, idle: 0) == .none)
        lifecycle.recordingAllowed = true; lifecycle.automaticEnabled = true
        precondition(lifecycle.reconcile(recording: false, mode: .automatic, idle: 0) == .none)
        precondition(lifecycle.state == .permissionUnavailable)
        lifecycle.permissionAvailable = true
        precondition(lifecycle.reconcile(recording: false, mode: .automatic, idle: 0) == .start)
        precondition(lifecycle.reconcile(recording: true, mode: .automatic, idle: 299) == .none)
        precondition(lifecycle.reconcile(recording: true, mode: .automatic, idle: 300) == .stop("idle_cutoff"))
        precondition(lifecycle.reconcile(recording: false, mode: .automatic, idle: 301) == .none)
        precondition(lifecycle.state == .idlePaused)
        precondition(lifecycle.reconcile(recording: false, mode: .automatic, idle: 1) == .start)
        lifecycle.userPaused = true
        precondition(lifecycle.reconcile(recording: true, mode: .automatic, idle: 0) == .stop("user_pause"))
        lifecycle.permissionAvailable = false
        _ = lifecycle.reconcile(recording: false, mode: .automatic, idle: 0)
        lifecycle.permissionAvailable = true
        precondition(lifecycle.reconcile(recording: false, mode: .automatic, idle: 0) == .none)
        precondition(lifecycle.state == .userPaused)
        lifecycle.userPaused = false
        lifecycle.blockers = ["sleep", "lock"]
        precondition(lifecycle.reconcile(recording: true, mode: .automatic, idle: 0) == .stop("lifecycle_lock_sleep"))
        lifecycle.blockers.remove("sleep")
        precondition(lifecycle.reconcile(recording: false, mode: .automatic, idle: 0) == .none)
        lifecycle.blockers.remove("lock")
        precondition(lifecycle.reconcile(recording: false, mode: .automatic, idle: 0) == .start)
        lifecycle.failed = true
        precondition(lifecycle.reconcile(recording: false, mode: .automatic, idle: 0) == .none)
        lifecycle.failed = false; lifecycle.automaticEnabled = false
        precondition(lifecycle.reconcile(recording: true, mode: .manual, idle: 0) == .none)
        precondition(lifecycle.reconcile(recording: true, mode: .automatic, idle: 0) == .stop("automatic_disabled"))
        lifecycle.quitting = true
        precondition(lifecycle.reconcile(recording: true, mode: .manual, idle: 0) == .stop("app_quit"))
        precondition(lifecycle.reconcile(recording: false, mode: .automatic, idle: 0) == .none)
        let midnight = ISO8601DateFormatter().date(from: "2026-11-03T00:00:00Z")!
        precondition(RecordingDay.key(at: midnight.addingTimeInterval(-1), timeZone: TimeZone(secondsFromGMT: 0)!) != RecordingDay.key(at: midnight, timeZone: TimeZone(secondsFromGMT: 0)!))
        precondition(RecordingDay.key(at: midnight, timeZone: TimeZone(secondsFromGMT: 0)!) != RecordingDay.key(at: midnight, timeZone: TimeZone(secondsFromGMT: -18000)!))
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let pending = SessionFiles.pendingRoot(in: root)
        let first = try RecordingWriter(root: pending, id: UUID().uuidString, startedAt: midnight, mode: .automatic)
        try first.event(time: 1, type: "left_click_down")
        try first.checkpoint(at: 2)
        // A written but uncheckpointed tail is explicitly outside recovery eligibility.
        try first.event(time: 3, type: "left_click_up"); try first.flush()
        let recovered = try SessionFiles.recoverPending(in: root)
        precondition(recovered == 1)
        let saved = try SessionFiles.list(in: root)
        precondition(saved.count == 1 && saved[0].duration == 2)
        precondition(saved[0].recordingContract?.observedThrough == 2)
        let count = try SessionFiles.recoverPending(in: root)
        precondition(count == 0)
        let context = saved[0].recordingContract!.intervals[0]
        let continued = RecordingContract(recordingID: first.contract.recordingID, mode: .automatic,
            startedAt: midnight.addingTimeInterval(2), elapsedOrigin: 2, continuing: context)
        let second = try RecordingWriter(root: pending, id: UUID().uuidString, startedAt: midnight.addingTimeInterval(2), mode: .automatic, continuingContract: continued)
        try second.finish(startedAt: midnight.addingTimeInterval(2), duration: 4, reason: "user_pause")
        let retained = try SessionFiles.retainRecording(second.folder, duration: 2, root: root)!
        let rotated = try SavedSession(folder: retained)
        precondition(rotated.duration == 2)
        precondition(rotated.recordingContract!.recordingID == first.contract.recordingID)
        precondition(rotated.recordingContract!.segmentID != first.contract.segmentID)
        precondition(rotated.recordingContract!.intervals[0].logicalID == context.logicalID)
        precondition(rotated.recordingContract!.intervals[0].start == 2)
        // A crash after finalizing the contract but before metadata replacement is recoverable.
        let halfFinishedRoot = root.appendingPathComponent("half-finished")
        let halfFinished = try RecordingWriter(root: SessionFiles.pendingRoot(in: halfFinishedRoot), id: "half-finished", startedAt: midnight)
        try halfFinished.checkpoint(at: 2)
        var finalContract = halfFinished.contract
        try finalContract.finish(at: 2); try finalContract.save(to: halfFinished.folder)
        let finalizedCount = try SessionFiles.recoverPending(in: halfFinishedRoot)
        precondition(finalizedCount == 1)
        let finalizedSessions = try SessionFiles.list(in: halfFinishedRoot)
        precondition(finalizedSessions.first?.duration == 2)
        // A damaged pending entry must not stop independent checkpoint recovery.
        for reverse in [false, true] {
            let mixed = root.appendingPathComponent("mixed-\(reverse)")
            let names = reverse ? ["z-valid", "a-missing", "b-malformed", "c-invalid"] : ["a-valid", "z-missing", "y-malformed", "x-invalid"]
            let mixedPending = SessionFiles.pendingRoot(in: mixed)
            var original: [URL: Data] = [:]
            for (index, name) in names.enumerated() {
                let fixture = try RecordingWriter(root: mixedPending, id: name, startedAt: midnight)
                try fixture.checkpoint(at: 2)
                let metadata = fixture.folder.appendingPathComponent("session.json")
                if index == 1 { try FileManager.default.removeItem(at: metadata) }
                if index == 2 { try Data("{broken".utf8).write(to: metadata) }
                if index == 3 { try Data("invalid contract".utf8).write(to: fixture.folder.appendingPathComponent("context_intervals.json")) }
                if index > 0 {
                    for file in try FileManager.default.contentsOfDirectory(at: fixture.folder, includingPropertiesForKeys: nil) {
                        original[file] = try Data(contentsOf: file)
                    }
                }
            }
            do { _ = try SessionFiles.recoverPending(in: mixed); preconditionFailure("Partial recovery must report damaged entries") }
            catch { }
            let recovered = try SessionFiles.list(in: mixed)
            precondition(recovered.count == 1 && recovered[0].duration == 2, "Damaged entry blocked valid recovery")
            for (file, bytes) in original { let actual = try Data(contentsOf: file); precondition(actual == bytes) }
        }
        print("PASS: deterministic lifecycle, idle/resume, permission/pause/lock/quit/failure, midnight/timezone boundaries, durable-only recovery, short-auto retention and rotation IDs")
    }
}
