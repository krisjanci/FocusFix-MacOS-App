import Foundation

struct FocusBadge: Identifiable, Equatable {
    let id: String
    let name: String
    let days: Int
    let rank: Int
    var description: String { days == 0 ? "Joined FocusFix." : "Completed a \(days)-day work streak." }
    var requirement: String { days == 0 ? "Create or sign in to a FocusFix account." : "Complete a \(days)-day work streak to earn this badge." }
    static let all: [FocusBadge] = [FocusBadge(id: "joined", name: "Joined FocusFix", days: 0, rank: 0)] +
        [5, 10, 20, 30, 50, 75, 100].enumerated().map {
            FocusBadge(id: "work-\($0.element)", name: $0.element == 5 ? "Full Week" : "\($0.element) Days", days: $0.element, rank: $0.offset + 1)
        }
}

struct BadgeAwards: Codable, Equatable {
    var initialized = false
    var earned: Set<String> = []
    var unread: Set<String> = []
    var pending: [String] = []

    mutating func award(streak: Int, joinedKey: String?, historical: Bool = false) -> [FocusBadge] {
        var added: [FocusBadge] = []
        for badge in FocusBadge.all {
            guard let key = badge.days == 0 ? joinedKey : badge.id,
                  badge.days == 0 || streak >= badge.days,
                  earned.insert(key).inserted else { continue }
            unread.insert(key)
            if !historical { pending.append(key); added.append(badge) }
        }
        initialized = true
        return added
    }

    // Replay historical reconciliations, rather than applying today's freeze allocation to past streaks.
    static func historicalBest(_ progress: DailyProgress, calendar: Calendar) -> Int {
        let formatter = DateFormatter()
        formatter.calendar = calendar; formatter.timeZone = calendar.timeZone
        formatter.dateFormat = "yyyy-MM-dd"; formatter.locale = Locale(identifier: "en_US_POSIX")
        var best = 0
        for key in progress.days.keys.sorted() where progress.days[key]!.workSeconds >= DailyProgress.goalSeconds {
            guard let date = formatter.date(from: key) else { continue }
            var snapshot = progress
            snapshot.reconcile(at: date, calendar: calendar)
            best = max(best, snapshot.streak(at: date, calendar: calendar))
            if best >= 100 { break }
        }
        return best
    }
}
