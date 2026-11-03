import Foundation

nonisolated struct ReminderRequest: Codable, Equatable {
    static let policyVersion = "focusfix.fixed-context.v1"
    let id: String
    let recordingID: UUID
    let contextID: UUID
    let workPeriodID: UUID?
    let policyVersion: String
    let context: ActivityContext
    let scheduledElapsed: Double
    let requestedAtUTC: Date
    let screenUse: Bool
}
nonisolated struct ReminderLogEntry: Codable {
    let request: ReminderRequest
    let action: String
    let effectiveElapsed: Double
    let recordedAtUTC: Date
}
nonisolated struct ReminderEligibility {
    private(set) var pending: ReminderRequest?
    private(set) var cooldownUntil: Double = 0
    static func eligible(context: ActivityContext, screenUseEnabled: Bool) -> Bool {
        context == .work || screenUseEnabled
    }
    mutating func schedule(token: String, recordingID: UUID, interval: ContextInterval,
                           elapsed: Double, monotonic: Double, date: Date, screenUseEnabled: Bool) -> ReminderRequest? {
        guard pending == nil, monotonic >= cooldownUntil,
              Self.eligible(context: interval.context, screenUseEnabled: screenUseEnabled) else { return nil }
        let request = ReminderRequest(id: token, recordingID: recordingID, contextID: interval.logicalID,
            workPeriodID: interval.context == .work ? interval.logicalID : nil,
            policyVersion: ReminderRequest.policyVersion, context: interval.context,
            scheduledElapsed: elapsed, requestedAtUTC: date, screenUse: interval.context != .work)
        pending = request
        cooldownUntil = monotonic + 1500
        return request
    }
    func accepts(token: String, recordingID: UUID, contextID: UUID, active: Bool) -> Bool {
        guard active, let pending else { return false }
        return pending.id == token && pending.recordingID == recordingID && pending.contextID == contextID
            && pending.policyVersion == ReminderRequest.policyVersion
    }
    mutating func consume(token: String, recordingID: UUID, contextID: UUID, active: Bool,
                          monotonic: Double, snooze: Bool = false) -> ReminderRequest? {
        guard accepts(token: token, recordingID: recordingID, contextID: contextID, active: active) else { return nil }
        let result = pending
        pending = nil
        cooldownUntil = monotonic + (snooze ? 600 : 1500)
        return result
    }
    mutating func invalidate() { pending = nil }
}
