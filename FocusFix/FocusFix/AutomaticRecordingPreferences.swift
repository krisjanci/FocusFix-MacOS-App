import Foundation
import Combine

// No account, old acknowledgement, OS permission or login item enables this choice.
@MainActor final class AutomaticRecordingPreferences: ObservableObject {
    static let shared = AutomaticRecordingPreferences()
    static let scopeVersion = 1
    private let defaults: UserDefaults
    @Published private(set) var optedIn: Bool
    @Published private(set) var userPaused: Bool
    @Published private(set) var generation = UUID()
    var onChange: (() -> Void)?
    var acknowledgedAt: Date? { defaults.object(forKey: "focusfix.automatic.acknowledgedAt") as? Date }
    var enabled: Bool { optedIn && RecordingNotice(defaults: defaults).enabled }

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        optedIn = defaults.integer(forKey: "focusfix.automatic.scopeVersion") == Self.scopeVersion
            && defaults.bool(forKey: "focusfix.automatic.enabled")
        userPaused = defaults.bool(forKey: "focusfix.automatic.userPaused")
    }
    // Call only from the explicit, scope-specific confirmation.
    func enable(at date: Date = Date()) {
        guard RecordingNotice(defaults: defaults).enabled else { return }
        defaults.set(Self.scopeVersion, forKey: "focusfix.automatic.scopeVersion")
        defaults.set(date, forKey: "focusfix.automatic.acknowledgedAt")
        defaults.set(true, forKey: "focusfix.automatic.enabled")
        optedIn = true
        generation = UUID()
        onChange?()
    }
    func disable() {
        defaults.set(false, forKey: "focusfix.automatic.enabled")
        optedIn = false
        generation = UUID() // Invalidates pending automatic callbacks before stopping capture.
        onChange?()
    }
    func setUserPaused(_ paused: Bool, notify: Bool = true) {
        defaults.set(paused, forKey: "focusfix.automatic.userPaused")
        userPaused = paused
        generation = UUID()
        if notify { onChange?() }
    }
}
