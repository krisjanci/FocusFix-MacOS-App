import Foundation
import CoreGraphics

// Stable CSV numbers, regardless of the Mac's language.
func csvNumber(_ value: Double) -> String {
    String(format: "%.6f", locale: Locale(identifier: "en_US_POSIX"), value)
}

struct MouseSummary {
    let start: Double
    let end: Double
    let distance: Double
    let events: Int
    let secondsSinceMovement: Double?
    var csv: String {
        [csvNumber(start), csvNumber(end),
         csvNumber(distance), String(events), secondsSinceMovement.map(csvNumber) ?? ""]
            .joined(separator: ",") + "\n"
    }
}

// Positions live only in memory. Add every observed segment so a circular
// movement is not mistaken for no movement. Keep the previous point across bins.
struct MouseAccumulator {
    private var previous: CGPoint
    private var start: Double = 0
    private var distance: Double = 0
    private var events = 0
    private var lastMovement: Double?
    init(initialPosition: CGPoint) { previous = initialPosition }

    mutating func advance(to time: Double) -> [MouseSummary] {
        var rows: [MouseSummary] = []
        while start + 1 <= time { rows.append(finish(at: start + 1)) }
        return rows
    }
    mutating func move(to position: CGPoint, at time: Double) -> [MouseSummary] {
        let rows = advance(to: time)
        let segment = hypot(position.x - previous.x, position.y - previous.y)
        distance += segment
        events += 1
        if segment > 0 { lastMovement = time }
        previous = position
        return rows
    }
    mutating func stop(at time: Double) -> [MouseSummary] {
        var rows = advance(to: time)
        if time > start { rows.append(finish(at: time)) }
        return rows
    }
    private mutating func finish(at end: Double) -> MouseSummary {
        let row = MouseSummary(start: start, end: end, distance: distance, events: events,
            secondsSinceMovement: lastMovement.map { max(0, end - $0) })
        start = end
        distance = 0
        events = 0
        return row
    }
}

// Match down/up in memory; key codes and letters are never written to disk.
struct KeyTiming {
    private var pressed: [UInt16: Double] = [:]
    mutating func down(code: UInt16, at time: Double, repeated: Bool) {
        if !repeated { pressed[code] = time }
    }
    mutating func up(code: UInt16, at time: Double) -> Double? {
        pressed.removeValue(forKey: code).map { max(0, time - $0) }
    }
}

// Unique sessions prevent overwrites. Buffer small writes, flush once a second
// and on Stop; never keep the entire session in memory.
final class RecordingWriter {
    let folder: URL
    private let events: FileHandle
    private let mouse: FileHandle
    private var eventBuffer = ""
    private var mouseBuffer = ""
    init(root: URL, id: String, startedAt: Date) throws {
        folder = root.appendingPathComponent(id, isDirectory: true)
        guard !FileManager.default.fileExists(atPath: folder.path) else {
            throw CocoaError(.fileWriteFileExists)
        }
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true,
            attributes: [.posixPermissions: 0o700])
        let eventURL = folder.appendingPathComponent("events.csv")
        let mouseURL = folder.appendingPathComponent("mouse_movement.csv")
        try Data("elapsed_seconds,event_type,is_repeat,key_hold_seconds,scroll_delta_x,scroll_delta_y,scroll_precise\n".utf8).write(to: eventURL)
        try Data("start_seconds,end_seconds,distance_screen_points,movement_events,seconds_since_last_movement\n".utf8).write(to: mouseURL)
        events = try FileHandle(forWritingTo: eventURL)
        mouse = try FileHandle(forWritingTo: mouseURL)
        try events.seekToEnd()
        try mouse.seekToEnd()
        try metadata(startedAt: startedAt, duration: nil, reason: "recording")
    }
    func event(time: Double, type: String, repeated: Bool? = nil, hold: Double? = nil,
               scrollX: Double? = nil, scrollY: Double? = nil, precise: Bool? = nil) throws {
        eventBuffer += [csvNumber(time), type, repeated.map { $0 ? "1" : "0" } ?? "",
            hold.map(csvNumber) ?? "", scrollX.map(csvNumber) ?? "", scrollY.map(csvNumber) ?? "",
            precise.map { $0 ? "1" : "0" } ?? ""].joined(separator: ",") + "\n"
        if eventBuffer.utf8.count >= 64_000 { try flush() }
    }
    func append(_ summaries: [MouseSummary]) { mouseBuffer += summaries.map(\.csv).joined() }
    func flush() throws {
        if !eventBuffer.isEmpty {
            try events.write(contentsOf: Data(eventBuffer.utf8))
            eventBuffer = ""
        }
        if !mouseBuffer.isEmpty {
            try mouse.write(contentsOf: Data(mouseBuffer.utf8))
            mouseBuffer = ""
        }
    }
    func finish(startedAt: Date, duration: Double, reason: String) throws {
        try flush()
        try events.synchronize()
        try mouse.synchronize()
        try metadata(startedAt: startedAt, duration: duration, reason: reason)
    }
    private func metadata(startedAt: Date, duration: Double?, reason: String) throws {
        var fields: [String: Any] = [
            "schema_version": 2, "session_id": folder.lastPathComponent,
            "started_at_utc": ISO8601DateFormatter().string(from: startedAt), "status": reason,
            "timestamp_basis": "monotonic callback receipt time, relative to session start",
            "mouse_interval_seconds": 1,
            "mouse_distance_units": "screen-coordinate points; not physical distance",
            "keyboard_scope": "key down/up and generic modifier changes; no key identities saved",
            "limitations": "Secure Input can suppress keyboard events. macOS may coalesce movement events. Silence is not proof of a break."
        ]
        if let duration {
            fields["duration_seconds"] = duration
            fields["ended_at_utc"] = ISO8601DateFormatter().string(from: startedAt.addingTimeInterval(duration))
        }
        let data = try JSONSerialization.data(withJSONObject: fields, options: [.prettyPrinted, .sortedKeys])
        try data.write(to: folder.appendingPathComponent("session.json"), options: .atomic)
    }
    deinit { try? events.close(); try? mouse.close() }
}
