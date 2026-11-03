import Foundation

nonisolated struct StudyCheckInConfiguration: Codable, Equatable {
    enum Scope: String, Codable { case synthetic, reviewedStudy = "reviewed_study" }
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
        return requests.filter { date.timeIntervalSince($0) < 86400 }.count < configuration.maximumPer24Hours
    }
    mutating func request(at date: Date, configuration: StudyCheckInConfiguration, calendar: Calendar = .current) -> Bool {
        guard eligible(at: date, configuration: configuration, calendar: calendar) else { return false }
        requests = requests.filter { date.timeIntervalSince($0) < 86400 }
        requests.append(date)
        return true
    }
}
