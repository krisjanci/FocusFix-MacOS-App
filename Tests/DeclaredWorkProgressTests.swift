import Foundation

@main struct DeclaredWorkProgressTests {
    static func main() throws {
        let date = ISO8601DateFormatter().date(from: "2026-11-02T23:59:30Z")!
        let calendar = DailyProgress.calendar(timeZone: TimeZone(secondsFromGMT: 0)!)
        let slices = [CoverageSlice(start: 0, end: 60, phase: .normal)]
        let allocation = DailyProgress.declaredAllocation(slices: slices, startedAt: date, origin: 0, calendar: calendar)
        precondition(allocation["2026-11-02"] == 30 && allocation["2026-11-03"] == 30)
        var progress = DailyProgress()
        // Protect historical points: only the new segment's own contribution is replaced.
        progress.addWork(seconds: 3600, endingAt: date, calendar: calendar)
        try progress.replaceDeclaredWork(segmentID: "segment", days: allocation)
        try progress.replaceDeclaredWork(segmentID: "segment", days: allocation)
        precondition(progress.day(at: date, calendar: calendar).workSeconds == 3630)
        try progress.replaceDeclaredWork(segmentID: "segment", days: ["2026-11-02": 5], revision: 1)
        precondition(progress.day(at: date, calendar: calendar).workSeconds == 3605)
        precondition(progress.day(at: date.addingTimeInterval(60), calendar: calendar).workSeconds == 0)
        precondition(progress.declaredRevisions["segment"] == 1)
        let restored = try JSONDecoder().decode(DailyProgress.self, from: JSONEncoder().encode(progress))
        precondition(restored == progress && restored.isValid)
        do { try progress.replaceDeclaredWork(segmentID: "bad", days: ["2026-11-02": .nan]); preconditionFailure("Nonfinite work accepted") } catch { }
        precondition(!progress.completeBreak(id: "idle", seconds: 600, reason: "idle_cutoff", at: date, calendar: calendar))
        precondition(progress.completeBreak(id: "break", seconds: 60, reason: "explicit_return", at: date, calendar: calendar))
        precondition(!progress.completeBreak(id: "break", seconds: 60, reason: "explicit_return", at: date, calendar: calendar))
        let owner = UUID(), other = UUID(), segment = UUID()
        var ledger = SocialLedger(timezone: "UTC")
        let pending = DeclaredWorkPending(ownerID: owner, origin: "https://synthetic.invalid", segmentID: segment, contractVersion: 2, days: allocation)
        precondition(ledger.stageDeclaredWork(pending, owner: owner, origin: pending.origin))
        precondition(ledger.pending.isEmpty) // No legacy increments can be produced by new totals.
        precondition(!ledger.stageDeclaredWork(pending, owner: other, origin: pending.origin))
        precondition(!ledger.stageDeclaredWork(pending, owner: owner, origin: "https://other.invalid"))
        let correction = DeclaredWorkPending(ownerID: owner, origin: pending.origin, segmentID: segment, contractVersion: 2, days: ["2026-11-02": 1])
        precondition(ledger.stageDeclaredWork(correction, owner: owner, origin: pending.origin))
        let offline = try JSONDecoder().decode(SocialLedger.self, from: JSONEncoder().encode(ledger))
        precondition(offline.declaredWorkPending?.count == 1 && offline.declaredWorkPending?[segment.uuidString] == correction)
        precondition(offline.pending.isEmpty)
        print("PASS: observed-work allocation, midnight, correction decreases/idempotence, protected legacy points, explicit-break rules, offline pending replacements and account isolation")
    }
}
