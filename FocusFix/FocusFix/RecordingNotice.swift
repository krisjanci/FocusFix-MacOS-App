// MARK: - FF: PRIVACY
// A local recording acknowledgement is separate from study consent and research sharing.

import Foundation

struct RecordingNotice {
    static let version = 4
    private let defaults: UserDefaults
    private static let key = "focusfix.recordingNoticeVersion"
    private static let enabledKey = "focusfix.recordingEnabled"
    private static let offeredKey = "focusfix.recordingOfferedVersion"

    init(defaults: UserDefaults = .standard) { self.defaults = defaults }

    // Show the notice again if its contents change; missing or unexpected values fail closed.
    var needsAcknowledgement: Bool { defaults.integer(forKey: Self.key) != Self.version }
    var enabled: Bool { !needsAcknowledgement && defaults.bool(forKey: Self.enabledKey) }
    var needsFirstLaunchChoice: Bool { defaults.integer(forKey: Self.offeredKey) != Self.version }

    // Save only after the person explicitly chooses I understand. This never enables sharing.
    func acknowledge() {
        defaults.set(Self.version, forKey: Self.key)
        defaults.set(true, forKey: Self.enabledKey)
        defaults.set(Self.version, forKey: Self.offeredKey)
    }
    func decline() {
        defaults.set(false, forKey: Self.enabledKey)
        defaults.set(Self.version, forKey: Self.offeredKey)
    }
}
