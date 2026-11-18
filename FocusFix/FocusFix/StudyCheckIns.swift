import Foundation

enum CheckInPromptCopy {
    static let title = "Time for a check-in"
    static let question = "Would you like to check in on your fatigue and productivity?"
}


nonisolated struct StudyCheckInConfiguration: Codable, Equatable {
    enum Scope: String, Codable { case personal, synthetic, reviewedStudy = "reviewed_study" }
    let version: String
    let scope: Scope
    let reviewReference: String
    let consentScopeVersion: String
    let minimumSpacingSeconds: Double
    let recallSeconds: Double
    let maximumPer24Hours: Int
    let quietLocalHours: [Int]
    var valid: Bool {
        !version.isEmpty && !reviewReference.isEmpty && !consentScopeVersion.isEmpty
            && minimumSpacingSeconds.isFinite && minimumSpacingSeconds >= 60
            && recallSeconds.isFinite && recallSeconds > 0 && recallSeconds <= minimumSpacingSeconds
            && (1...24).contains(maximumPer24Hours) && quietLocalHours.allSatisfy { (0...23).contains($0) }
    }
    static func personal(promptsPerDay: Int) -> Self {
        Self(version: "personal.random.v1", scope: .personal,
             reviewReference: "Personal self-tracking, not study enrollment", consentScopeVersion: "personal.v1",
             minimumSpacingSeconds: 1800, recallSeconds: 300,
             maximumPer24Hours: min(5, max(1, promptsPerDay)), quietLocalHours: [])
    }
    static let synthetic = Self(version: "synthetic.demo.v1", scope: .synthetic,
        reviewReference: "synthetic test only", consentScopeVersion: "synthetic-not-consent",
        minimumSpacingSeconds: 600, recallSeconds: 300, maximumPer24Hours: 6, quietLocalHours: [0, 1, 2, 3, 4, 5])
    static var bundled: Self? {
        guard let url = Bundle.main.url(forResource: "StudyCheckInConfiguration", withExtension: "json"),
              let data = try? Data(contentsOf: url), let config = try? JSONDecoder().decode(Self.self, from: data),
              config.valid, config.scope == .reviewedStudy else { return nil }
        return config
    }
}
nonisolated struct StudyPromptSnapshot: Codable, Equatable {
    let id: String
    let scheduleVersion: String
    let configurationScope: StudyCheckInConfiguration.Scope
    let recordingID: UUID
    let contextAtPrompt: ActivityContext
    let requestedElapsed: Double
    let recallStart: Double
    let recallEnd: Double
    let requestedAtUTC: Date
}
nonisolated struct StudyPromptLogEntry: Codable {
    let prompt: StudyPromptSnapshot
    let action: String
    let elapsed: Double
    let recordedAtUTC: Date
}
nonisolated struct StudyPromptBudget: Codable {
    private(set) var requests: [Date] = []
    private var blocked = false
    static var unavailable: Self { var value = Self(); value.blocked = true; return value }
    func eligible(at date: Date, configuration: StudyCheckInConfiguration, calendar: Calendar = .current) -> Bool {
        guard !blocked, configuration.valid, !configuration.quietLocalHours.contains(calendar.component(.hour, from: date)) else { return false }
        if let last = requests.last, date.timeIntervalSince(last) < configuration.minimumSpacingSeconds { return false }
        if configuration.scope == .personal {
            return requests.filter { calendar.isDate($0, inSameDayAs: date) }.count < configuration.maximumPer24Hours
        }
        return requests.filter { date.timeIntervalSince($0) < 86400 }.count < configuration.maximumPer24Hours
    }
    mutating func request(at date: Date, configuration: StudyCheckInConfiguration, calendar: Calendar = .current) -> Bool {
        guard eligible(at: date, configuration: configuration, calendar: calendar) else { return false }
        requests = requests.filter {
            date.timeIntervalSince($0) < 86400 ||
                (configuration.scope == .personal && calendar.isDate($0, inSameDayAs: date))
        }
        requests.append(date)
        return true
    }
}

// A saved local-day plan survives relaunches, breaks and recording restarts.
// Missed opportunities coalesce into one request, never a burst of catch-up prompts.
nonisolated struct PersonalSurveySchedule: Codable {
    let dayStart: Date
    let timeZone: String
    let target: Int
    private(set) var dates: [Date]

    func matches(date: Date, target: Int, calendar: Calendar) -> Bool {
        dayStart == calendar.startOfDay(for: date) && timeZone == calendar.timeZone.identifier && self.target == target
    }

    static func make(at date: Date, target: Int, requests: [Date], calendar: Calendar = .current,
                     random: () -> Double = { Double.random(in: 0..<1) }) -> Self {
        let target = min(5, max(1, target))
        let start = calendar.startOfDay(for: date)
        let end = calendar.date(byAdding: .day, value: 1, to: start)!
        let used = requests.filter { calendar.isDate($0, inSameDayAs: date) }.count
        let earliest = max(date.addingTimeInterval(60), (requests.max() ?? .distantPast).addingTimeInterval(1800))
        let available = end.timeIntervalSince(earliest)
        let count = min(max(0, target - used), available > 0 ? Int(ceil(available / 1800)) : 0)
        let slack = max(0, available - Double(max(0, count - 1)) * 1800)
        // Stratify the free time, then insert the mandatory gaps. Even extreme
        // random draws cannot put adjacent opportunities within 30 minutes.
        let dates = (0..<count).map { index in
            earliest.addingTimeInterval(Double(index) * 1800 +
                (Double(index) + min(0.999999, max(0, random()))) * slack / Double(count))
        }
        return Self(dayStart: start, timeZone: calendar.timeZone.identifier, target: target, dates: dates)
    }

    var next: Date? { dates.first }
    mutating func requested(at date: Date) { dates.removeAll { $0 <= date } }
}
