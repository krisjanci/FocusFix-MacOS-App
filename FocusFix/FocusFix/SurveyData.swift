// MARK: - FF: SURVEYS
// Defines custom fatigue/productivity ratings and their CSV format; these are not objective productivity or NASA-TLX measurements.

import Foundation

// These are custom self-report items, not a NASA-TLX score or an ML prediction.
enum CheckInContext: String {
    case sessionStart = "session_start", beforeBreak = "before_break", duringWork = "during_work"
}
enum CheckInStatus: String { case answered, skipped, cancelled }

// Copy these choices at session start so a session keeps one clear survey protocol.
struct SurveyOptions: Equatable {
    var beforeSession = true
    var beforeBreak = true
    var duringWork = true

    func isEnabled(for context: CheckInContext) -> Bool {
        switch context {
        case .sessionStart: return beforeSession
        case .beforeBreak: return beforeBreak
        case .duringWork: return duringWork
        }
    }

    // Disabled is different from a skipped question; save the choices alongside the CSVs.
    var metadata: [String: Bool] {
        ["before_session": beforeSession, "before_break": beforeBreak,
         "during_work_10_minutes": duringWork]
    }
}

struct CheckInPrompt {
    let id = UUID().uuidString
    let shownAt = Date()
    let instant = ContinuousClock.now
    let elapsed: Double
}

struct SurveyEntry {
    static let version = "focusfix_check_in_v2"
    // Store the labels actually shown, without implying an undisplayed time window.
    static let fatigueQuestion = "Mental fatigue"
    static let productivityQuestion = "Productivity"
    static let header = "session_id,check_in_id,question_version,context,status,break_id,shown_at_utc,answered_at_utc,shown_elapsed_seconds,answered_elapsed_seconds,fatigue_0_10,productivity_0_10\n"
    let id: String
    let context: CheckInContext
    let status: CheckInStatus
    let breakID: String
    let shownAt: Date
    let answeredAt: Date
    let shownElapsed: Double
    let answeredElapsed: Double
    let fatigue: Int?
    let productivity: Int?

    // Validate ratings and timing, then write blanks for unanswered questions instead of fake zeroes.
    func csv(sessionID: String) throws -> String {
        let values = [fatigue, productivity].compactMap { $0 }
        guard values.allSatisfy({ (0...10).contains($0) }),
              shownElapsed.isFinite, answeredElapsed.isFinite, shownElapsed <= answeredElapsed,
              context != .sessionStart || productivity == nil,
              status != .answered || (fatigue != nil && (context == .sessionStart || productivity != nil)),
              status == .answered || values.isEmpty else {
            throw NSError(domain: "FocusFix", code: 3, userInfo: [NSLocalizedDescriptionKey: "Invalid check-in response."])
        }
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return [BreakLogEntry.text(sessionID), BreakLogEntry.text(id), Self.version, context.rawValue,
                status.rawValue, BreakLogEntry.text(breakID), formatter.string(from: shownAt),
                formatter.string(from: answeredAt), csvNumber(shownElapsed), csvNumber(answeredElapsed),
                fatigue.map(String.init) ?? "", productivity.map(String.init) ?? ""].joined(separator: ",") + "\n"
    }
}
