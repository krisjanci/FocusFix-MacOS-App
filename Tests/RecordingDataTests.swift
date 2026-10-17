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
        precondition(events.split(separator: "\n").allSatisfy { $0.split(separator: ",", omittingEmptySubsequences: false).count == 7 })
        precondition(!events.contains("keyCode") && !events.contains("characters"))
        let summaries = try String(contentsOf: writer.folder.appendingPathComponent("mouse_movement.csv"), encoding: .utf8)
        precondition(summaries.split(separator: "\n").count == 3)
        let info = try JSONSerialization.jsonObject(with: Data(contentsOf: writer.folder.appendingPathComponent("session.json"))) as! [String: Any]
        precondition(info["status"] as? String == "user_stop")
        near(info["duration_seconds"] as! Double, 1.4)
        do {
            _ = try RecordingWriter(root: root, id: "synthetic-session", startedAt: Date())
            preconditionFailure("Existing session must never be overwritten")
        } catch { /* Expected. */ }
        print("PASS: path distance, boundaries, idle intervals, partial stop, key timing, CSV schema, metadata, overwrite protection.")
    }
}
