import Foundation

@main struct ReminderEligibilityTests {
    static func main() throws {
        var contract = RecordingContract(mode: .automatic, startedAt: Date(timeIntervalSince1970: 0))
        let id = contract.recordingID
        var gate = ReminderEligibility()
        precondition(!ReminderEligibility.eligible(context: .unknown, screenUseEnabled: false))
        precondition(!ReminderEligibility.eligible(context: .nonWork, screenUseEnabled: false))
        precondition(ReminderEligibility.eligible(context: .work, screenUseEnabled: false))
        precondition(ReminderEligibility.eligible(context: .unknown, screenUseEnabled: true))
        precondition(gate.schedule(token: "unknown", recordingID: id, interval: contract.intervals[0], elapsed: 1,
            monotonic: 1, date: Date(), screenUseEnabled: false) == nil)
        try contract.changeContext(.work, at: 1, effectiveAt: Date(), recordedAt: Date(), source: .userAction)
        let work = contract.intervals.last!
        let request = gate.schedule(token: "current", recordingID: id, interval: work, elapsed: 1501,
            monotonic: 1501, date: Date(), screenUseEnabled: false)!
        precondition(request.workPeriodID == work.logicalID && !request.screenUse)
        // No response leaves a request, never a context confirmation or fatigue answer.
        precondition(gate.pending == request && contract.currentContext == .work)
        precondition(!gate.accepts(token: "stale", recordingID: id, contextID: work.logicalID, active: true))
        precondition(!gate.accepts(token: "current", recordingID: UUID(), contextID: work.logicalID, active: true))
        precondition(!gate.accepts(token: "current", recordingID: id, contextID: UUID(), active: true))
        precondition(!gate.accepts(token: "current", recordingID: id, contextID: work.logicalID, active: false))
        // Midnight segment changes preserve logical context, so the same pending period remains valid.
        let rotated = RecordingContract(recordingID: id, mode: .automatic, startedAt: Date(), elapsedOrigin: 1501, continuing: work)
        precondition(gate.accepts(token: "current", recordingID: rotated.recordingID,
            contextID: rotated.intervals[0].logicalID, active: true))
        let action = gate.consume(token: "current", recordingID: id, contextID: work.logicalID,
            active: true, monotonic: 1502, snooze: true)
        precondition(action == request && gate.cooldownUntil == 2102)
        precondition(gate.consume(token: "current", recordingID: id, contextID: work.logicalID,
            active: true, monotonic: 1503) == nil)
        precondition(gate.schedule(token: "too-soon", recordingID: id, interval: work, elapsed: 1600,
            monotonic: 1600, date: Date(), screenUseEnabled: false) == nil)
        _ = gate.schedule(token: "new", recordingID: id, interval: work, elapsed: 2200,
            monotonic: 2200, date: Date(), screenUseEnabled: false)
        try contract.changeContext(.nonWork, at: 2201, effectiveAt: Date(), recordedAt: Date(), source: .userAction)
        precondition(!gate.accepts(token: "new", recordingID: id, contextID: contract.intervals.last!.logicalID, active: true))
        gate.invalidate()
        precondition(gate.pending == nil && gate.cooldownUntil == 3700)
        print("PASS: work/screen-use eligibility, current/stale/duplicate/no-response, changed context/account, pause/revoke and midnight cooldown")
    }
}
