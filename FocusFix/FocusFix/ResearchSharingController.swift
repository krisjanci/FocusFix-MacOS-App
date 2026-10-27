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
    private var withdrawalTask: Task<Void, Never>?
    @Published private(set) var synchronizingWithdrawal = false
    @Published private(set) var deletionPending = false
    private let defaults: UserDefaults?
    private static let withdrawalLatch = "focusfix.research.withdrawalLatch"
    var withdrawalPending: Bool {
        state.pendingWithdrawals.contains { $0.owner == account.session?.user.id && $0.origin == account.api?.configuration.origin.absoluteString }
    }

    var enabled: Bool { capturedConsent != nil }
    var capturedConsent: ResearchConsent? {
        guard !deletionPending, account.researchAvailable, account.researchEnrolled, let consent = state.consent,
              consent.owner == account.session?.user.id, consent.studyVersion == account.enrollment?.consent_version,
              consent.origin == account.api?.configuration.origin.absoluteString,
              account.serverResearchConsent?.consent_id == consent.id,
              account.serverResearchConsent?.study_version == consent.studyVersion,
              account.serverResearchConsent?.withdrawn_at == nil,
              !(defaults?.stringArray(forKey: Self.withdrawalLatch) ?? []).contains(consent.id.uuidString),
              !withdrawalPending else { return nil }
        return consent
    }

    init(account: AccountController, root: URL? = nil, recordings: URL? = nil, startTimer: Bool = true, defaults: UserDefaults? = .standard) {
        self.account = account
        self.defaults = defaults
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
            if let consent = state.consent, (defaults?.stringArray(forKey: Self.withdrawalLatch) ?? []).contains(consent.id.uuidString) {
                state.disable()
                try JSONEncoder().encode(state).write(to: file, options: .atomic)
            }
        } catch { notice = "Research sharing could not open its saved state. Sharing remains paused."; storage = nil }
        observation = account.$session.map { $0?.user.id }.removeDuplicates().sink { [weak self] owner in
            guard let self else { return }
            self.generation = UUID()
            self.task?.cancel()
            self.task = nil
            self.busy = false
            if (self.previousOwner != nil && self.previousOwner != owner) ||
                (owner != nil && self.state.consent != nil && self.state.consent?.owner != owner) {
                self.disable()
            }
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

    func enable(reviewedStudy: ResearchStudy? = nil) async {
        guard !busy, account.researchAvailable, account.researchEnrolled, let owner = account.session?.user.id,
              let api = account.api, storage != nil, let reviewed = reviewedStudy ?? account.study else { return }
        guard await synchronizeWithdrawals(), state.pendingWithdrawals.allSatisfy({ $0.owner != owner || $0.origin != api.configuration.origin.absoluteString }) else { return }
        busy = true
        generation = UUID()
        let token = generation
        defer { if token == generation { busy = false } }
        guard await account.refreshResearchAccess(), account.session?.user.id == owner, token == generation else { return }
        guard account.study == reviewed else {
            notice = "Study details changed. Review the current consent before enabling sharing."
            return
        }
        state.enable(owner: owner, origin: api.configuration.origin.absoluteString, at: Date(), studyVersion: reviewed.version)
        let candidate = state.consent!
        // Persist a compensating withdrawal before sending the grant. A crash cannot leave an untracked grant.
        state.pendingWithdrawals.append(ResearchWithdrawal(candidate))
        do {
            try persist()
            try await api.setResearchConsent(id: candidate.id, version: candidate.studyVersion, enabled: true, session: account.validSession())
            guard token == generation, state.consent == candidate, account.session?.user.id == owner else {
                _ = await synchronizeWithdrawals(); return
            }
            state.pendingWithdrawals.removeAll { $0.consentID == candidate.id }
            try persist()
            _ = await account.refreshResearchAccess()
            guard token == generation else { return }
            notice = enabled ? "Research sharing is on for new sessions. Each finished session is sent separately." : "Consent could not be verified. Uploads are paused."
        } catch {
            guard token == generation else { return }
            state.disable()
            try? persist()
            notice = "Sharing was not enabled. A pending withdrawal will be synchronized before any upload."
        }
    }

    func disable() {
        // Independent fail-closed preference protects against failure to rewrite the queue file.
        if let consent = state.consent {
            var latch = defaults?.stringArray(forKey: Self.withdrawalLatch) ?? []
            if !latch.contains(consent.id.uuidString) { latch.append(consent.id.uuidString) }
            defaults?.set(latch, forKey: Self.withdrawalLatch)
        }
        generation = UUID()
        task?.cancel()
        task = nil
        busy = false
        state.disable()
        do { try persist(); notice = "Research sharing is off. Pending deliveries were cancelled; local sessions are kept. Data already received may remain with the researcher." }
        catch { notice = "Sharing stopped for this launch, but its saved setting could not be updated. Keep sharing off after relaunch." }
        withdrawalTask = Task { [weak self] in _ = await self?.synchronizeWithdrawals() }
    }

    @discardableResult
    func synchronizeWithdrawals() async -> Bool {
        guard !synchronizingWithdrawal else { return false }
        guard let owner = account.session?.user.id, let api = account.api else { return state.pendingWithdrawals.isEmpty }
        let pending = state.pendingWithdrawals.filter { $0.owner == owner && $0.origin == api.configuration.origin.absoluteString }
        guard !pending.isEmpty else { return true }
        synchronizingWithdrawal = true
        defer { synchronizingWithdrawal = false }
        do {
            for withdrawal in pending {
                let session = try await account.validSession()
                guard session.user.id == owner else { return false }
                try await api.setResearchConsent(id: withdrawal.consentID, version: withdrawal.studyVersion, enabled: false, session: session)
                state.pendingWithdrawals.removeAll { $0 == withdrawal }
                try persist()
                let latch = defaults?.stringArray(forKey: Self.withdrawalLatch) ?? []
                defaults?.set(latch.filter { $0 != withdrawal.consentID.uuidString }, forKey: Self.withdrawalLatch)
            }
            _ = await account.refreshResearchAccess()
            return true
        } catch {
            notice = "Sharing is off. Server withdrawal is pending; reconnect and sign in to synchronize."
            return false
        }
    }

    func requestDeletion() async {
        disable()
        guard !deletionPending, let api = account.api, let owner = account.session?.user.id else { return }
        deletionPending = true
        defer { deletionPending = false }
        do {
            let session = try await account.validSession()
            guard session.user.id == owner else { return }
            try await api.requestResearchDeletion(session: session)
            _ = await account.refreshResearchAccess()
            notice = "Hosted recordings deleted. The researcher must review downloaded copies and training datasets before completing your request."
        } catch { notice = "Deletion could not be completed. Sharing is off; reconnect and retry the deletion request." }
    }

    func finished(folder: URL, startedAt: Date, captured: ResearchConsent?) {
        guard enabled else { return }
        let old = state
        if state.enqueue(id: folder.lastPathComponent, startedAt: startedAt, endedAt: Date(), captured: captured) {
            do { try persist(); notice = "\(state.sessions.count) new sessions waiting for delivery."; checkDue() }
            catch { state = old; notice = "This session could not be queued for sharing. Export it manually from Sessions." }
        }
    }

    func checkDue(at date: Date = Date()) {
        if !busy, withdrawalPending {
            withdrawalTask = Task { [weak self] in _ = await self?.synchronizeWithdrawals() }
            return
        }
        guard !busy, !state.sessions.isEmpty, date >= retryAt, let consent = state.consent,
              consent.owner == account.session?.user.id,
              consent.origin == account.api?.configuration.origin.absoluteString,
              account.researchAvailable else { return }
        if enabled { deliver(); return }
        // A failed access refresh clears cached approval. Retry that check too, rather than
        // leaving a durable queue stuck forever behind the cleared cache.
        busy = true
        let token = generation
        task = Task { [weak self] in
            guard let self else { return }
            _ = await self.account.refreshResearchAccess()
            guard token == self.generation else { return }
            self.busy = false
            self.task = nil
            if self.enabled { self.deliver() }
            else { self.retryAt = Date().addingTimeInterval(3600) }
        }
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
                guard await self.synchronizeWithdrawals() else { return }
                guard await self.account.refreshResearchAccess(), token == self.generation,
                      self.capturedConsent == consent else {
                    if token == self.generation {
                        self.retryAt = Date().addingTimeInterval(3600)
                        self.notice = "Research approval is unavailable or changed. Uploads are paused; local recordings are kept."
                    }
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
                self.retryAt = .distantPast
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
