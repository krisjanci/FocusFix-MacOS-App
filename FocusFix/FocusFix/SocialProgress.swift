import Foundation

// Only duration summaries cross the social boundary; never event recordings or survey values.
struct SocialEvent: Codable, Equatable, Identifiable {
    let id: UUID
    let kind: String
    let at: Double
    let seconds: Double
    init(id: UUID = UUID(), kind: String, at: Date, seconds: Double) {
        self.id = id; self.kind = kind; self.at = at.timeIntervalSince1970; self.seconds = seconds
    }
}

struct SocialMember: Codable, Identifiable {
    let id: UUID
    let name: String
    let symbol: String
    let color: String
    let work: Int
    let habits: Int
    let workRank: Int
    let habitsRank: Int
    var habitsStreak: Int? = nil
    var habitsStreakRank: Int? = nil
    var habitsStreakFrozen: Bool? = nil
    var workStreak: Int? = nil
    var workStreakRank: Int? = nil
    var workStreakFrozen: Bool? = nil
}
struct SocialGroup: Codable, Identifiable {
    static let capacity = 50
    let id: UUID
    let name: String
    let owner: UUID
    let code: String?
    let members: [SocialMember]
    var description: String? = nil
}
struct GroupInvitation: Codable, Identifiable {
    let id: UUID
    let groupID: UUID
    let groupName: String
    let inviterName: String
}
struct SocialState: Codable {
    let timezone: String
    let progress: DailyProgress
    let groups: [SocialGroup]
    var invitations: [GroupInvitation]? = nil
}

struct DeclaredWorkPending: Codable, Equatable {
    let ownerID: UUID
    let origin: String
    let segmentID: UUID
    let contractVersion: Int
    let days: [String: Double]
}

struct SocialLedger: Codable {
    var timezone: String
    var activatedAt: Double = Date().timeIntervalSince1970
    var progress = DailyProgress()
    var pending: [SocialEvent] = []
    var submitted: Set<UUID> = []
    // These replacement totals must never be sent to the increment-only legacy RPC.
    var declaredWorkPending: [String: DeclaredWorkPending]? = nil
    mutating func stageDeclaredWork(_ value: DeclaredWorkPending, owner: UUID, origin: String) -> Bool {
        guard value.ownerID == owner, value.origin == origin, value.contractVersion == 2,
              value.days.values.allSatisfy({ $0.isFinite && $0 >= 0 }) else { return false }
        if declaredWorkPending == nil { declaredWorkPending = [:] }
        declaredWorkPending?[value.segmentID.uuidString] = value
        return true
    }

    mutating func append(_ event: SocialEvent) {
        guard event.seconds.isFinite, event.seconds > 0, !pending.contains(where: { $0.id == event.id }) else { return }
        pending.append(event)
        apply(event)
    }
    mutating func apply(_ event: SocialEvent) {
        let calendar = DailyProgress.calendar(timeZone: TimeZone(identifier: timezone) ?? .current)
        let date = Date(timeIntervalSince1970: event.at)
        if event.kind == "work" { progress.addWork(seconds: event.seconds, endingAt: date, calendar: calendar) }
        if event.kind == "break" {
            progress.completeBreak(id: event.id.uuidString.lowercased(), seconds: event.seconds, reason: "explicit_return", at: date, calendar: calendar)
        }
    }
    mutating func accept(_ state: SocialState, sent: Set<UUID>) {
        pending.removeAll { sent.contains($0.id) }
        submitted.subtract(sent)
        timezone = state.timezone; progress = state.progress
        for event in pending { apply(event) }
    }
}
