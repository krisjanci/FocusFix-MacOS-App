import Foundation

@MainActor final class QueueFixture {
    let root = FileManager.default.temporaryDirectory.appendingPathComponent("focusfix-queue-tests-\(UUID().uuidString)")
    let participant = UUID().uuidString.lowercased()
    var uploads: [String] = []
    var responseCode = 200
    var offline = false
    var credentialAvailable = true
    var credentialSaves = 0
    var onPrepare: (() -> Void)?
    var onSend: (() -> Void)?
    var sessions: URL { root.appendingPathComponent("Sessions") }
    var sharing: URL { root.appendingPathComponent("Sharing") }
    var environment: SharingEnvironment {
        SharingEnvironment(serviceURL: "https://synthetic.example",
            identity: { self.participant }, readCredential: {
                self.credentialAvailable ? "\(self.participant).\(String(repeating: "a", count: 64))" : nil
            },
            saveCredential: { _ in self.credentialSaves += 1; self.credentialAvailable = true },
            sharingRoot: { self.sharing }, sessionRoot: { self.sessions },
            prepare: { _, destination in
                self.onPrepare?()
                return PreparedUpload(file: destination, sha256: String(repeating: "a", count: 64), bytes: 7)
            }, send: { archive, item, endpoint, _ in
                self.onSend?()
                if self.offline { throw URLError(.notConnectedToInternet) }
                self.uploads.append(item.id)
                let response = HTTPURLResponse(url: endpoint, statusCode: self.responseCode,
                    httpVersion: nil, headerFields: ["Retry-After": "3600"])!
                let data = try JSONSerialization.data(withJSONObject: ["stored": true,
                    "session_id": item.id.lowercased(), "sha256": archive.sha256])
                return (data, response)
            })
    }
    func session(consent: String?, seconds: Double = 60) throws -> String {
        let id = UUID().uuidString
        let directory = sessions.appendingPathComponent(id)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        var metadata: [String: Any] = ["session_id": id, "participant_id": participant,
            "duration_seconds": seconds, "status": "user_stop",
            "started_at_utc": "2026-10-19T10:00:00Z", "ended_at_utc": "2026-10-19T10:01:00Z"]
        if let consent { metadata["sharing_consent_id"] = consent }
        try JSONSerialization.data(withJSONObject: metadata).write(to: directory.appendingPathComponent("session.json"))
        return id
    }
    func cleanup() { try? FileManager.default.removeItem(at: root) }
}

@main struct SharingQueueTests {
    @MainActor static func main() async throws {
        // Missing enrollment explains the disabled toggle and never silently opts in.
        let enrollment = QueueFixture()
        defer { enrollment.cleanup() }
        enrollment.credentialAvailable = false
        let onboarding = SharingController(environment: enrollment.environment)
        precondition(!onboarding.canEnable && !onboarding.enabled)
        precondition(onboarding.setupBlocker?.contains("Save an enrollment credential") == true)
        onboarding.setEnabled(true)
        precondition(!onboarding.enabled && onboarding.notice == onboarding.setupBlocker)
        onboarding.saveCredential("not-an-enrollment-code")
        precondition(!onboarding.canEnable && enrollment.credentialSaves == 0)
        onboarding.saveCredential("\(UUID().uuidString.lowercased()).\(String(repeating: "a", count: 64))")
        precondition(!onboarding.canEnable && enrollment.credentialSaves == 0)
        onboarding.saveCredential("\(enrollment.participant).\(String(repeating: "a", count: 64))")
        precondition(onboarding.canEnable && onboarding.setupBlocker == nil)
        precondition(!onboarding.enabled && enrollment.credentialSaves == 1 && enrollment.uploads.isEmpty)

        var missingURL = enrollment.environment
        missingURL.serviceURL = ""
        let unconfigured = SharingController(environment: missingURL)
        precondition(!unconfigured.canEnable && unconfigured.setupBlocker?.contains("Worker address") == true)
        var failedIdentity = enrollment.environment
        failedIdentity.identity = { throw SharingError.message("Synthetic Keychain failure") }
        let locked = SharingController(environment: failedIdentity)
        precondition(!locked.canEnable && locked.setupBlocker?.contains("Keychain") == true)

        let f = QueueFixture()
        defer { f.cleanup() }
        let c = SharingController(environment: f.environment)
        precondition(!c.enabled && c.canEnable)
        let old = try f.session(consent: nil)
        await c.retryPending()?.value
        precondition(f.uploads.isEmpty)
        c.setEnabled(true)
        await c.retryPending()?.value
        precondition(f.uploads.isEmpty && c.status(for: old) == "Local only")
        let first = try f.session(consent: c.consentID)
        await c.retryPending()?.value
        precondition(f.uploads == [first] && c.status(for: first) == "Uploaded")
        let restored = SharingController(environment: f.environment)
        precondition(restored.participantID == c.participantID && restored.enabled)
        await restored.retryPending()?.value
        precondition(f.uploads == [first]) // Local receipt survives restart.

        let previousConsent = c.consentID
        c.setEnabled(false)
        let optedOut = try f.session(consent: previousConsent)
        c.setEnabled(true)
        await c.retryPending()?.value
        precondition(f.uploads == [first] && c.status(for: optedOut) == "Local only")
        let long = try f.session(consent: c.consentID, seconds: 10801)
        await c.retryPending()?.value
        precondition(c.status(for: long).contains("Over 180") && f.uploads == [first])

        // Opt-out during compression prevents even the first network request.
        let cancelled = try f.session(consent: c.consentID)
        f.onPrepare = { c.setEnabled(false) }
        await c.retryPending()?.value
        precondition(!c.enabled && f.uploads == [first] && c.status(for: cancelled).contains("Sharing stopped"))
        f.onPrepare = nil
        c.setEnabled(true)
        await c.retryPending()?.value
        precondition(f.uploads == [first])

        // Offline failure remains queued, with durable backoff rather than a tight loop.
        let pending = try f.session(consent: c.consentID)
        f.offline = true
        await c.retryPending()?.value
        let waiting = c.settings.items.first { $0.id == pending }!
        precondition(waiting.state == "waiting" && waiting.retryAfter > Date())
        f.offline = false
        let offlineRestart = SharingController(environment: f.environment)
        precondition(offlineRestart.settings.items.first { $0.id == pending }!.state == "waiting")
        // Advance the persisted retry clock in this temporary test directory only.
        var state = offlineRestart.settings
        let index = state.items.firstIndex { $0.id == pending }!
        state.items[index].retryAfter = .distantPast
        try JSONEncoder().encode(state).write(to: f.sharing.appendingPathComponent("state.json"))
        let reconnect = SharingController(environment: f.environment)
        await reconnect.retryPending()?.value
        precondition(f.uploads == [first, pending] && reconnect.status(for: pending) == "Uploaded")

        // Server quota delay is respected, including manual retry clicks.
        let limited = try f.session(consent: reconnect.consentID)
        f.responseCode = 429
        await reconnect.retryPending()?.value
        let count = f.uploads.count
        precondition(reconnect.status(for: limited).contains("Daily upload limit"))
        await reconnect.retryPending()?.value
        precondition(f.uploads.count == count)
        reconnect.cancelSession(limited)
        precondition(reconnect.status(for: limited).contains("cancelled"))

        // An endpoint change requires renewed consent; corrupt settings fail closed.
        var changedEnvironment = f.environment
        changedEnvironment.serviceURL = "https://different.example"
        let changed = SharingController(environment: changedEnvironment)
        precondition(!changed.enabled)
        try Data("corrupt".utf8).write(to: f.sharing.appendingPathComponent("state.json"))
        let corrupt = SharingController(environment: f.environment)
        precondition(!corrupt.enabled && !corrupt.canEnable)
        precondition(corrupt.setupBlocker?.contains("Sharing preferences") == true)
        print("Sharing queue tests passed: enrollment guidance, opt-in, no backfill, cancellation, restart, offline retry, quota delay and fail-closed settings")
    }
}
