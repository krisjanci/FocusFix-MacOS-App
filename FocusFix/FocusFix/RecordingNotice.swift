// MARK: - FF: PRIVACY
// A local recording acknowledgement is separate from study consent and research sharing.

import Foundation

struct RecordingNotice {
    static let version = 2
    private let defaults: UserDefaults
    private static let key = "focusfix.recordingNoticeVersion"

    init(defaults: UserDefaults = .standard) { self.defaults = defaults }

    // Show the notice again if its contents change; missing or unexpected values fail closed.
    var needsAcknowledgement: Bool { defaults.integer(forKey: Self.key) != Self.version }

    // Save only after the person explicitly chooses I understand. This never enables sharing.
    func acknowledge() { defaults.set(Self.version, forKey: Self.key) }
}
