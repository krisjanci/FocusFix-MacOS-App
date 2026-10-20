// MARK: - FF: SHARING
// Manages explicit opt-in, the persistent upload queue and retries. Original local sessions are never deleted after upload.

import Foundation
import Combine

@MainActor
final class SharingController: ObservableObject {
    static let shared = SharingController(environment: .live)
    @Published private(set) var participantID = ""
    @Published private(set) var settings = SharingSettings()
    @Published private(set) var hasCredential = false
    @Published private(set) var notice = "Sharing is off. Recordings stay on this Mac."
    @Published private(set) var uploading = false
    private var root: URL?
    private var task: Task<Void, Never>?
    private var timer: Timer?
    private var storageReady = false
    private var generation = UUID()
    private let environment: SharingEnvironment

    // Whether a sharing opt-in is saved.
    var enabled: Bool { settings.consentID != nil }
    // Release builds cannot opt in, read enrollment secrets or resume a development upload queue.
    var researchAvailable: Bool { environment.researchUploadsAllowed }
    // Expose the consent marker only while all upload prerequisites are available.
    var consentID: String? { canEnable ? settings.consentID : nil }
    // Whether this build contains a valid HTTPS receiver origin.
    var configured: Bool { UploadPolicy.endpoint(environment.serviceURL) != nil }
    // Require working storage, enrollment, identity and configuration before allowing sharing.
    var canEnable: Bool { researchAvailable && storageReady && configured && hasCredential && !participantID.isEmpty }

    // Explain a disabled switch without treating local setup as proof the server is ready.
    var setupBlocker: String? {
        if !researchAvailable { return "This build is local-only. Research uploads and enrollment are unavailable." }
        if !configured { return "This app build is not connected to the upload service. Add the Worker address and rebuild the app." }
        if participantID.isEmpty { return "The participant ID could not be read from Keychain. Allow FocusFix access, then quit and reopen the app." }
        if !storageReady { return "Sharing preferences are unavailable. Resolve the error shown below, then quit and reopen the app. Local recording still works." }
        if !hasCredential { return "Save an enrollment credential before turning on sharing. Open Research enrollment below. You don't need to record a session first." }
        return nil
    }

    // Load identity and queue state; fail closed on invalid state or a changed service URL.
    init(environment: SharingEnvironment) {
        self.environment = environment
        // Leave the test installation's Keychain and queue untouched when running a local-only build.
        guard researchAvailable else {
            notice = "Local-only build. No research data is uploaded."
            return
        }
        do {
            participantID = try environment.identity()
            hasCredential = try environment.readCredential() != nil
            let directory = try environment.sharingRoot()
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true,
                                                    attributes: [.posixPermissions: 0o700])
            root = directory
            let state = directory.appendingPathComponent("state.json")
            if FileManager.default.fileExists(atPath: state.path) {
                settings = try JSONDecoder().decode(SharingSettings.self, from: Data(contentsOf: state))
            }
            // Consent never silently follows a build configured for another service.
            if settings.serviceURL != environment.serviceURL {
                settings.consentID = nil
                for index in settings.items.indices where settings.items[index].uploadedAt == nil {
                    settings.items[index].state = "cancelled"
                    settings.items[index].message = "Service changed · sharing stopped"
                }
            }
            // A crash or quit leaves durable work queued; it never marks it uploaded.
            for index in settings.items.indices where settings.items[index].state == "uploading" {
                settings.items[index].state = "waiting"
            }
            storageReady = true
            _ = persist()
            if enabled { notice = "Sharing is on for new sessions." }
        } catch {
            settings = SharingSettings()
            notice = error.localizedDescription
        }
    }

    // Start the retry timer and resume eligible pending uploads while the app is running.
    func resume() {
        guard researchAvailable else { return }
        guard timer == nil else { return }
        timer = Timer.scheduledTimer(withTimeInterval: 60, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { _ = self?.retryPending() }
        }
        retryPending()
    }

    // Validate and store the enrollment credential in Keychain, resetting sharing before replacing it.
    func saveCredential(_ input: String) {
        guard researchAvailable else {
            notice = setupBlocker ?? "Research sharing is unavailable."
            return
        }
        let value = input.trimmingCharacters(in: .whitespacesAndNewlines)
        // The researcher issues ID.secret. This catches a token for the wrong Mac
        // before sharing is enabled; the server still verifies the secret itself.
        let parts = value.split(separator: ".", omittingEmptySubsequences: false)
        guard parts.count == 2, String(parts[0]) == participantID,
              parts[1].count == 64, parts[1].allSatisfy({ $0.isHexDigit }) else {
            notice = "Use the enrollment credential issued for the participant ID shown here."
            return
        }
        setEnabled(false)
        do {
            try environment.saveCredential(value)
            hasCredential = true
            notice = "Enrollment saved. Turn on sharing when you're ready."
        } catch { notice = error.localizedDescription }
    }

    // Create a fresh consent marker on opt-in, or cancel pending work and discard its cached ZIPs on opt-out.
    func setEnabled(_ value: Bool) {
        if value {
            guard canEnable else { notice = setupBlocker ?? "Sharing setup is incomplete."; return }
            guard !enabled else { return }
            settings.consentID = UUID().uuidString
            settings.consentedAt = Date()
            settings.serviceURL = environment.serviceURL
            guard persist() else { return }
            notice = "Sharing is on for sessions started from now on. Older sessions remain local."
            retryPending()
        } else {
            generation = UUID()
            task?.cancel()
            // Keep the task reference until its cancellation cleanup has finished.
            settings.consentID = nil
            settings.consentedAt = nil
            for index in settings.items.indices where settings.items[index].uploadedAt == nil {
                settings.items[index].state = "cancelled"
                settings.items[index].message = "Sharing stopped · kept locally"
            }
            _ = persist()
            notice = "Sharing is off. Pending uploads are cancelled. Data already received isn't deleted."
            if task == nil { removeCancelledArchives() }
        }
    }

    // Return a session's sharing status for display in the session library.
    func status(for sessionID: String) -> String {
        settings.items.first { $0.id == sessionID }?.message ?? "Local only"
    }

    // Cancel pending sharing for a deleted local session without claiming cloud copies were deleted.
    func cancelSession(_ id: String) {
        if let index = settings.items.firstIndex(where: { $0.id == id }), settings.items[index].uploadedAt == nil {
            if settings.items[index].state == "uploading" { task?.cancel() }
            settings.items[index].state = "cancelled"
            settings.items[index].message = "Local session deleted · upload cancelled"
            _ = persist()
        }
    }

    // Called after Stop and at relaunch. Only sessions explicitly eligible at START
    // under the current consent are considered. This is not a historical backfill.
    // Discover newly eligible sessions and start one queue worker, without backfilling older consent periods.
    @discardableResult func retryPending() -> Task<Void, Never>? {
        guard enabled, canEnable else { return nil }
        if let task { return task }
        do {
            let sessions = try SessionFiles.list(in: environment.sessionRoot())
            for session in sessions where !settings.items.contains(where: { $0.id == session.id }) {
                guard let data = try? Data(contentsOf: session.folder.appendingPathComponent("session.json")),
                      let meta = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any],
                      UUID(uuidString: session.id) != nil, meta["session_id"] as? String == session.id,
                      meta["participant_id"] as? String == participantID,
                      meta["sharing_consent_id"] as? String == settings.consentID,
                      let duration = session.duration, session.endedAt != nil else { continue }
                if duration > Double(UploadPolicy.dailySeconds) {
                    var item = UploadItem(id: session.id, participantID: participantID,
                        consentID: settings.consentID!, durationSeconds: UploadPolicy.dailySeconds)
                    item.state = "local"
                    item.message = "Over 180 minutes · kept locally"
                    settings.items.append(item)
                } else if UploadPolicy.eligible(metadata: meta, participant: participantID, consent: consentID),
                          let seconds = UploadPolicy.seconds(duration) {
                    settings.items.append(UploadItem(id: session.id, participantID: participantID,
                        consentID: settings.consentID!, durationSeconds: seconds))
                }
            }
            guard persist() else { return nil }
        } catch { notice = "Couldn't check saved sessions: \(error.localizedDescription)"; return nil }
        let currentGeneration = generation
        task = Task { [weak self] in
            guard let self else { return }
            await self.processQueue(generation: currentGeneration)
            self.task = nil
            self.uploading = false
            self.removeCancelledArchives()
        }
        return task
    }

    // Prepare and send waiting sessions, verify receipts, and delay retries or mark permanent problems.
    private func processQueue(generation currentGeneration: UUID) async {
        guard let root, let endpoint = UploadPolicy.endpoint(environment.serviceURL) else { return }
        let candidates = settings.items.filter { $0.state == "waiting" && $0.retryAfter <= Date() }
        for item in candidates {
            guard !Task.isCancelled, currentGeneration == generation, enabled,
                  item.consentID == consentID,
                  let index = settings.items.firstIndex(where: { $0.id == item.id }),
                  settings.items[index].state == "waiting" else { continue }
            do {
                let sessionRoot = try environment.sessionRoot()
                let folder = sessionRoot.appendingPathComponent(item.id)
                try SessionFiles.validate(folder, in: sessionRoot, active: nil)
                let meta = try JSONSerialization.jsonObject(with: Data(contentsOf: folder.appendingPathComponent("session.json"))) as? [String: Any] ?? [:]
                guard UploadPolicy.eligible(metadata: meta, participant: participantID, consent: consentID),
                      UploadPolicy.seconds(meta["duration_seconds"] as? Double ?? 0) == item.durationSeconds else {
                    throw SharingError.message("Session is not eligible for sharing. Kept locally.")
                }
                let destination = root.appendingPathComponent("\(item.id).zip")
                settings.items[index].state = "uploading"
                settings.items[index].message = "Preparing upload…"
                uploading = true
                guard persist() else { return }
                let archive = try await environment.prepare(folder, destination)
                try Task.checkCancellation()
                guard currentGeneration == generation, enabled, item.consentID == consentID else { return }
                guard let token = try environment.readCredential() else {
                    throw SharingError.message("Enrollment credential is missing.")
                }
                if let previous = item.sha256, previous != archive.sha256 {
                    throw SharingError.message("The queued archive changed. Kept locally rather than replacing an upload.")
                }
                settings.items[index].sha256 = archive.sha256
                settings.items[index].bytes = archive.bytes
                settings.items[index].attempts += 1
                settings.items[index].message = "Uploading…"
                guard persist() else { return }
                let (data, response) = try await environment.send(archive, item, endpoint, token)
                guard currentGeneration == generation, !Task.isCancelled else { return }
                if (200...299).contains(response.statusCode) {
                    let receipt = try JSONDecoder().decode(UploadReceipt.self, from: data)
                    guard receipt.stored, receipt.session_id == item.id.lowercased(), receipt.sha256 == archive.sha256 else {
                        throw SharingError.message("Upload confirmation didn't match this session.")
                    }
                    settings.items[index].state = "uploaded"
                    settings.items[index].uploadedAt = Date()
                    settings.items[index].message = "Uploaded"
                    guard persist() else { return }
                    try? FileManager.default.removeItem(at: archive.file)
                    notice = "Session uploaded. Your local recording is still saved."
                } else if response.statusCode == 429 {
                    let seconds = Double(response.value(forHTTPHeaderField: "Retry-After") ?? "3600") ?? 3600
                    settings.items[index].state = "waiting"
                    settings.items[index].retryAfter = Date().addingTimeInterval(max(60, min(seconds, 86400)))
                    settings.items[index].message = "Daily upload limit · waiting until \(settings.items[index].retryAfter.formatted(date: .abbreviated, time: .shortened))"
                    _ = persist()
                    break
                } else if [400, 401, 403, 409, 413, 415, 422].contains(response.statusCode) {
                    settings.items[index].state = "local"
                    settings.items[index].message = [401, 403].contains(response.statusCode)
                        ? "Enrollment rejected · contact the researcher" : "Upload rejected (\(response.statusCode)) · kept locally"
                    notice = settings.items[index].message
                    _ = persist()
                    break
                } else {
                    throw URLError(.badServerResponse)
                }
            } catch {
                guard currentGeneration == generation, settings.items[index].state != "cancelled" else { return }
                if error is SharingError || error is CocoaError {
                    settings.items[index].state = "local"
                    settings.items[index].message = error.localizedDescription
                } else {
                    settings.items[index].state = "waiting"
                    let delay = min(21600.0, 300 * pow(2, Double(min(settings.items[index].attempts, 6))))
                    settings.items[index].retryAfter = Date().addingTimeInterval(delay)
                    settings.items[index].message = "Waiting to retry · original session kept locally"
                }
                notice = settings.items[index].message
                _ = persist()
                if Task.isCancelled { return }
            }
        }
    }

    // Save queue/settings atomically; stop sharing if this state cannot be safely saved.
    @discardableResult private func persist() -> Bool {
        guard let root, storageReady else { return false }
        do {
            let destination = root.appendingPathComponent("state.json")
            try JSONEncoder().encode(settings).write(to: destination, options: .atomic)
            try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: destination.path)
            return true
        } catch {
            storageReady = false
            settings.consentID = nil
            task?.cancel()
            notice = "Couldn't save sharing preferences. Uploads stopped; relaunch before trying again."
            return false
        }
    }

    // Remove cached ZIPs for cancelled/local-only items, not the original recording folders.
    private func removeCancelledArchives() {
        guard let root else { return }
        for item in settings.items where item.state == "cancelled" || item.state == "local" {
            guard UUID(uuidString: item.id) != nil else { continue }
            try? FileManager.default.removeItem(at: root.appendingPathComponent("\(item.id).zip"))
        }
    }
}
