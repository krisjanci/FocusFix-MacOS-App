import Foundation

// Pure, clock-driven logic so reminder and break timing can be tested without waiting.
struct BreakRecord {
    let id: String
    let promptID: String
    let start: Double
    let plannedSeconds: Double
    let plannedActivity: String
    var actualActivity: String
    var end: Double?
    var endReason = ""
    var deadline: Double { start + plannedSeconds }
    var actualSeconds: Double? { end.map { max(0, $0 - start) } }
    var extraIdleSeconds: Double? { end.map { max(0, $0 - deadline) } }
}

struct BreakLogEntry {
    let time: Double
    let action: String
    let promptID: String
    let record: BreakRecord?
    let nextEligible: Double?
    let sinceLastBreak: Double

    // Quotes protect commas/newlines in custom activities; the prefix also prevents
    // spreadsheet formula execution when a custom label starts with =, +, - or @.
    static func text(_ value: String) -> String {
        let first = value.trimmingCharacters(in: .whitespacesAndNewlines).first
        let safe = first.map { "=+-@".contains($0) } == true ? "'" + value : value
        return "\"" + safe.replacingOccurrences(of: "\"", with: "\"\"") + "\""
    }
    static let header = "elapsed_seconds,action,prompt_id,break_id,planned_seconds,start_seconds,end_seconds,actual_seconds,extra_idle_seconds,planned_activity,actual_activity,end_reason,next_eligible_seconds,seconds_since_last_break\n"
    var csv: String {
        [csvNumber(time), Self.text(action), Self.text(promptID), Self.text(record?.id ?? ""),
         record.map { csvNumber($0.plannedSeconds) } ?? "",
         record.map { csvNumber($0.start) } ?? "", record?.end.map(csvNumber) ?? "",
         record?.actualSeconds.map(csvNumber) ?? "", record?.extraIdleSeconds.map(csvNumber) ?? "",
         Self.text(record?.plannedActivity ?? ""), Self.text(record?.actualActivity ?? ""),
         Self.text(record?.endReason ?? ""), nextEligible.map(csvNumber) ?? "", csvNumber(sinceLastBreak)]
            .joined(separator: ",") + "\n"
    }
}

struct BreakPolicy {
    enum Phase: String { case work, resting, awaitingReturn = "awaiting_return" }
    private(set) var phase: Phase = .work
    private(set) var promptID: String?
    private(set) var activeBreak: BreakRecord?
    private(set) var lastBreak: BreakRecord?
    private(set) var lastBreakEnd: Double = 0
    private(set) var nextEligible: Double
    private var lastInput: Double = 0
    private var idleGaps: [(start: Double, end: Double)] = []
    private let workDelay: Double
    private let snoozeDelay: Double

    init(workDelay: Double = 25 * 60, snoozeDelay: Double = 10 * 60) {
        self.workDelay = workDelay
        self.snoozeDelay = snoozeDelay
        nextEligible = workDelay
    }
    func sinceLastBreak(at time: Double) -> Double { max(0, time - lastBreakEnd) }
    var activityPhase: String { phase == .awaitingReturn ? "awaiting_return" : "work" }

    mutating func input(at time: Double) {
        guard phase == .work else { return }
        if time - lastInput >= 5 { idleGaps.append((lastInput, time)) }
        lastInput = time
        idleGaps.removeAll { $0.end <= time - 60 }
    }
    mutating func tick(at time: Double) -> BreakLogEntry? {
        if phase == .resting, let record = activeBreak, time >= record.deadline {
            phase = .awaitingReturn
            return entry(at: record.deadline, action: "timer_elapsed", record: record)
        }
        guard phase == .work, promptID == nil, time >= nextEligible, time - lastInput >= 5 else { return nil }
        let cutoff = time - 60
        idleGaps.removeAll { $0.end <= cutoff }
        let completed = idleGaps.filter { $0.end - max($0.start, cutoff) >= 5 }.count
        // The current idle stretch counts once, however long it lasts. Prompt only
        // while idle, not in the middle of renewed typing after two earlier pauses.
        let current = time - max(lastInput, cutoff) >= 5 ? 1 : 0
        guard completed + current >= 2 else { return nil }
        promptID = UUID().uuidString
        return entry(at: time, action: "prompt")
    }
    mutating func deferPrompt(at time: Double, snooze: Bool) -> BreakLogEntry? {
        guard phase == .work, promptID != nil else { return nil }
        nextEligible = time + (snooze ? snoozeDelay : workDelay)
        let result = entry(at: time, action: snooze ? "snooze" : "skip")
        promptID = nil
        resetInput(at: time)
        return result
    }
    mutating func begin(at time: Double, seconds: Double, activity: String) -> BreakLogEntry? {
        guard phase == .work, seconds.isFinite, (60...7200).contains(seconds), !activity.isEmpty else { return nil }
        let record = BreakRecord(id: UUID().uuidString, promptID: promptID ?? "",
            start: time, plannedSeconds: seconds, plannedActivity: activity, actualActivity: "")
        activeBreak = record
        phase = .resting
        let result = entry(at: time, action: "break_start", record: record)
        promptID = nil
        resetInput(at: time)
        return result
    }
    mutating func finish(at time: Double, reason: String) -> BreakLogEntry? {
        guard var record = activeBreak else { return nil }
        record.end = max(record.start, time)
        record.endReason = reason
        let result = entry(at: time, action: "break_end", record: record)
        lastBreak = record
        activeBreak = nil
        phase = .work
        lastBreakEnd = time
        nextEligible = time + workDelay
        resetInput(at: time)
        return result
    }
    mutating func updateActivity(_ activity: String, at time: Double) -> BreakLogEntry? {
        guard !activity.isEmpty, var record = lastBreak else { return nil }
        record.actualActivity = activity
        lastBreak = record
        return entry(at: time, action: "activity_updated", record: record)
    }
    func entry(at time: Double, action: String, record: BreakRecord? = nil) -> BreakLogEntry {
        BreakLogEntry(time: time, action: action, promptID: record?.promptID ?? promptID ?? "",
            record: record, nextEligible: phase == .work ? nextEligible : nil,
            sinceLastBreak: sinceLastBreak(at: time))
    }
    private mutating func resetInput(at time: Double) { lastInput = time; idleGaps = [] }
}
