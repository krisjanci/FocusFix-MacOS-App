// MARK: - FF: SURVEYS
// Saves local survey choices independently of research enrollment and sharing.

import Foundation
import Combine

@MainActor
final class SurveyPreferences: ObservableObject {
    static let shared = SurveyPreferences()
    private let defaults: UserDefaults
    private let configuration: StudyCheckInConfiguration?
    @Published private(set) var studyCheckInsEnabled: Bool
    var onRevoke: (() -> Void)?
    var activeConfiguration: StudyCheckInConfiguration? { studyCheckInsEnabled ? configuration : nil }
    func setStudyCheckInsEnabled(_ enabled: Bool) {
        defaults.set(enabled, forKey: "focusfix.studyCheckIns.enabled")
        if enabled {
            defaults.set(configuration?.consentScopeVersion ?? "", forKey: "focusfix.studyCheckIns.acceptedScope")
            defaults.set(Date(), forKey: "focusfix.studyCheckIns.acknowledgedAt")
        }
        defaults.set(1, forKey: "focusfix.studyCheckIns.scopeVersion")
        studyCheckInsEnabled = enabled
        if !enabled { onRevoke?() }
    }
    func loadBudget() -> StudyPromptBudget {
        guard let data = defaults.data(forKey: "focusfix.studyCheckIns.budget") else { return StudyPromptBudget() }
        // An unreadable budget fails closed for this launch rather than resetting the rate.
        return (try? JSONDecoder().decode(StudyPromptBudget.self, from: data)) ?? .unavailable
    }
    func saveBudget(_ budget: StudyPromptBudget) throws {
        defaults.set(try JSONEncoder().encode(budget), forKey: "focusfix.studyCheckIns.budget")
    }
    @Published var beforeSession: Bool {
        didSet { defaults.set(beforeSession, forKey: "focusfix.surveys.beforeSession") }
    }
    @Published var beforeBreak: Bool {
        didSet { defaults.set(beforeBreak, forKey: "focusfix.surveys.beforeBreak") }
    }
    @Published var duringWork: Bool {
        didSet { defaults.set(duringWork, forKey: "focusfix.surveys.duringWork") }
    }

    // Historic switches are retained, but never activate the new study scope.
    init(defaults: UserDefaults = .standard, configuration: StudyCheckInConfiguration? = StudyCheckInConfiguration.bundled, allowSynthetic: Bool = false) {
        self.defaults = defaults
        let acceptedConfiguration = configuration.flatMap { $0.valid && ($0.scope == .reviewedStudy || allowSynthetic) ? $0 : nil }
        self.configuration = acceptedConfiguration
        studyCheckInsEnabled = defaults.integer(forKey: "focusfix.studyCheckIns.scopeVersion") == 1
            && defaults.bool(forKey: "focusfix.studyCheckIns.enabled")
            && defaults.string(forKey: "focusfix.studyCheckIns.acceptedScope") == (acceptedConfiguration?.consentScopeVersion ?? "")
        beforeSession = defaults.object(forKey: "focusfix.surveys.beforeSession") as? Bool ?? true
        beforeBreak = defaults.object(forKey: "focusfix.surveys.beforeBreak") as? Bool ?? true
        duringWork = defaults.object(forKey: "focusfix.surveys.duringWork") as? Bool ?? true
    }

    // Return a value copy; later preference edits only affect future sessions.
    var snapshot: SurveyOptions {
        guard activeConfiguration != nil else { return SurveyOptions(beforeSession: false, beforeBreak: false, duringWork: false) }
        return SurveyOptions(beforeSession: beforeSession, beforeBreak: beforeBreak, duringWork: duringWork)
    }
}
