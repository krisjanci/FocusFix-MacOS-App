import Foundation

@main
struct SurveyDataTests {
    static func entry(context: CheckInContext = .beforeBreak, status: CheckInStatus = .answered,
                      fatigue: Int? = 5, workload: Int? = 7, shown: Double = 10, answered: Double = 20) -> SurveyEntry {
        SurveyEntry(id: "test-check-in", context: context, status: status,
            breakID: context == .beforeBreak ? "test-break" : "",
            shownAt: Date(timeIntervalSince1970: shown), answeredAt: Date(timeIntervalSince1970: answered),
            shownElapsed: shown, answeredElapsed: answered, fatigue: fatigue, workload: workload)
    }
    static func rejects(_ value: SurveyEntry) {
        do { _ = try value.csv(sessionID: "test"); preconditionFailure("Invalid rating must not be saved") }
        catch { /* Expected. */ }
    }
    static func main() throws {
        let initial = entry(context: .sessionStart, fatigue: 0, workload: nil, shown: -8, answered: 0)
        let beforeBreak = entry(fatigue: 10, workload: 0)
        let skipped = entry(status: .skipped, fatigue: nil, workload: nil)
        let cancelled = entry(status: .cancelled, fatigue: nil, workload: nil)
        rejects(entry(fatigue: -1))
        rejects(entry(workload: 11))
        rejects(entry(fatigue: nil))
        rejects(entry(workload: nil))
        rejects(entry(context: .sessionStart)) // No workload at session start.
        rejects(entry(status: .skipped)) // Skipping must never silently submit defaults.
        rejects(entry(status: .cancelled))
        rejects(entry(shown: 21))
        rejects(entry(answered: .infinity))

        let root = FileManager.default.temporaryDirectory.appendingPathComponent("focusfix-survey-tests-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: root) }
        let writer = try RecordingWriter(root: root, id: "test-session", startedAt: Date(timeIntervalSince1970: 0))
        for value in [initial, beforeBreak, skipped, cancelled] { try writer.logSurvey(value) }
        // Rows are readable immediately, before Stop or the next periodic flush.
        let csv = try String(contentsOf: writer.folder.appendingPathComponent("surveys.csv"), encoding: .utf8)
        let lines = csv.split(separator: "\n")
        precondition(lines.count == 5)
        precondition(lines.allSatisfy { $0.split(separator: ",", omittingEmptySubsequences: false).count == 12 })
        precondition(lines[1].contains("session_start,answered") && lines[1].hasSuffix("-8.000000,0.000000,0,"))
        precondition(lines[2].contains("before_break,answered,\"test-break\"") && lines[2].hasSuffix(",10,0"))
        precondition(lines[3].contains("skipped") && lines[3].hasSuffix(",,"))
        precondition(lines[4].contains("cancelled") && lines[4].hasSuffix(",,"))
        precondition(csv.contains(SurveyEntry.version) && csv.contains("\"test-session\""))
        try writer.event(time: 10, type: "check_in_start", activityPhase: "check_in")
        var mouse = MouseAccumulator(initialPosition: .zero, start: 10, activityPhase: "check_in", workReference: nil)
        writer.append(mouse.stop(at: 11))
        try writer.finish(startedAt: Date(timeIntervalSince1970: 0), duration: 20, reason: "user_stop")
        let events = try String(contentsOf: writer.folder.appendingPathComponent("events.csv"), encoding: .utf8)
        let movements = try String(contentsOf: writer.folder.appendingPathComponent("mouse_movement.csv"), encoding: .utf8)
        precondition(events.contains(",check_in,"))
        precondition(movements.contains(",check_in,"))
        let metadata = try JSONSerialization.jsonObject(with: Data(contentsOf: writer.folder.appendingPathComponent("session.json"))) as! [String: Any]
        precondition(metadata["fatigue_question"] as? String == SurveyEntry.fatigueQuestion)
        precondition(metadata["workload_question"] as? String == SurveyEntry.workloadQuestion)
        print("PASS: fatigue/workload ranges, start vs break items, blank skipped/cancelled answers, immediate CSV persistence, timestamps, metadata and check-in activity phase.")
    }
}
