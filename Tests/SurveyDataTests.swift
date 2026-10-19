import Foundation

@main
struct SurveyDataTests {
    static func entry(context: CheckInContext = .beforeBreak, status: CheckInStatus = .answered,
                      fatigue: Int? = 5, productivity: Int? = 7, shown: Double = 10, answered: Double = 20) -> SurveyEntry {
        SurveyEntry(id: "test-check-in", context: context, status: status,
            breakID: context == .beforeBreak ? "test-break" : "",
            shownAt: Date(timeIntervalSince1970: shown), answeredAt: Date(timeIntervalSince1970: answered),
            shownElapsed: shown, answeredElapsed: answered, fatigue: fatigue, productivity: productivity)
    }
    static func rejects(_ value: SurveyEntry) {
        do { _ = try value.csv(sessionID: "test"); preconditionFailure("Invalid rating must not be saved") }
        catch { /* Expected. */ }
    }
    static func main() throws {
        let initial = entry(context: .sessionStart, fatigue: 0, productivity: nil, shown: -8, answered: 0)
        let beforeBreak = entry(fatigue: 10, productivity: 0)
        let skipped = entry(status: .skipped, fatigue: nil, productivity: nil)
        let cancelled = entry(status: .cancelled, fatigue: nil, productivity: nil)
        rejects(entry(fatigue: -1))
        rejects(entry(productivity: 11))
        rejects(entry(fatigue: nil))
        rejects(entry(productivity: nil))
        rejects(entry(context: .sessionStart)) // No productivity at session start.
        rejects(entry(context: .duringWork, productivity: nil))
        rejects(entry(context: .duringWork, fatigue: nil))
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
        precondition(SurveyEntry.version == "focusfix_check_in_v2")
        precondition(csv.contains("productivity_0_10") && !csv.contains("workload_0_10"))
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
        precondition(metadata["productivity_question"] as? String == SurveyEntry.productivityQuestion)
        precondition(metadata["workload_question"] == nil)
        precondition(metadata["productivity_scale"] as? String == "0 = Not productive; 10 = Extremely productive")
        print("PASS: fatigue/productivity ranges, start vs break items, blank skipped/cancelled answers, immediate CSV persistence, timestamps, versioned metadata and check-in activity phase.")
    }
}
