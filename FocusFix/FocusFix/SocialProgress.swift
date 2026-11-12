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
    var photo: Data? = nil
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
    var declaredWorkSyncVersion: Int? = nil
}

struct DeclaredWorkInterval: Codable, Equatable {
    var start: Double
    var end: Double
    static func merged(_ values: [DeclaredWorkInterval]) -> [DeclaredWorkInterval] {
        var result: [DeclaredWorkInterval] = []
        for value in values.sorted(by: { $0.start < $1.start }) {
            guard value.start.isFinite, value.end.isFinite, value.end > value.start else { continue }
            if let last = result.last, value.start <= last.end + 0.000001 {
                result[result.count - 1].end = max(last.end, value.end)
            } else { result.append(value) }
        }
        return result
    }
    static func observed(_ slices: [CoverageSlice], startedAt: Date, origin: Double) -> [DeclaredWorkInterval] {
        merged(slices.map { DeclaredWorkInterval(start: startedAt.timeIntervalSince1970 + $0.start - origin,
            end: startedAt.timeIntervalSince1970 + $0.end - origin) })
    }
}
struct DeclaredWorkAcknowledgement: Codable { let segmentID: UUID; let revision: Int }
struct DeclaredWorkResponse: Codable { let version: Int; let acknowledged: [DeclaredWorkAcknowledgement] }
struct DeclaredWorkPending: Codable, Equatable {
    let ownerID: UUID
    let origin: String
    let segmentID: UUID
    let contractVersion: Int
    let days: [String: Double]
    var startedAt: Double? = nil
    var observedThrough: Double? = nil
    var intervals: [DeclaredWorkInterval]? = nil
    var revision: Int? = nil
    var ready: Bool { startedAt != nil && observedThrough != nil && intervals != nil && (revision ?? 0) > 0 }
}

struct SocialLedger: Codable {
    var timezone: String
    var activatedAt: Double = Date().timeIntervalSince1970
    var progress = DailyProgress()
    var pending: [SocialEvent] = []
    var submitted: Set<UUID> = []
    // These replacement totals must never be sent to the increment-only legacy RPC.
    var declaredWorkPending: [String: DeclaredWorkPending]? = nil
    var declaredWorkSnapshots: [String: DeclaredWorkPending]? = nil
    mutating func stageDeclaredWork(_ value: DeclaredWorkPending, owner: UUID, origin: String) -> Bool {
        guard value.ownerID == owner, value.origin == origin, value.contractVersion == 2,
              value.days.values.allSatisfy({ $0.isFinite && $0 >= 0 }) else { return false }
        let key = value.segmentID.uuidString
        let previous = declaredWorkSnapshots?[key] ?? declaredWorkPending?[key]
        // Legacy day-only replays cannot overwrite detailed, correction-safe summaries.
        if value.intervals == nil && previous?.intervals != nil { return false }
        if previous?.days == value.days && previous?.intervals == value.intervals && previous?.startedAt == value.startedAt { return false }
        var staged = value
        if let start = value.startedAt, let end = value.observedThrough, let intervals = value.intervals {
            guard start.isFinite, end.isFinite, end >= start,
                  intervals.allSatisfy({ $0.start >= start && $0.end <= end && $0.end > $0.start }) else { return false }
            staged.revision = (previous?.revision ?? 0) + 1
            if declaredWorkSnapshots == nil { declaredWorkSnapshots = [:] }
            declaredWorkSnapshots?[key] = staged
        }
        if declaredWorkPending == nil { declaredWorkPending = [:] }
        declaredWorkPending?[key] = staged
        return true
    }
    mutating func acknowledgeDeclaredWork(_ acknowledgements: [DeclaredWorkAcknowledgement], sent: [DeclaredWorkPending]) {
        for ack in acknowledgements {
            guard let original = sent.first(where: { $0.segmentID == ack.segmentID && $0.revision == ack.revision }),
                  declaredWorkPending?[ack.segmentID.uuidString] == original else { continue }
            declaredWorkPending?.removeValue(forKey: ack.segmentID.uuidString)
        }
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
