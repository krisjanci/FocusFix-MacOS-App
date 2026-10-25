import Foundation
import Combine

@MainActor
final class ResearchSharingController: ObservableObject {
    static let shared = ResearchSharingController(account: .shared)
    @Published private(set) var state = ResearchSharingState()
    @Published private(set) var busy = false
    @Published private(set) var notice = "Research sharing is off."
    private let account: AccountController
    private var storage: URL?
    private var sessionRoot: URL?
    private var observation: AnyCancellable?
    private var timer: Timer?
    private var task: Task<Void, Never>?
    private var generation = UUID()
    private var retryAt = Date.distantPast
    private var previousOwner: UUID?

    var enabled: Bool { capturedConsent != nil }
    var capturedConsent: ResearchConsent? {
        guard account.researchAvailable, account.researchEnrolled, let consent = state.consent,
              consent.owner == account.session?.user.id, consent.studyVersion == account.enrollment?.consent_version,
              consent.origin == account.api?.configuration.origin.absoluteString else { return nil }
        return consent
    }

    init(account: AccountController, root: URL? = nil, recordings: URL? = nil, startTimer: Bool = true) {
        self.account = account
        do {
            let root = try root ?? FileManager.default.url(for: .applicationSupportDirectory,
                in: .userDomainMask, appropriateFor: nil, create: true).appendingPathComponent("FocusFix/ResearchSharing", isDirectory: true)
            try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
            storage = root
            sessionRoot = try recordings ?? SessionFiles.root()
            let file = root.appendingPathComponent("state.json")
            if FileManager.default.fileExists(atPath: file.path) {
                state = try JSONDecoder().decode(ResearchSharingState.self, from: Data(contentsOf: file))
            }
        } catch { notice = "Research sharing could not open its saved state. Sharing remains paused."; storage = nil }
        observation = account.$session.map { $0?.user.id }.removeDuplicates().sink { [weak self] owner in
            guard let self else { return }
            self.generation = UUID()
            self.task?.cancel()
            self.task = nil
            self.busy = false
            if self.previousOwner != nil && self.previousOwner != owner { self.disable() }
            self.previousOwner = owner
            // A matching saved opt-in can resume after an explicit Restore sign-in action.
        }
        guard startTimer else { return }
        let timer = Timer(timeInterval: 60, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.checkDue() }
        }
        self.timer = timer
        RunLoop.main.add(timer, forMode: .common)
    }

    func enable() {
        guard !busy, account.researchAvailable, account.researchEnrolled, let owner = account.session?.user.id,
              let api = account.api, storage != nil else { return }
        let old = state
        state.enable(owner: owner, origin: api.configuration.origin.absoluteString, at: Date(), studyVersion: account.enrollment!.consent_version)
        do { try persist(); notice = "Research sharing is on for new sessions. Each finished session is sent separately." }
        catch { state = old; notice = "Could not save consent. Research sharing was not enabled." }
    }

    func disable() {
        generation = UUID()
        task?.cancel()
        task = nil
        busy = false
        state.disable()
        do { try persist(); notice = "Research sharing is off. Pending deliveries were cancelled; local sessions are kept. Data already received may remain with the researcher." }
        catch { notice = "Sharing stopped for this launch, but its saved setting could not be updated. Keep sharing off after relaunch." }
    }

    func finished(folder: URL, startedAt: Date, captured: ResearchConsent?) {
        guard enabled else { return }
        let old = state
        if state.enqueue(id: folder.lastPathComponent, startedAt: startedAt, endedAt: Date(), captured: captured) {
            do { try persist(); notice = "\(state.sessions.count) new sessions waiting for delivery."; checkDue() }
            catch { state = old; notice = "This session could not be queued for sharing. Export it manually from Sessions." }
        }
    }

    func checkDue() {
        guard enabled, !busy, !state.sessions.isEmpty, Date() >= retryAt else { return }
        deliver()
    }

    func deliver() {
        guard !busy, let consent = capturedConsent, let api = account.api,
              let storage, let root = sessionRoot, !state.sessions.isEmpty else { return }
        busy = true
        let token = generation
        let sessions = state.sessions
        let existing = state.batch
        task = Task { [weak self] in
            guard let self else { return }
            var temporaryZIP: URL?
            defer {
                if let temporaryZIP { try? FileManager.default.removeItem(at: temporaryZIP) }
                if token == self.generation { self.busy = false; self.task = nil }
            }
            do {
                guard await self.account.refreshResearchAccess(), token == self.generation,
                      self.capturedConsent == consent else {
                    self.notice = "Research approval is unavailable or changed. Uploads are paused; local recordings are kept."
                    return
                }
                let batch: ResearchBatch
                if let existing { batch = existing }
                else {
                    let ids = try await Task.detached { try ResearchArchive.select(sessions, root: root) }.value
                    batch = ResearchBatch(id: UUID(), sessionIDs: ids)
                    guard token == self.generation, self.capturedConsent == consent else { return }
                    self.state.batch = batch
                    try self.persist()
                }
                var signedIn = try await self.account.validSession()
                let received = try await api.researchArchiveReceived(batch.id, session: signedIn)
                guard !Task.isCancelled, token == self.generation, self.capturedConsent == consent else { return }
                if !received {
                    let file = storage.appendingPathComponent("\(batch.id.uuidString.lowercased()).zip")
                    temporaryZIP = file
                    let data = try await Task.detached {
                        try ResearchArchive.prepare(ids: batch.sessionIDs, root: root, destination: file)
                    }.value
                    signedIn = try await self.account.validSession()
                    guard !Task.isCancelled, token == self.generation, self.capturedConsent == consent,
                          signedIn.user.id == consent.owner else { return }
                    let objectName = "\(consent.owner.uuidString.lowercased())/\(consent.id.uuidString.lowercased())/\(batch.id.uuidString.lowercased()).zip"
                    _ = try await api.request(path: "storage/v1/object/research-sessions/\(objectName)", body: data,
                        token: signedIn.access_token, headers: ["Content-Type": "application/zip", "x-upsert": "true"])
                    guard token == self.generation, self.capturedConsent == consent else { return }
                    try await api.confirmResearchArchive(batch.id, objectName: objectName, session: signedIn)
                }
                guard token == self.generation, self.capturedConsent == consent else { return }
                let oldState = self.state
                self.state.acknowledge(batchID: batch.id, at: Date())
                do { try self.persist() } catch { self.state = oldState; throw error }
                self.notice = "Session ZIP delivered to the researcher's private storage. Your local sessions are kept."
            } catch {
                guard token == self.generation else { return }
                self.retryAt = Date().addingTimeInterval(3600)
                self.notice = "Research delivery paused: \(error.localizedDescription) Retry later or export a ZIP. Your recordings are kept."
            }
        }
    }

    // Export doesn't mark a batch as delivered: the app cannot know whether a user sends it.
    func export(to destination: URL) async throws {
        guard !busy, !state.sessions.isEmpty, let root = sessionRoot else {
            throw AccountFailure(message: "No queued sessions are available, or a delivery is running.")
        }
        busy = true
        defer { busy = false }
        let sessions = state.sessions
        let ids = try await Task.detached { try ResearchArchive.select(sessions, root: root) }.value
        _ = try await Task.detached { try ResearchArchive.prepare(ids: ids, root: root, destination: destination) }.value
        notice = "ZIP exported. Review it and send it to the researcher using the agreed private channel."
    }

    func report(_ error: Error) { notice = error.localizedDescription }

    private func persist() throws {
        guard let storage else { throw AccountFailure(message: "Research sharing storage is unavailable.") }
        try JSONEncoder().encode(state).write(to: storage.appendingPathComponent("state.json"), options: .atomic)
    }
}
