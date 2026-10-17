import Foundation
import CoreGraphics

// No real keyboard/mouse monitoring: all inputs are synthetic.
@main
struct RecordingDataTests {
    static func near(_ actual: Double, _ expected: Double) {
        precondition(abs(actual - expected) < 0.00001, "\(actual) != \(expected)")
    }
    static func main() throws {
        var mouse = MouseAccumulator(initialPosition: .zero)
        precondition(mouse.move(to: CGPoint(x: 3, y: 4), at: 0.2).isEmpty)
        precondition(mouse.move(to: .zero, at: 0.6).isEmpty)
        let first = mouse.advance(to: 1)
        precondition(first.count == 1 && first[0].events == 2)
        near(first[0].distance, 10) // Returning to origin must not erase the path.
        near(first[0].secondsSinceMovement!, 0.4)
        _ = mouse.move(to: CGPoint(x: 3, y: 4), at: 1.2)
        let tail = mouse.stop(at: 1.4)
        precondition(tail.count == 1 && tail[0].events == 1)
        near(tail[0].distance, 5) // Previous position survives interval boundary.
        near(tail[0].end - tail[0].start, 0.4)
        near(tail[0].secondsSinceMovement!, 0.2)

        var idle = MouseAccumulator(initialPosition: .zero)
        let empty = idle.advance(to: 3.3)
        precondition(empty.count == 3)
        precondition(empty.allSatisfy { $0.events == 0 && $0.distance == 0 && $0.secondsSinceMovement == nil })
        near(idle.stop(at: 3.3)[0].end, 3.3)
        var boundary = MouseAccumulator(initialPosition: .zero)
        let previous = boundary.move(to: CGPoint(x: 1, y: 0), at: 1)
        precondition(previous.count == 1 && previous[0].events == 0)
        let next = boundary.stop(at: 2)
        precondition(next.count == 1 && next[0].events == 1)
        var short = MouseAccumulator(initialPosition: .zero)
        near(short.stop(at: 0.05)[0].end, 0.05)

        var keys = KeyTiming()
        keys.down(code: 12, at: 0.1, repeated: false)
        keys.down(code: 13, at: 0.2, repeated: false)
        keys.down(code: 12, at: 0.4, repeated: true)
        near(keys.up(code: 12, at: 0.6)!, 0.5)
        near(keys.up(code: 13, at: 0.7)!, 0.5)
        precondition(keys.up(code: 99, at: 1) == nil)

        let root = FileManager.default.temporaryDirectory.appendingPathComponent("focusfix-tests-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: root) }
        let writer = try RecordingWriter(root: root, id: "synthetic-session", startedAt: Date(timeIntervalSince1970: 0))
        try writer.event(time: 0.1, type: "key_down", repeated: false)
        try writer.event(time: 0.6, type: "key_up", hold: 0.5)
        try writer.event(time: 0.7, type: "scroll", scrollX: -1, scrollY: 2, precise: true)
        writer.append(first + tail)
        try writer.finish(startedAt: Date(timeIntervalSince1970: 0), duration: 1.4, reason: "user_stop")
        let events = try String(contentsOf: writer.folder.appendingPathComponent("events.csv"), encoding: .utf8)
        precondition(events.split(separator: "\n").count == 4)
        precondition(events.split(separator: "\n").allSatisfy { $0.split(separator: ",", omittingEmptySubsequences: false).count == 9 })
        precondition(!events.contains("keyCode") && !events.contains("characters"))
        let summaries = try String(contentsOf: writer.folder.appendingPathComponent("mouse_movement.csv"), encoding: .utf8)
        precondition(summaries.split(separator: "\n").count == 3)
        precondition(summaries.split(separator: "\n").allSatisfy { $0.split(separator: ",", omittingEmptySubsequences: false).count == 7 })
        precondition(!summaries.contains("duration_seconds"))
        precondition(events.contains("0.700000,scroll,,,-1.000000,2.000000,1"))
        let info = try JSONSerialization.jsonObject(with: Data(contentsOf: writer.folder.appendingPathComponent("session.json"))) as! [String: Any]
        precondition(info["status"] as? String == "user_stop")
        precondition(info["schema_version"] as? Int == 3)
        near(info["duration_seconds"] as! Double, 1.4)
        precondition(info["ended_at_utc"] as? String == "1970-01-01T00:00:01Z")
        do {
            _ = try RecordingWriter(root: root, id: "synthetic-session", startedAt: Date())
            preconditionFailure("Existing session must never be overwritten")
        } catch { /* Expected. */ }

        // Saved sessions survive reopening; exports are named and never replace earlier copies.
        let saved = try SavedSession(folder: writer.folder)
        precondition(saved.exportName(timeZone: TimeZone(secondsFromGMT: 0)!) ==
            "FocusFix Session [1970-01-01 00-00-00-1970-01-01 00-00-01]")
        let initialSessions = try SessionFiles.list(in: root)
        precondition(initialSessions.count == 1)
        let exports = root.deletingLastPathComponent().appendingPathComponent("focusfix-exports-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: exports, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: exports) }
        let copy = try SessionFiles.export(saved, to: exports, root: root, active: nil)
        let secondCopy = try SessionFiles.export(saved, to: exports, root: root, active: nil)
        precondition(copy != secondCopy && secondCopy.lastPathComponent.hasSuffix(" (2)"))
        let exported = try String(contentsOf: copy.appendingPathComponent("events.csv"), encoding: .utf8)
        precondition(exported == events)
        let breakCSV = try String(contentsOf: copy.appendingPathComponent("breaks.csv"), encoding: .utf8)
        precondition(breakCSV == BreakLogEntry.header)
        do {
            try SessionFiles.validate(saved.folder, in: root, active: saved.folder)
            preconditionFailure("Active sessions must be protected")
        } catch { /* Expected. */ }
        do {
            try SessionFiles.validate(root, in: root, active: nil)
            preconditionFailure("The storage root must be protected")
        } catch { /* Expected. */ }
        do {
            _ = try SessionFiles.export(saved, to: saved.folder, root: root, active: nil)
            preconditionFailure("Cannot export into session storage")
        } catch { /* Expected. */ }

        let oldFolder = root.appendingPathComponent("legacy")
        try FileManager.default.createDirectory(at: oldFolder, withIntermediateDirectories: true)
        let legacy: [String: Any] = ["started_at_utc": "2026-10-17T23:59:30Z", "duration_seconds": 90,
                                   "status": "user_stop", "schema_version": 1]
        try JSONSerialization.data(withJSONObject: legacy).write(to: oldFolder.appendingPathComponent("session.json"))
        let old = try SavedSession(folder: oldFolder)
        precondition(old.exportName(timeZone: TimeZone(secondsFromGMT: 0)!) ==
            "FocusFix Session [2026-10-17 23-59-30-2026-10-18 00-01-00]")
        let unfinishedFolder = root.appendingPathComponent("unfinished")
        try FileManager.default.createDirectory(at: unfinishedFolder, withIntermediateDirectories: true)
        let unfinished = try SavedSession(folder: unfinishedFolder)
        precondition(unfinished.endedAt == nil && unfinished.exportName().hasSuffix("-unfinished]"))
        let link = root.appendingPathComponent("link")
        try FileManager.default.createSymbolicLink(at: link, withDestinationURL: exports)
        do {
            try SessionFiles.validate(link, in: root, active: nil)
            preconditionFailure("Symlinks must not be treated as sessions")
        } catch { /* Expected. */ }
        let all = try SessionFiles.list(in: root)
        precondition(all.count == 3 && !all.contains { $0.folder == link })
        print("PASS: recording schema and timing, session reload, dated exports, duplicate protection, legacy and unfinished sessions, active-session and path guards.")
    }
}
