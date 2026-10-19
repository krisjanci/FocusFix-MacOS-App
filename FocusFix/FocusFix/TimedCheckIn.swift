// MARK: - FF: SURVEYS
// Schedules one during-work survey per work period, independently of fatigue or idle detection.

import Foundation

struct TimedCheckIn {
    let id: String
    let due: Double
    let referenceBreakID: String
    var requestedAt: Double?
    var openedAt: Double?
}

// One opportunity per work period. No idle/fatigue condition and no repeating timer.
struct TimedCheckInPolicy {
    private(set) var current: TimedCheckIn?
    // Whether the current opportunity has been requested and is waiting for an action.
    var hasPending: Bool { current?.requestedAt != nil }

    // Replace the previous opportunity with one due 10 minutes from this start or break return.
    mutating func schedule(from time: Double, afterBreak: String = "") -> TimedCheckIn {
        let item = TimedCheckIn(id: UUID().uuidString, due: time + 600, referenceBreakID: afterBreak)
        current = item
        return item
    }
    // Request the due check-in once, only when another check-in or break does not block it.
    mutating func tick(at time: Double, canPrompt: Bool) -> TimedCheckIn? {
        guard canPrompt, var item = current, item.requestedAt == nil, time >= item.due else { return nil }
        item.requestedAt = time
        current = item
        return item
    }
    // Mark the current opportunity opened and reject stale or duplicate prompt actions.
    mutating func open(token: String, at time: Double) -> TimedCheckIn? {
        guard var item = current, item.id == token, let requested = item.requestedAt,
              item.openedAt == nil, time >= requested else { return nil }
        item.openedAt = time
        current = item
        return item
    }
    // Return and clear the current opportunity so it cannot be answered twice.
    mutating func finish() -> TimedCheckIn? {
        let result = current
        current = nil
        return result
    }
}

struct SurveyPromptEntry {
    static let header = "session_id,check_in_id,action,elapsed_seconds,due_elapsed_seconds,notification_requested_elapsed_seconds,opened_elapsed_seconds,reference_break_id\n"
    let item: TimedCheckIn
    let action: String
    let time: Double
    // Format a prompt-history row, leaving times blank for actions that never happened.
    func csv(sessionID: String) -> String {
        [BreakLogEntry.text(sessionID), BreakLogEntry.text(item.id), BreakLogEntry.text(action),
         csvNumber(time), csvNumber(item.due), item.requestedAt.map(csvNumber) ?? "",
         item.openedAt.map(csvNumber) ?? "", BreakLogEntry.text(item.referenceBreakID)]
            .joined(separator: ",") + "\n"
    }
}
