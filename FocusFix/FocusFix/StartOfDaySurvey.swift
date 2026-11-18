// Local daily context for joining with activity and check-in timestamps.
import Foundation

nonisolated struct StartOfDayResponse: Codable, Equatable {
    var day: String
    var timeZone: String
    var shownAt: Date
    var status = "shown"
    var answeredAt: Date?
    var bedtime: Date?
    var wakeTime: Date?
    var rested: Int?
    var fatigue: Int?
    var stress: Int?
    var version = "focusfix_start_of_day_v1"

    func validate() throws {
        let ratings = [rested, fatigue, stress]
        guard ["shown", "skipped", "answered"].contains(status),
              ratings.compactMap({ $0 }).allSatisfy({ (0...10).contains($0) }) else { throw StartOfDayError.invalid }
        if status == "answered" {
            guard let bedtime, let wakeTime, let answeredAt,
                  ratings.allSatisfy({ $0 != nil }),
                  bedtime < wakeTime, wakeTime <= answeredAt,
                  wakeTime.timeIntervalSince(bedtime) <= 24 * 3600 else { throw StartOfDayError.invalid }
        } else {
            guard ratings.allSatisfy({ $0 == nil }), bedtime == nil, wakeTime == nil else { throw StartOfDayError.invalid }
        }
    }
}

nonisolated enum StartOfDayError: LocalizedError {
    case invalid
    var errorDescription: String? { "Choose all three ratings and a wake time after bedtime, no later than now. Keep the sleep interval under 24 hours." }
}

nonisolated struct StartOfDayStore {
    let url: URL

    static func local() throws -> Self {
        let root = try FileManager.default.url(for: .applicationSupportDirectory,
            in: .userDomainMask, appropriateFor: nil, create: true)
        return Self(url: root.appendingPathComponent("FocusFix/start-of-day.json"))
    }

    static func dayKey(_ date: Date, calendar: Calendar = .current) -> String {
        let parts = calendar.dateComponents([.year, .month, .day], from: date)
        return String(format: "%04d-%02d-%02d", parts.year!, parts.month!, parts.day!)
    }

    func load() throws -> [StartOfDayResponse] {
        guard FileManager.default.fileExists(atPath: url.path) else { return [] }
        let entries = try JSONDecoder().decode([StartOfDayResponse].self, from: Data(contentsOf: url))
        try entries.forEach { try $0.validate() }
        return entries
    }

    func save(_ entries: [StartOfDayResponse]) throws {
        try entries.forEach { try $0.validate() }
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true,
            attributes: [.posixPermissions: 0o700])
        try JSONEncoder().encode(entries).write(to: url, options: [.atomic, .completeFileProtectionUnlessOpen])
        try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: url.path)
    }

    func delete() throws {
        if FileManager.default.fileExists(atPath: url.path) { try FileManager.default.removeItem(at: url) }
    }

    static func csv(_ entries: [StartOfDayResponse]) -> String {
        let formatter = ISO8601DateFormatter()
        func date(_ value: Date?) -> String { value.map { formatter.string(from: $0) } ?? "" }
        func quoted(_ value: String) -> String { "\"" + value.replacingOccurrences(of: "\"", with: "\"\"") + "\"" }
        let header = "question_version,local_day,time_zone,status,shown_at_utc,answered_at_utc,bedtime_utc,wake_time_utc,time_in_bed_hours,rested_0_10,mental_fatigue_0_10,stress_0_10\n"
        return header + entries.map { entry in
            let hours = entry.bedtime.flatMap { bed in entry.wakeTime.map { String(format: "%.3f", locale: Locale(identifier: "en_US_POSIX"), $0.timeIntervalSince(bed) / 3600) } } ?? ""
            return [entry.version, entry.day, quoted(entry.timeZone), entry.status, date(entry.shownAt), date(entry.answeredAt),
                date(entry.bedtime), date(entry.wakeTime), hours, entry.rested.map(String.init) ?? "",
                entry.fatigue.map(String.init) ?? "", entry.stress.map(String.init) ?? ""].joined(separator: ",")
        }.joined(separator: "\n") + (entries.isEmpty ? "" : "\n")
    }
}
