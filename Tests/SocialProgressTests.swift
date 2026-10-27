import Foundation

@main struct SocialProgressTests {
    static func date(_ string: String) -> Date { ISO8601DateFormatter().date(from: string)! }
    static let cal = DailyProgress.calendar(timeZone: TimeZone(identifier: "America/New_York")!)
    static func main() throws {
        let monday = date("2026-10-19T16:00:00Z")
        var progress = DailyProgress()
        progress.reconcile(at: monday, calendar: cal)
        progress.addWork(seconds: 3600, endingAt: monday, calendar: cal)
        progress.reconcile(at: date("2026-10-21T16:00:00Z"), calendar: cal)
        precondition(progress.frozenDays == ["2026-10-20"])
        precondition(progress.streak(at: date("2026-10-21T16:00:00Z"), calendar: cal) == 1)
        precondition(progress.tokensRemaining(at: monday, calendar: cal) == 2)
        progress.reconcile(at: date("2026-10-22T16:00:00Z"), calendar: cal)
        precondition(progress.frozenDays == ["2026-10-20"])
        precondition(progress.streak(at: date("2026-10-22T16:00:00Z"), calendar: cal) == 0)
        // Late work replaces a freeze and returns its token, then protects Wednesday instead.
        progress.addWork(seconds: 3600, endingAt: date("2026-10-20T16:00:00Z"), calendar: cal)
        progress.reconcile(at: date("2026-10-22T16:00:00Z"), calendar: cal)
        precondition(progress.frozenDays == ["2026-10-21"])
        precondition(progress.streak(at: date("2026-10-22T16:00:00Z"), calendar: cal) == 2)
        let saved = progress
        progress.reconcile(at: date("2026-10-22T16:00:00Z"), calendar: cal)
        precondition(saved == progress)
        // Friday and Monday can both be frozen; weekends neither spend nor earn streak days.
        var weekends = DailyProgress()
        weekends.reconcile(at: date("2026-10-22T16:00:00Z"), calendar: cal)
        weekends.addWork(seconds: 3600, endingAt: date("2026-10-22T16:00:00Z"), calendar: cal)
        weekends.reconcile(at: date("2026-10-27T16:00:00Z"), calendar: cal)
        precondition(weekends.frozenDays == ["2026-10-23", "2026-10-26"])
        // Alternating work and missed days exhaust exactly three, with no rollover.
        var monthly = DailyProgress()
        monthly.reconcile(at: monday, calendar: cal)
        for day in [19,21,23,27] { monthly.addWork(seconds: 3600, endingAt: date("2026-10-\(day)T16:00:00Z"), calendar: cal) }
        monthly.reconcile(at: date("2026-10-29T16:00:00Z"), calendar: cal)
        precondition(monthly.frozenDays == ["2026-10-20", "2026-10-22", "2026-10-26"])
        precondition(monthly.tokensRemaining(at: monday, calendar: cal) == 0)
        precondition(monthly.tokensRemaining(at: date("2026-11-01T17:00:00Z"), calendar: cal) == 3)
        var boundary = DailyProgress()
        let september = date("2026-09-29T16:00:00Z")
        boundary.reconcile(at: september, calendar: cal)
        boundary.addWork(seconds: 3600, endingAt: september, calendar: cal)
        boundary.reconcile(at: date("2026-10-02T16:00:00Z"), calendar: cal)
        precondition(boundary.frozenDays == ["2026-09-30"])
        precondition(boundary.tokensRemaining(at: monday, calendar: cal) == 3) // New month cannot bypass adjacent-date rule.
        var dst = DailyProgress()
        let friday = date("2026-10-30T16:00:00Z")
        dst.reconcile(at: friday, calendar: cal)
        dst.addWork(seconds: 3600, endingAt: friday, calendar: cal)
        dst.reconcile(at: date("2026-11-03T17:00:00Z"), calendar: cal)
        precondition(dst.frozenDays == ["2026-11-02"])
        // Old files migrate without historical freezes or loss of breaks/work.
        let old = Data(#"{"version":1,"days":{"2026-10-19":{"workSeconds":3600,"completedBreakIDs":["existing"]}}}"#.utf8)
        var migrated = try JSONDecoder().decode(DailyProgress.self, from: old)
        migrated.reconcile(at: date("2026-10-26T16:00:00Z"), calendar: cal)
        precondition(migrated.frozenDays.isEmpty && migrated.day(at: monday, calendar: cal).completedBreakIDs == ["existing"])
        let roundTrip = try JSONDecoder().decode(DailyProgress.self, from: JSONEncoder().encode(migrated))
        precondition(roundTrip == migrated)
        // Acknowledging one batch preserves events created while it was in flight.
        var ledger = SocialLedger(timezone: "America/New_York")
        let work = SocialEvent(kind: "work", at: monday, seconds: 3599)
        let lastSecond = SocialEvent(kind: "work", at: monday.addingTimeInterval(1), seconds: 1)
        ledger.append(work); ledger.append(work); ledger.append(lastSecond)
        precondition(ledger.pending.count == 2 && ledger.progress.day(at: monday, calendar: cal).workSeconds == 3600)
        var server = DailyProgress(); server.addWork(seconds: 3599, endingAt: monday, calendar: cal)
        ledger.accept(SocialState(timezone: "America/New_York", progress: server, groups: []), sent: [work.id])
        precondition(ledger.pending == [lastSecond] && ledger.progress.day(at: monday, calendar: cal).workSeconds == 3600)
        let tooShort = SocialEvent(kind: "break", at: monday, seconds: 59.999)
        ledger.append(tooShort)
        precondition(ledger.progress.day(at: monday, calendar: cal).completedBreakIDs.isEmpty)
        let rest = SocialEvent(kind: "break", at: monday, seconds: 60)
        ledger.append(rest); ledger.append(rest)
        precondition(ledger.progress.day(at: monday, calendar: cal).completedBreakIDs.count == 1)
        print("Automatic freezes, month limits, weekday boundaries, migration, idempotent summaries and in-flight acknowledgement passed")
    }
}
