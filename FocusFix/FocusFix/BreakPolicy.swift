// MARK: - FF: BREAKS
// Pure timing rules for break reminders and actual break duration. These can be tested without the macOS UI.

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
    // The planned end time, which can differ from the user's actual return.
    var deadline: Double { start + plannedSeconds }
    // The actual recorded break duration, once an end time is known.
    var actualSeconds: Double? { end.map { max(0, $0 - start) } }
    // Time after the planned timer before actual return; unknown until the break ends.
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
    // Quote a CSV text cell and protect spreadsheet users from formula-like text.
    static func text(_ value: String) -> String {
        let first = value.trimmingCharacters(in: .whitespacesAndNewlines).first
        let safe = first.map { "=+-@".contains($0) } == true ? "'" + value : value
        return "\"" + safe.replacingOccurrences(of: "\"", with: "\"\"") + "\""
    }
    static let header = "elapsed_seconds,action,prompt_id,break_id,planned_seconds,start_seconds,end_seconds,actual_seconds,extra_idle_seconds,planned_activity,actual_activity,end_reason,next_eligible_seconds,seconds_since_last_break\n"
    // Serialize one break decision with quoted labels and optional timing fields.
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

    // Set the normal reminder delay and the shorter snooze delay.
    init(workDelay: Double = 25 * 60, snoozeDelay: Double = 10 * 60) {
        self.workDelay = workDelay
        self.snoozeDelay = snoozeDelay
        nextEligible = workDelay
    }
    // Measure elapsed time since the last actual break ended, or session start before the first break.
    func sinceLastBreak(at time: Double) -> Double { max(0, time - lastBreakEnd) }
    // Label resumed sampling after timer expiry as awaiting_return until the user returns.
    var activityPhase: String { phase == .awaitingReturn ? "awaiting_return" : "work" }

    // Remember separate idle gaps so one long pause is not counted as two pauses.
    mutating func input(at time: Double) {
        guard phase == .work else { return }
        if time - lastInput >= 5 { idleGaps.append((lastInput, time)) }
        lastInput = time
        idleGaps.removeAll { $0.end <= time - 60 }
    }
    // Wait for the reminder delay and two distinct idle gaps, or notice that the planned break timer expired.
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
    // Clear the current reminder and start a fresh skip/snooze wait.
    mutating func deferPrompt(at time: Double, snooze: Bool) -> BreakLogEntry? {
        guard phase == .work, promptID != nil else { return nil }
        nextEligible = time + (snooze ? snoozeDelay : workDelay)
        let result = entry(at: time, action: snooze ? "snooze" : "skip")
        promptID = nil
        resetInput(at: time)
        return result
    }
    // Start a valid planned break and remember its chosen activity and duration.
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
    // Close the actual break when the person returns, including time beyond the planned timer.
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
    // Correct the reported activity for the most recently completed break.
    mutating func updateActivity(_ activity: String, at time: Double) -> BreakLogEntry? {
        guard !activity.isEmpty, var record = lastBreak else { return nil }
        record.actualActivity = activity
        lastBreak = record
        return entry(at: time, action: "activity_updated", record: record)
    }
    // Build a log row describing a break decision or timing transition.
    func entry(at time: Double, action: String, record: BreakRecord? = nil) -> BreakLogEntry {
        BreakLogEntry(time: time, action: action, promptID: record?.promptID ?? promptID ?? "",
            record: record, nextEligible: phase == .work ? nextEligible : nil,
            sinceLastBreak: sinceLastBreak(at: time))
    }
    // Forget earlier idle gaps so they cannot trigger a new reminder immediately.
    private mutating func resetInput(at time: Double) { lastInput = time; idleGaps = [] }
}
