import Foundation

@main
struct BadgeAwardsTests {
    static func main() throws {
        let thresholds = [5, 10, 20, 30, 50, 75, 100]
        precondition(FocusBadge.all.count == 8)
        for threshold in thresholds {
            var awards = BadgeAwards()
            _ = awards.award(streak: threshold - 1, joinedKey: nil)
            precondition(!awards.earned.contains("work-\(threshold)"))
            let added = awards.award(streak: threshold, joinedKey: nil)
            precondition(added.map(\.days) == [threshold])
            precondition(awards.unread.contains("work-\(threshold)"))
            let snapshot = awards
            precondition(awards.award(streak: threshold, joinedKey: nil).isEmpty)
            precondition(snapshot == awards)
            _ = awards.award(streak: 0, joinedKey: nil)
            precondition(awards.earned.contains("work-\(threshold)"), "A broken streak must not revoke badges")
        }
        var awards = BadgeAwards()
        let added = awards.award(streak: 100, joinedKey: "joined|account-a")
        precondition(added.map(\.days) == [0, 5, 10, 20, 30, 50, 75, 100])
        precondition(awards.pending.count == 8)
        precondition(awards.award(streak: 100, joinedKey: "joined|account-a").isEmpty)
        precondition(awards.award(streak: 0, joinedKey: "joined|account-b").map(\.id) == ["joined"])
        precondition(awards.earned.contains("joined|account-a") && awards.earned.contains("joined|account-b"))
        let restoredAwards = try JSONDecoder().decode(BadgeAwards.self, from: JSONEncoder().encode(awards))
        precondition(restoredAwards == awards)
        var historical = BadgeAwards()
        precondition(historical.award(streak: 100, joinedKey: nil, historical: true).isEmpty)
        precondition(historical.pending.isEmpty && historical.unread.count == 7 && historical.initialized)

        let calendar = DailyProgress.calendar(timeZone: TimeZone(identifier: "America/New_York")!)
        let start = ISO8601DateFormatter().date(from: "2026-10-19T17:00:00Z")!
        func day(_ offset: Int) -> Date { calendar.date(byAdding: .day, value: offset, to: start)! }
        var progress = DailyProgress()
        progress.reconcile(at: start, calendar: calendar)
        for offset in 0..<5 { progress.addWork(seconds: 3600, endingAt: day(offset), calendar: calendar) }
        precondition(BadgeAwards.historicalBest(progress, calendar: calendar) == 5)
        // Completed weekends add days, while a rest weekend does not add to the total.
        progress.addWork(seconds: 3600, endingAt: day(5), calendar: calendar)
        progress.addWork(seconds: 3600, endingAt: day(7), calendar: calendar)
        precondition(BadgeAwards.historicalBest(progress, calendar: calendar) == 7)
        // A frozen weekday protects continuity but never counts as an earned work day.
        progress.addWork(seconds: 3600, endingAt: day(9), calendar: calendar)
        precondition(BadgeAwards.historicalBest(progress, calendar: calendar) == 8)
        progress.reconcile(at: day(18), calendar: calendar)
        precondition(progress.streak(at: day(18), calendar: calendar) == 0)
        precondition(BadgeAwards.historicalBest(progress, calendar: calendar) == 8, "Historical badges survive a later broken streak")
        var short = DailyProgress()
        short.addWork(seconds: 3599, endingAt: start, calendar: calendar)
        precondition(BadgeAwards.historicalBest(short, calendar: calendar) == 0)
        // Adding badge storage must not require changes to the existing progress format.
        let restored = try JSONDecoder().decode(DailyProgress.self, from: JSONEncoder().encode(progress))
        precondition(restored == progress)
        // Cached and cold ledgers must award the same badges across DST/month
        // boundaries and after late corrections that change historical continuity.
        var cachedHistory = DailyProgress()
        cachedHistory.reconcile(at: start, calendar: calendar)
        for offset in 0..<35 {
            try cachedHistory.replaceDeclaredWork(segmentID: "fixture-\(offset)",
                days: [DailyProgress.key(for: day(offset), calendar: calendar): 3600])
        }
        for offset in [11, 13, 14, 34, 45] {
            cachedHistory.reconcile(at: day(offset), calendar: calendar)
            let coldHistory = try JSONDecoder().decode(DailyProgress.self, from: JSONEncoder().encode(cachedHistory))
            var cachedAwards = BadgeAwards(), coldAwards = BadgeAwards()
            let cachedBest = max(BadgeAwards.historicalBest(cachedHistory, calendar: calendar), cachedHistory.streakStatus(at: day(offset), calendar: calendar).count)
            let coldBest = max(BadgeAwards.historicalBest(coldHistory, calendar: calendar), coldHistory.streakStatus(at: day(offset), calendar: calendar).count)
            _ = cachedAwards.award(streak: cachedBest, joinedKey: nil)
            _ = coldAwards.award(streak: coldBest, joinedKey: nil)
            precondition(cachedAwards == coldAwards)
            try cachedHistory.replaceDeclaredWork(segmentID: "fixture-\(offset)", days: [:])
        }
        print("Badge award tests passed")
    }
}
