import Foundation

@main
struct DailyProgressTests {
    static var calendar: Calendar { DailyProgress.calendar(timeZone: TimeZone(identifier: "America/New_York")!) }
    static func date(_ value: String) -> Date { ISO8601DateFormatter().date(from: value)! }
    static func near(_ a: Double, _ b: Double) { precondition(abs(a - b) < 0.00001, "\(a) != \(b)") }
    static func check(_ value: Bool) { precondition(value) }
    static func reconciliationCache() throws {
        let cal = calendar
        let start = date("2025-01-01T17:00:00Z")
        var value = DailyProgress(); value.reconcile(at: start, calendar: cal)
        for offset in stride(from: 0, through: 690, by: 2) {
            value.addWork(seconds: 3600, endingAt: cal.date(byAdding: .day, value: offset, to: start)!, calendar: cal)
        }
        func verify(_ progress: inout DailyProgress, at day: Date, calendar: Calendar) throws {
            // JSON decoding removes only the ephemeral cache, yielding a cold reference.
            var cold = try JSONDecoder().decode(DailyProgress.self, from: JSONEncoder().encode(progress))
            progress.reconcile(at: day, calendar: calendar); cold.reconcile(at: day, calendar: calendar)
            precondition(progress == cold)
            precondition(progress.streakStatus(at: day, calendar: calendar) == cold.streakStatus(at: day, calendar: calendar))
            precondition(progress.tokensRemaining(at: day, calendar: calendar) == cold.tokensRemaining(at: day, calendar: calendar))
        }
        let today = date("2026-11-18T17:00:00Z")
        try verify(&value, at: today, calendar: cal)
        let passes = value.reconciliationPasses
        for _ in 0..<100 { value.reconcile(at: today, calendar: cal) }
        precondition(value.reconciliationPasses == passes, "Unchanged history must not be walked again")
        value.addWork(seconds: 1, endingAt: today, calendar: cal)
        try verify(&value, at: today, calendar: cal)
        precondition(value.reconciliationPasses == passes, "Today's work cannot change historical freezes")
        value.addWork(seconds: 3600, endingAt: date("2026-11-16T17:00:00Z"), calendar: cal)
        try verify(&value, at: today, calendar: cal)
        precondition(value.reconciliationPasses == passes + 1)
        try value.replaceDeclaredWork(segmentID: "late", days: ["2026-11-17": 3600])
        try verify(&value, at: today, calendar: cal)
        try value.replaceDeclaredWork(segmentID: "late", days: [:])
        try verify(&value, at: today, calendar: cal)
        for day in ["2026-10-30T17:00:00Z", "2026-10-31T17:00:00Z", "2026-11-01T17:00:00Z", "2026-11-02T17:00:00Z", "2027-01-01T17:00:00Z"] {
            try verify(&value, at: date(day), calendar: cal)
        }
        try verify(&value, at: today, calendar: DailyProgress.calendar(timeZone: TimeZone(identifier: "Pacific/Auckland")!))
        value.protectionStart = "2026-10-01"
        try verify(&value, at: today, calendar: cal)
        value.frozenDays = []
        try verify(&value, at: today, calendar: cal)
        print("PASS: reconciliation cache parity, invalidation, weekends, DST, months, timezone and historical corrections")
    }
    static func main() throws {
        try reconciliationCache()
        let cal = calendar
        let monday = date("2026-10-19T16:00:00Z")
        var progress = DailyProgress()
        var clock = ProgressClock()
        clock.update(&progress, elapsed: 0, date: monday, working: true, calendar: cal)
        clock.update(&progress, elapsed: 3599, date: monday.addingTimeInterval(3599), working: false, calendar: cal)
        precondition(progress.streak(at: monday, calendar: cal) == 0)
        near(progress.day(at: monday, calendar: cal).workSeconds, 3599)
        // Closed time isn't restored; another session contributes to the same goal.
        clock = ProgressClock()
        clock.update(&progress, elapsed: 0, date: monday, working: true, calendar: cal)
        clock.update(&progress, elapsed: 1, date: monday.addingTimeInterval(1), working: false, calendar: cal)
        precondition(progress.streak(at: monday, calendar: cal) == 1)
        // All non-work phases (survey, resting, awaiting return, suspended, stopped) are excluded.
        for _ in 0..<5 {
            clock.update(&progress, elapsed: 100, date: monday, working: false, calendar: cal)
            clock.update(&progress, elapsed: 200, date: monday, working: false, calendar: cal)
        }
        near(progress.day(at: monday, calendar: cal).workSeconds, 3600)
        // Going backwards between sessions cannot create credit.
        clock.update(&progress, elapsed: 0, date: monday, working: true, calendar: cal)
        clock.update(&progress, elapsed: 60, date: monday.addingTimeInterval(60), working: false, calendar: cal)
        near(progress.day(at: monday, calendar: cal).workSeconds, 3660)
        // Wall-clock jumps cannot increase monotonic credit.
        clock.update(&progress, elapsed: 60, date: monday, working: true, calendar: cal)
        clock.update(&progress, elapsed: 61, date: monday.addingTimeInterval(3600), working: false, calendar: cal)
        near(progress.day(at: monday, calendar: cal).workSeconds, 3661)
        precondition(progress.streak(at: date("2026-10-20T16:00:00Z"), calendar: cal) == 1)
        precondition(progress.streak(at: date("2026-10-21T16:00:00Z"), calendar: cal) == 0)

        // Work resumes after a survey without crediting the survey's duration.
        var transitions = DailyProgress()
        var transitionClock = ProgressClock()
        for (elapsed, working) in [(0.0, true), (30, false), (330, true), (360, false), (960, false)] {
            transitionClock.update(&transitions, elapsed: elapsed, date: monday.addingTimeInterval(elapsed),
                working: working, calendar: cal)
        }
        near(transitions.day(at: monday, calendar: cal).workSeconds, 60)
        var regional = cal
        regional.locale = Locale(identifier: "ar_SA")
        precondition(!DailyProgress.isWeekend(date("2026-10-23T16:00:00Z"), calendar: regional))
        precondition(DailyProgress.isWeekend(date("2026-10-25T16:00:00Z"), calendar: regional))

        var week = DailyProgress()
        for day in 19...23 {
            week.addWork(seconds: 3600, endingAt: date("2026-10-\(day)T16:00:00Z"), calendar: cal)
        }
        for day in 23...26 {
            precondition(week.streak(at: date("2026-10-\(day)T16:00:00Z"), calendar: cal) == 5)
        }
        week.addWork(seconds: 7200, endingAt: date("2026-10-24T16:00:00Z"), calendar: cal)
        precondition(week.streak(at: date("2026-10-25T16:00:00Z"), calendar: cal) == 6)
        week.addWork(seconds: 3600, endingAt: date("2026-10-26T16:00:00Z"), calendar: cal)
        precondition(week.streak(at: date("2026-10-26T16:00:00Z"), calendar: cal) == 7)
        precondition(week.streak(at: date("2026-10-28T16:00:00Z"), calendar: cal) == 0)

        // Completed weekend days count once each; idle weekends remain optional.
        var weekendStart = DailyProgress()
        let saturday = date("2026-10-24T16:00:00Z")
        let sunday = date("2026-10-25T16:00:00Z")
        weekendStart.reconcile(at: saturday, calendar: cal)
        weekendStart.addWork(seconds: 3599, endingAt: saturday, calendar: cal)
        precondition(weekendStart.streak(at: saturday, calendar: cal) == 0)
        weekendStart.addWork(seconds: 1, endingAt: saturday, calendar: cal)
        precondition(weekendStart.streakStatus(at: saturday, calendar: cal) == WorkStreakStatus(count: 1, frozen: false))
        weekendStart.addWork(seconds: 7200, endingAt: sunday, calendar: cal)
        precondition(weekendStart.streak(at: sunday, calendar: cal) == 2)
        weekendStart.reconcile(at: date("2026-10-27T16:00:00Z"), calendar: cal)
        precondition(weekendStart.frozenDays == ["2026-10-26"])
        precondition(weekendStart.streakStatus(at: date("2026-10-27T16:00:00Z"), calendar: cal) == WorkStreakStatus(count: 2, frozen: true))
        precondition(weekendStart.streakStatus(at: date("2026-10-28T16:00:00Z"), calendar: cal).count == 0)
        var sundayStart = DailyProgress()
        sundayStart.addWork(seconds: 3600, endingAt: sunday, calendar: cal)
        precondition(sundayStart.streak(at: sunday, calendar: cal) == 1)

        var midnight = DailyProgress()
        let end = date("2026-10-20T04:30:00Z") // 00:30 local
        midnight.addWork(seconds: 3600, endingAt: end, calendar: cal)
        near(midnight.day(at: monday, calendar: cal).workSeconds, 1800)
        near(midnight.day(at: end, calendar: cal).workSeconds, 1800)
        // Calendar days are 23/25 hours at DST changes, never assumed to be 86400 seconds.
        for (start, end, seconds) in [
            ("2026-03-08T05:00:00Z", "2026-03-09T04:00:00Z", 23.0 * 3600),
            ("2026-11-01T04:00:00Z", "2026-11-02T05:00:00Z", 25.0 * 3600)
        ] {
            var dst = DailyProgress()
            dst.addWork(seconds: seconds + 120, endingAt: date(end).addingTimeInterval(60), calendar: cal)
            near(dst.day(at: date(start), calendar: cal).workSeconds, seconds)
            near(dst.day(at: date(start).addingTimeInterval(-1), calendar: cal).workSeconds, 60)
            near(dst.day(at: date(end), calendar: cal).workSeconds, 60)
        }
        let unchanged = midnight
        for invalid in [Double.nan, .infinity, -1, 0] {
            midnight.addWork(seconds: invalid, endingAt: end, calendar: cal)
        }
        precondition(midnight == unchanged)

        // Exercise the real break policy, including early, late, automatic and stopped breaks.
        var breaks = DailyProgress()
        var policy = BreakPolicy()
        func finish(_ entry: BreakLogEntry) -> Bool {
            let record = entry.record!
            return breaks.completeBreak(id: record.id, seconds: record.actualSeconds!,
                reason: record.endReason, at: monday, calendar: cal)
        }
        _ = policy.begin(at: 0, seconds: 300, activity: "Stretch")
        precondition(!finish(policy.finish(at: 59, reason: "explicit_return")!))
        _ = policy.begin(at: 60, seconds: 300, activity: "Stretch")
        let early = policy.finish(at: 120, reason: "explicit_return")!
        precondition(finish(early))
        precondition(!finish(early))
        precondition(!breaks.completeBreak(id: early.record!.id, seconds: 60, reason: "explicit_return",
            at: end, calendar: cal)) // Duplicate even on another day or after relaunch.
        _ = policy.updateActivity("Walk", at: 121)
        _ = policy.begin(at: 130, seconds: 60, activity: "Walk")
        _ = policy.tick(at: 200)
        precondition(finish(policy.finish(at: 220, reason: "outside_app_input")!))
        _ = policy.begin(at: 230, seconds: 60, activity: "Rest")
        precondition(!finish(policy.finish(at: 400, reason: "session_user_stop")!))
        precondition(breaks.day(at: monday, calendar: cal).completedBreakIDs.count == 2)
        precondition(!breaks.completeBreak(id: "bad", seconds: .infinity,
            reason: "explicit_return", at: monday, calendar: cal))

        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let store = ProgressStore(url: root.appendingPathComponent("progress.json"))
        check(try store.load() == DailyProgress())
        try store.save(breaks)
        let loaded = try store.load()
        precondition(loaded == breaks)
        // A failed write leaves the in-memory ledger intact and permits a later retry.
        let blocker = root.appendingPathComponent("blocker")
        try Data("file".utf8).write(to: blocker)
        let failing = ProgressStore(url: blocker.appendingPathComponent("progress.json"))
        do { try failing.save(breaks); preconditionFailure("Expected write failure") } catch { }
        check(try store.load() == loaded)
        try store.save(progress)
        check(try store.load() == progress)
        // Recovery backs up the exact unreadable contents, then can save new progress.
        let corrupt = Data("unreadable".utf8)
        try corrupt.write(to: store.url)
        do { _ = try store.load(); preconditionFailure("Expected decode failure") } catch { }
        try store.preserveUnreadableFile()
        try store.save(DailyProgress())
        let backup = try FileManager.default.contentsOfDirectory(at: root, includingPropertiesForKeys: nil)
            .first { $0.lastPathComponent.hasPrefix("progress-unreadable-") }!
        check(try Data(contentsOf: backup) == corrupt)
        check(try store.load() == DailyProgress())
        print("Daily progress tests passed")
    }
}
