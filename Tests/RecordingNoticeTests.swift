import Foundation

@main struct RecordingNoticeTests {
    static func main() {
        let suite = "focusfix.test.notice.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }
        let notice = RecordingNotice(defaults: defaults)
        precondition(notice.needsAcknowledgement)
        // Merely displaying or cancelling the notice must not record acceptance.
        precondition(RecordingNotice(defaults: defaults).needsAcknowledgement)
        notice.acknowledge()
        precondition(!RecordingNotice(defaults: defaults).needsAcknowledgement)
        for version in [0, RecordingNotice.version + 1] {
            defaults.set(version, forKey: "focusfix.recordingNoticeVersion")
            precondition(notice.needsAcknowledgement)
        }
        print("Recording notice: defaults, explicit acknowledgement and version changes passed.")
    }
}
