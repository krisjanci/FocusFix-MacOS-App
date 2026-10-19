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
    var activityPhase = "work"
    var secondsSinceLastBreak: Double? = nil
    var csv: String {
        [csvNumber(start), csvNumber(end),
         csvNumber(distance), String(events), secondsSinceMovement.map(csvNumber) ?? "", activityPhase,
         secondsSinceLastBreak.map(csvNumber) ?? ""]
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
    private let activityPhase: String
    private let workReference: Double?
    init(initialPosition: CGPoint, start: Double = 0, activityPhase: String = "work", workReference: Double? = 0) {
        previous = initialPosition
        self.start = start
        self.activityPhase = activityPhase
        self.workReference = workReference
    }

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
            secondsSinceMovement: lastMovement.map { max(0, end - $0) }, activityPhase: activityPhase,
            secondsSinceLastBreak: workReference.map { max(0, end - $0) })
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
    private let breaks: FileHandle
    private let surveys: FileHandle
    private let surveyPrompts: FileHandle
    private var eventBuffer = ""
    private var mouseBuffer = ""
    private var breakBuffer = ""
    init(root: URL, id: String, startedAt: Date) throws {
        folder = root.appendingPathComponent(id, isDirectory: true)
        guard !FileManager.default.fileExists(atPath: folder.path) else {
            throw CocoaError(.fileWriteFileExists)
        }
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true,
            attributes: [.posixPermissions: 0o700])
        let eventURL = folder.appendingPathComponent("events.csv")
        let mouseURL = folder.appendingPathComponent("mouse_movement.csv")
        let breakURL = folder.appendingPathComponent("breaks.csv")
        let surveyURL = folder.appendingPathComponent("surveys.csv")
        let promptURL = folder.appendingPathComponent("survey_prompts.csv")
        try Data("elapsed_seconds,event_type,is_repeat,key_hold_seconds,scroll_delta_x,scroll_delta_y,scroll_precise,activity_phase,seconds_since_last_break\n".utf8).write(to: eventURL)
        try Data("start_seconds,end_seconds,distance_screen_points,movement_events,seconds_since_last_movement,activity_phase,seconds_since_last_break\n".utf8).write(to: mouseURL)
        try Data(BreakLogEntry.header.utf8).write(to: breakURL)
        try Data(SurveyEntry.header.utf8).write(to: surveyURL)
        try Data(SurveyPromptEntry.header.utf8).write(to: promptURL)
        events = try FileHandle(forWritingTo: eventURL)
        mouse = try FileHandle(forWritingTo: mouseURL)
        breaks = try FileHandle(forWritingTo: breakURL)
        surveys = try FileHandle(forWritingTo: surveyURL)
        surveyPrompts = try FileHandle(forWritingTo: promptURL)
        try events.seekToEnd()
        try mouse.seekToEnd()
        try breaks.seekToEnd()
        try surveys.seekToEnd()
        try surveyPrompts.seekToEnd()
        try metadata(startedAt: startedAt, duration: nil, reason: "recording")
    }
    func event(time: Double, type: String, repeated: Bool? = nil, hold: Double? = nil,
               scrollX: Double? = nil, scrollY: Double? = nil, precise: Bool? = nil,
               activityPhase: String = "work", secondsSinceLastBreak: Double? = nil) throws {
        eventBuffer += [csvNumber(time), type, repeated.map { $0 ? "1" : "0" } ?? "",
            hold.map(csvNumber) ?? "", scrollX.map(csvNumber) ?? "", scrollY.map(csvNumber) ?? "",
            precise.map { $0 ? "1" : "0" } ?? "", activityPhase,
            secondsSinceLastBreak.map(csvNumber) ?? ""].joined(separator: ",") + "\n"
        if eventBuffer.utf8.count >= 64_000 { try flush() }
    }
    func append(_ summaries: [MouseSummary]) { mouseBuffer += summaries.map(\.csv).joined() }
    func logBreak(_ entry: BreakLogEntry) throws {
        breakBuffer += entry.csv
        // Lifecycle decisions are persisted immediately, not just on session Stop.
        try flush()
        try breaks.synchronize()
    }
    func flush() throws {
        if !eventBuffer.isEmpty {
            try events.write(contentsOf: Data(eventBuffer.utf8))
            eventBuffer = ""
        }
        if !mouseBuffer.isEmpty {
            try mouse.write(contentsOf: Data(mouseBuffer.utf8))
            mouseBuffer = ""
        }
        if !breakBuffer.isEmpty {
            try breaks.write(contentsOf: Data(breakBuffer.utf8))
            breakBuffer = ""
        }
    }
    func logSurvey(_ entry: SurveyEntry) throws {
        let row = try entry.csv(sessionID: folder.lastPathComponent)
        try surveys.write(contentsOf: Data(row.utf8))
        try surveys.synchronize()
    }
    func logSurveyPrompt(_ entry: SurveyPromptEntry) throws {
        try surveyPrompts.write(contentsOf: Data(entry.csv(sessionID: folder.lastPathComponent).utf8))
        try surveyPrompts.synchronize()
    }
    func finish(startedAt: Date, duration: Double, reason: String) throws {
        try flush()
        try events.synchronize()
        try mouse.synchronize()
        try breaks.synchronize()
        try surveys.synchronize()
        try surveyPrompts.synchronize()
        try metadata(startedAt: startedAt, duration: duration, reason: reason)
    }
    private func metadata(startedAt: Date, duration: Double?, reason: String) throws {
        var fields: [String: Any] = [
            "schema_version": 6, "session_id": folder.lastPathComponent,
            "timed_check_in_policy": "One notification request 600 seconds after session start or actual break return; no idle or fatigue threshold. Deferred while another check-in is open. Break start or session stop cancels the work-period opportunity. Skip/Snooze of a break reminder does not reset it.",
            "survey_prompt_logging": "survey_prompts.csv records scheduled/requested/opened/answered/skipped/cancelled/break_setup/break_started/session_stopped. requested is not proof of banner delivery or viewing. Unopened check-ins have no surveys.csv response; join by check_in_id. reference_break_id identifies the preceding break, not a future break.",
            "check_in_version": SurveyEntry.version,
            "fatigue_question": SurveyEntry.fatigueQuestion,
            "fatigue_scale": "0 = Not tired; 10 = Extremely tired",
            "productivity_question": SurveyEntry.productivityQuestion,
            "productivity_scale": "0 = Not productive; 10 = Extremely productive",
            "survey_logging": "Optional custom ratings, not NASA-TLX or objective productivity. Fatigue before session; fatigue and self-reported productivity before breaks and during_work timed check-ins. Only labels and scale endpoints are displayed, with no explicit recall window. Negative shown_elapsed_seconds means before recording. Open check-in sheets and break setup are marked check_in; exclude them from work predictors. Skipped/cancelled ratings are blank, not zero. Version 1 workload scores must not be relabelled as productivity.",
            "started_at_utc": ISO8601DateFormatter().string(from: startedAt), "status": reason,
            "timestamp_basis": "continuous monotonic callback receipt time including sleep, relative to session start",
            "mouse_interval_seconds": 1,
            "break_policy": "25 work minutes, two distinct >=5-second idle stretches in the past 60 seconds; prompt only while idle; skip 25 minutes; snooze 10 minutes",
            "break_logging": "Detailed activity paused during planned break. At timer expiry activity resumes as awaiting_return until outside-app input or explicit return. breaks.csv is append-only; use latest activity_updated per break_id.",
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
    deinit { try? events.close(); try? mouse.close(); try? breaks.close(); try? surveys.close(); try? surveyPrompts.close() }
}
