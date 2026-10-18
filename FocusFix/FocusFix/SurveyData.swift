import Foundation

// These are custom self-report items, not a NASA-TLX score or an ML prediction.
enum CheckInContext: String { case sessionStart = "session_start", beforeBreak = "before_break" }
enum CheckInStatus: String { case answered, skipped, cancelled }

struct CheckInPrompt {
    let id = UUID().uuidString
    let shownAt = Date()
    let instant = ContinuousClock.now
    let elapsed: Double
}

struct SurveyEntry {
    static let version = "focusfix_check_in_v1"
    static let fatigueQuestion = "How mentally tired do you feel right now?"
    static let workloadQuestion = "How mentally demanding was your work in the last 5 minutes?"
    static let header = "session_id,check_in_id,question_version,context,status,break_id,shown_at_utc,answered_at_utc,shown_elapsed_seconds,answered_elapsed_seconds,fatigue_0_10,workload_0_10\n"
    let id: String
    let context: CheckInContext
    let status: CheckInStatus
    let breakID: String
    let shownAt: Date
    let answeredAt: Date
    let shownElapsed: Double
    let answeredElapsed: Double
    let fatigue: Int?
    let workload: Int?

    func csv(sessionID: String) throws -> String {
        let values = [fatigue, workload].compactMap { $0 }
        guard values.allSatisfy({ (0...10).contains($0) }),
              shownElapsed.isFinite, answeredElapsed.isFinite, shownElapsed <= answeredElapsed,
              context != .sessionStart || workload == nil,
              status != .answered || (fatigue != nil && (context == .sessionStart || workload != nil)),
              status == .answered || values.isEmpty else {
            throw NSError(domain: "FocusFix", code: 3, userInfo: [NSLocalizedDescriptionKey: "Invalid check-in response."])
        }
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return [BreakLogEntry.text(sessionID), BreakLogEntry.text(id), Self.version, context.rawValue,
                status.rawValue, BreakLogEntry.text(breakID), formatter.string(from: shownAt),
                formatter.string(from: answeredAt), csvNumber(shownElapsed), csvNumber(answeredElapsed),
                fatigue.map(String.init) ?? "", workload.map(String.init) ?? ""].joined(separator: ",") + "\n"
    }
}
