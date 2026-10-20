// MARK: - FF: SURVEYS
// Saves local survey choices independently of research enrollment and sharing.

import Foundation
import Combine

@MainActor
final class SurveyPreferences: ObservableObject {
    static let shared = SurveyPreferences()
    private let defaults: UserDefaults
    @Published var beforeSession: Bool {
        didSet { defaults.set(beforeSession, forKey: "focusfix.surveys.beforeSession") }
    }
    @Published var beforeBreak: Bool {
        didSet { defaults.set(beforeBreak, forKey: "focusfix.surveys.beforeBreak") }
    }
    @Published var duringWork: Bool {
        didSet { defaults.set(duringWork, forKey: "focusfix.surveys.duringWork") }
    }

    // Keep all existing surveys enabled unless the user has explicitly changed a switch.
    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        beforeSession = defaults.object(forKey: "focusfix.surveys.beforeSession") as? Bool ?? true
        beforeBreak = defaults.object(forKey: "focusfix.surveys.beforeBreak") as? Bool ?? true
        duringWork = defaults.object(forKey: "focusfix.surveys.duringWork") as? Bool ?? true
    }

    // Return a value copy; later preference edits only affect future sessions.
    var snapshot: SurveyOptions {
        SurveyOptions(beforeSession: beforeSession, beforeBreak: beforeBreak, duringWork: duringWork)
    }
}
