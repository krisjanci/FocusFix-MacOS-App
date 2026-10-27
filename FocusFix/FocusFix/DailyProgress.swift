// MARK: - FF: PROGRESS
// Local rewards are independent of recordings, exports, and research sharing.
import Foundation

struct ProgressDay: Codable, Equatable {
    var workSeconds: Double = 0
    var completedBreakIDs: Set<String> = []
}

struct DailyProgress: Codable, Equatable {
    static let goalSeconds: Double = 3600
    var version = 1
    private(set) var days: [String: ProgressDay] = [:]
    var protectionStart: String?
    var reconciledThrough: String?
    var frozenDays: Set<String> = []

    enum CodingKeys: String, CodingKey { case version, days, protectionStart, reconciledThrough, frozenDays }
    init() {}
    init(from decoder: Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        version = try values.decode(Int.self, forKey: .version)
        days = try values.decode([String: ProgressDay].self, forKey: .days)
        protectionStart = try values.decodeIfPresent(String.self, forKey: .protectionStart)
        reconciledThrough = try values.decodeIfPresent(String.self, forKey: .reconciledThrough)
        frozenDays = try values.decodeIfPresent(Set<String>.self, forKey: .frozenDays) ?? []
    }

    mutating func reconcile(at date: Date, calendar: Calendar) {
        let today = Self.key(for: date, calendar: calendar)
        if protectionStart == nil { protectionStart = today }
        guard let start = protectionStart else { return }
        // Rebuild deterministically: late offline work replaces a freeze, returning its token.
        frozenDays = []
        var cursor = calendar.startOfDay(for: date)
        while Self.key(for: cursor, calendar: calendar) > start {
            guard let prior = calendar.date(byAdding: .day, value: -1, to: cursor) else { return }
            cursor = prior
        }
        var alive = streak(at: cursor, calendar: calendar) > 0
        var previousFrozen: String?
        var spent: [String: Int] = [:]
        while cursor < calendar.startOfDay(for: date) {
            let key = Self.key(for: cursor, calendar: calendar)
            let month = String(key.prefix(7))
            let yesterday = calendar.date(byAdding: .day, value: -1, to: cursor)!
            if !Self.isWeekend(cursor, calendar: calendar) {
                if day(at: cursor, calendar: calendar).workSeconds >= Self.goalSeconds { alive = true }
                else if alive && previousFrozen != Self.key(for: yesterday, calendar: calendar) && spent[month, default: 0] < 3 {
                    frozenDays.insert(key); previousFrozen = key; spent[month, default: 0] += 1
                } else { alive = false }
            }
            cursor = calendar.date(byAdding: .day, value: 1, to: cursor)!
        }
        reconciledThrough = today
    }

    func tokensRemaining(at date: Date, calendar: Calendar) -> Int {
        let month = String(Self.key(for: date, calendar: calendar).prefix(7))
        return max(0, 3 - frozenDays.filter { $0.hasPrefix(month) }.count)
    }

    static func calendar(timeZone: TimeZone = .current) -> Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = timeZone
        return calendar
    }

    // The goal follows Monday–Friday even in regions with different weekend conventions.
    static func isWeekend(_ date: Date, calendar: Calendar) -> Bool {
        let weekday = calendar.component(.weekday, from: date)
        return weekday == 1 || weekday == 7
    }

    static func key(for date: Date, calendar: Calendar) -> String {
        let parts = calendar.dateComponents([.year, .month, .day], from: date)
        return String(format: "%04d-%02d-%02d", parts.year!, parts.month!, parts.day!)
    }

    func day(at date: Date, calendar: Calendar) -> ProgressDay {
        days[Self.key(for: date, calendar: calendar)] ?? ProgressDay()
    }

    // Duration comes from a monotonic clock. Calendar boundaries only allocate that duration.
    mutating func addWork(seconds: Double, endingAt end: Date, calendar: Calendar) {
        guard seconds.isFinite, seconds > 0 else { return }
        var cursor = end.addingTimeInterval(-seconds)
        while cursor < end {
            guard let interval = calendar.dateInterval(of: .day, for: cursor) else { return }
            let boundary = min(end, interval.end)
            guard boundary > cursor else { return }
            let key = Self.key(for: cursor, calendar: calendar)
            days[key, default: ProgressDay()].workSeconds += boundary.timeIntervalSince(cursor)
            cursor = boundary
        }
    }

    @discardableResult
    mutating func completeBreak(id: String, seconds: Double, reason: String,
                                at date: Date, calendar: Calendar) -> Bool {
        guard seconds.isFinite, seconds >= 60,
              reason == "explicit_return" || reason == "outside_app_input",
              !days.values.contains(where: { $0.completedBreakIDs.contains(id) }) else { return false }
        let key = Self.key(for: date, calendar: calendar)
        days[key, default: ProgressDay()].completedBreakIDs.insert(id)
        return true
    }

    // Today remains provisional; only earlier missed weekdays end the current streak.
    func streak(at date: Date, calendar: Calendar) -> Int {
        var cursor = calendar.startOfDay(for: date)
        var count = 0
        let today = cursor
        while true {
            if !Self.isWeekend(cursor, calendar: calendar) {
                if day(at: cursor, calendar: calendar).workSeconds >= Self.goalSeconds { count += 1 }
                else if cursor != today && !frozenDays.contains(Self.key(for: cursor, calendar: calendar)) { return count }
            }
            guard let previous = calendar.date(byAdding: .day, value: -1, to: cursor) else { return count }
            cursor = previous
        }
    }

    var isValid: Bool {
        version == 1 && days.values.allSatisfy { $0.workSeconds.isFinite && $0.workSeconds >= 0 }
    }
}

// Ephemeral state is deliberately never restored: relaunch must not invent work while closed.
struct ProgressClock {
    private var lastElapsed: Double?
    private var wasWorking = false

    @discardableResult
    mutating func update(_ progress: inout DailyProgress, elapsed: Double, date: Date,
                         working: Bool, calendar: Calendar) -> Double {
        guard elapsed.isFinite, elapsed >= 0 else { return 0 }
        var credited: Double = 0
        if let lastElapsed, elapsed >= lastElapsed, wasWorking {
            credited = elapsed - lastElapsed
            progress.addWork(seconds: credited, endingAt: date, calendar: calendar)
        }
        lastElapsed = elapsed
        wasWorking = working
        return credited
    }
}

struct ProgressStore {
    let url: URL

    static func local() throws -> ProgressStore {
        let root = try FileManager.default.url(for: .applicationSupportDirectory,
            in: .userDomainMask, appropriateFor: nil, create: true)
        return ProgressStore(url: root.appendingPathComponent("FocusFix/progress.json"))
    }

    func load() throws -> DailyProgress {
        guard FileManager.default.fileExists(atPath: url.path) else { return DailyProgress() }
        let data = try Data(contentsOf: url)
        let progress = try JSONDecoder().decode(DailyProgress.self, from: data)
        guard progress.isValid else {
            throw NSError(domain: "FocusFix.Progress", code: 1,
                userInfo: [NSLocalizedDescriptionKey: "The saved progress format is unsupported or invalid."])
        }
        return progress
    }

    // Preserve unreadable data before permitting a fresh ledger to replace it.
    func preserveUnreadableFile() throws {
        let backup = url.deletingLastPathComponent()
            .appendingPathComponent("progress-unreadable-\(UUID().uuidString).json")
        try FileManager.default.copyItem(at: url, to: backup)
    }

    func save(_ progress: DailyProgress) throws {
        guard progress.isValid else {
            throw NSError(domain: "FocusFix.Progress", code: 2,
                userInfo: [NSLocalizedDescriptionKey: "Progress could not be saved because its values are invalid."])
        }
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try JSONEncoder().encode(progress).write(to: url, options: .atomic)
    }
}
