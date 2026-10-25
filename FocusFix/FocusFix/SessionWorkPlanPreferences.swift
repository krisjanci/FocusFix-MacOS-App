import Foundation
import Combine

@MainActor
final class SessionWorkPlanPreferences: ObservableObject {
    static let shared = SessionWorkPlanPreferences()
    private let defaults: UserDefaults
    @Published var enabled: Bool {
        didSet { defaults.set(enabled, forKey: "focusfix.plan.enabled") }
    }
    @Published private(set) var minutes: Int

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        enabled = defaults.bool(forKey: "focusfix.plan.enabled")
        let saved = defaults.integer(forKey: "focusfix.plan.minutes")
        minutes = (1...480).contains(saved) ? saved : 60
    }

    @discardableResult
    func setMinutes(_ value: Int) -> Bool {
        guard (1...480).contains(value) else { return false }
        minutes = value
        defaults.set(value, forKey: "focusfix.plan.minutes")
        return true
    }

    var snapshot: SessionWorkPlan { SessionWorkPlan(targetMinutes: enabled ? minutes : nil) }
}
