// MARK: - FF: STORAGE
// Formats and saves local activity data. Mouse positions and key identities are used transiently, not written to the recording.

import Foundation
import CoreGraphics

// Stable CSV numbers, regardless of the Mac's language.
// Format numbers with a decimal point so CSVs are consistent across the Mac's language settings.
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
    // Serialize one mouse interval's totals without including cursor coordinates.
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
    // Start a mouse-summary window with the current position and activity phase.
    init(initialPosition: CGPoint, start: Double = 0, activityPhase: String = "work", workReference: Double? = 0) {
        previous = initialPosition
        self.start = start
        self.activityPhase = activityPhase
        self.workReference = workReference
    }

    // Close full one-second mouse windows, including windows with no movement.
    mutating func advance(to time: Double) -> [MouseSummary] {
        var rows: [MouseSummary] = []
        while start + 1 <= time { rows.append(finish(at: start + 1)) }
        return rows
    }
    // Add the distance between successive positions to the current window, without saving coordinates.
    mutating func move(to position: CGPoint, at time: Double) -> [MouseSummary] {
        let rows = advance(to: time)
        let segment = hypot(position.x - previous.x, position.y - previous.y)
        distance += segment
        events += 1
        if segment > 0 { lastMovement = time }
        previous = position
        return rows
    }
    // Finish full windows and the final partial mouse window when sampling stops.
    mutating func stop(at time: Double) -> [MouseSummary] {
        var rows = advance(to: time)
        if time > start { rows.append(finish(at: time)) }
        return rows
    }
    // Create one mouse summary and reset its counters for the next window.
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
    // Remember the start of a key press in memory, ignoring automatic key repeats.
    mutating func down(code: UInt16, at time: Double, repeated: Bool) {
        if !repeated { pressed[code] = time }
    }
    // Calculate how long a matching key was held, then forget that temporary key identity.
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
    private let participantID: String?
    private let sharingConsentID: String?
    // Create a new session folder and CSV files, then write the initial session metadata.
    init(root: URL, id: String, startedAt: Date, participantID: String? = nil, sharingConsentID: String? = nil) throws {
        self.participantID = participantID
        self.sharingConsentID = sharingConsentID
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
    // Buffer a generic keyboard, click, scroll or app-switch event with timing and phase information.
    func event(time: Double, type: String, repeated: Bool? = nil, hold: Double? = nil,
               scrollX: Double? = nil, scrollY: Double? = nil, precise: Bool? = nil,
               activityPhase: String = "work", secondsSinceLastBreak: Double? = nil) throws {
        eventBuffer += [csvNumber(time), type, repeated.map { $0 ? "1" : "0" } ?? "",
            hold.map(csvNumber) ?? "", scrollX.map(csvNumber) ?? "", scrollY.map(csvNumber) ?? "",
            precise.map { $0 ? "1" : "0" } ?? "", activityPhase,
            secondsSinceLastBreak.map(csvNumber) ?? ""].joined(separator: ",") + "\n"
        if eventBuffer.utf8.count >= 64_000 { try flush() }
    }
    // Add mouse-summary CSV rows to the pending write buffer.
    func append(_ summaries: [MouseSummary]) { mouseBuffer += summaries.map(\.csv).joined() }
    // Write and synchronize a break transition so it survives a later interruption.
    func logBreak(_ entry: BreakLogEntry) throws {
        breakBuffer += entry.csv
        // Lifecycle decisions are persisted immediately, not just on session Stop.
        try flush()
        try breaks.synchronize()
    }
    // Write pending activity and break buffers to disk and clear the buffers.
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
    // Validate and save a check-in response immediately rather than waiting for the activity buffer.
    func logSurvey(_ entry: SurveyEntry) throws {
        let row = try entry.csv(sessionID: folder.lastPathComponent)
        try surveys.write(contentsOf: Data(row.utf8))
        try surveys.synchronize()
    }
    // Save a survey opportunity's scheduling/delivery/action history separately from its answers.
    func logSurveyPrompt(_ entry: SurveyPromptEntry) throws {
        try surveyPrompts.write(contentsOf: Data(entry.csv(sessionID: folder.lastPathComponent).utf8))
        try surveyPrompts.synchronize()
    }
    // Flush and synchronize session files, then save the final duration and stop reason.
    func finish(startedAt: Date, duration: Double, reason: String) throws {
        try flush()
        try events.synchronize()
        try mouse.synchronize()
        try breaks.synchronize()
        try surveys.synchronize()
        try surveyPrompts.synchronize()
        try metadata(startedAt: startedAt, duration: duration, reason: reason)
    }
    // Write session timing, schema, participant identity and consent information into session.json.
    private func metadata(startedAt: Date, duration: Double?, reason: String) throws {
        var fields: [String: Any] = [
            "schema_version": 7, "session_id": folder.lastPathComponent,
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
        if let participantID { fields["participant_id"] = participantID }
        if let sharingConsentID { fields["sharing_consent_id"] = sharingConsentID }
        fields["sharing_policy"] = "Optional research sharing. Eligibility captured at session start; opt-out cancels queued uploads. Participant ID identifies a Keychain installation, not a verified person. 180 elapsed minutes (including breaks) per UTC upload day; no truncation."
        if let duration {
            fields["duration_seconds"] = duration
            fields["ended_at_utc"] = ISO8601DateFormatter().string(from: startedAt.addingTimeInterval(duration))
        }
        let data = try JSONSerialization.data(withJSONObject: fields, options: [.prettyPrinted, .sortedKeys])
        try data.write(to: folder.appendingPathComponent("session.json"), options: .atomic)
    }
    // Close all recording file handles when this writer is released.
    deinit { try? events.close(); try? mouse.close(); try? breaks.close(); try? surveys.close(); try? surveyPrompts.close() }
}
