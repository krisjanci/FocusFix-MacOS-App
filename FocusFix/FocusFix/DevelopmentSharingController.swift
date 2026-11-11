import Foundation
import Combine

@MainActor
final class DevelopmentSharingController: ObservableObject {
    static let shared = DevelopmentSharingController(account: .shared)
    @Published private(set) var state = DevelopmentSharingState()
    @Published private(set) var collectionEnabled = false
    @Published private(set) var approved = false
    @Published private(set) var busy = false
    @Published private(set) var deletionPending = false
    @Published private(set) var notice = "Recording sharing is off."
    private(set) var policyVersion = ""
    private var serverConsent: DevelopmentServerConsent?
    private let account: AccountController
    private let defaults: UserDefaults?
    private let storage: URL?
    private let recordings: URL?
    private var observation: AnyCancellable?
    private var timer: Timer?
    private var deliveryTask: Task<Void, Never>?
    private var generation = UUID()
    private var retryAt = Date.distantPast
    private var previousOwner: UUID?
    private static let stopLatch = "focusfix.development.sharingStopped"

    var available: Bool { account.api?.configuration.developmentSharingEnabled == true }
    var enabled: Bool { capturedConsent != nil }
    var capturedConsent: DevelopmentConsent? {
        guard available, collectionEnabled, approved, !deletionPending,
              defaults?.bool(forKey: Self.stopLatch) != true,
              let consent = state.consent, consent.owner == account.session?.user.id,
              consent.origin == account.api?.configuration.origin.absoluteString,
              consent.policyVersion == policyVersion,
              serverConsent?.consent_id == consent.id,
              serverConsent?.policy_version == policyVersion,
              serverConsent?.withdrawn_at == nil,
              !state.pendingWithdrawals.contains(consent) else { return nil }
        return consent
    }

    init(account: AccountController, root: URL? = nil, recordings: URL? = nil,
         startTimer: Bool = true, defaults: UserDefaults? = .standard) {
        self.account = account
        self.defaults = defaults
        var resolvedRoot: URL?
        var resolvedRecordings: URL?
        var loadedState = DevelopmentSharingState()
        do {
            let folder = try root ?? FileManager.default.url(for: .applicationSupportDirectory,
                in: .userDomainMask, appropriateFor: nil, create: true)
                .appendingPathComponent("FocusFix/DevelopmentSharing", isDirectory: true)
            try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true,
                                                    attributes: [.posixPermissions: 0o700])
            resolvedRoot = folder
            resolvedRecordings = try recordings ?? SessionFiles.root()
            let file = folder.appendingPathComponent("state.json")
            if FileManager.default.fileExists(atPath: file.path) {
                loadedState = try JSONDecoder().decode(DevelopmentSharingState.self, from: Data(contentsOf: file))
            }
            if defaults?.bool(forKey: Self.stopLatch) == true {
                loadedState.disable()
                try JSONEncoder().encode(loadedState).write(to: file, options: .atomic)
            }
        } catch { notice = "Sharing could not open its saved state. No uploads will start." }
        storage = resolvedRoot
        self.recordings = resolvedRecordings
        state = loadedState
        observation = account.$session.map { $0?.user.id }.removeDuplicates().sink { [weak self] owner in
            guard let self else { return }
            self.generation = UUID()
            self.deliveryTask?.cancel()
            self.deliveryTask = nil
            self.busy = false
            self.collectionEnabled = false
            self.approved = false
            self.serverConsent = nil
            if (self.previousOwner != nil && self.previousOwner != owner) ||
                (owner != nil && self.state.consent != nil && self.state.consent?.owner != owner) {
                self.disable()
            }
            self.previousOwner = owner
            if owner != nil {
                Task { await self.refresh(); self.checkDue() }
            }
        }
        if startTimer {
            let timer = Timer(timeInterval: 60, repeats: true) { [weak self] _ in
                MainActor.assumeIsolated {
                    guard let self, self.account.session != nil, !self.busy else { return }
                    Task { await self.refresh(); self.checkDue() }
                }
            }
            self.timer = timer
            RunLoop.main.add(timer, forMode: .common)
        }
    }

    private func persist() throws {
        guard let storage else { throw AccountFailure(message: "Sharing state is unavailable.") }
        try JSONEncoder().encode(state).write(to: storage.appendingPathComponent("state.json"), options: .atomic)
    }

    func refresh() async {
        guard available, account.session != nil, let api = account.api else {
            collectionEnabled = false; approved = false; serverConsent = nil
            return
        }
        do {
            let session = try await account.validSession()
            let collection = try await api.developmentCollection(session: session)
            let approval = try await api.developmentApproval(session: session)
            let consent = try await api.developmentConsent(session: session)
            guard account.session?.user.id == session.user.id else { return }
            collectionEnabled = collection?.enabled == true
            approved = approval?.enabled == true
            policyVersion = collection?.policy_version ?? ""
            serverConsent = consent
            if enabled { notice = "Sharing is on for new recordings started after consent." }
            else if !collectionEnabled { notice = "The developer is not collecting recordings right now." }
            else if !approved { notice = "Your account has not been approved for sharing." }
            else { notice = "Sharing is off. Your recordings stay on this Mac." }
            _ = await synchronizeWithdrawals()
        } catch {
            collectionEnabled = false; approved = false; serverConsent = nil
            notice = "Sharing status is unavailable. Uploads are paused; local recordings are kept."
        }
    }

    func enable() async {
        guard !busy, available, storage != nil, let api = account.api else { return }
        busy = true
        defer { busy = false }
        await refresh()
        guard collectionEnabled, approved, !policyVersion.isEmpty,
              let owner = account.session?.user.id,
              await synchronizeWithdrawals(), state.pendingWithdrawals.isEmpty else { return }
        let consent = DevelopmentConsent(id: UUID(), owner: owner,
            origin: api.configuration.origin.absoluteString, policyVersion: policyVersion, startedAt: Date())
        state.enable(consent)
        state.pendingWithdrawals.append(consent)
        do {
            try persist()
            let session = try await account.validSession()
            guard session.user.id == owner else { throw AccountFailure(message: "Account changed.") }
            try await api.setDevelopmentConsent(id: consent.id, version: consent.policyVersion,
                                                 enabled: true, session: session)
            guard state.consent == consent, account.session?.user.id == owner else { return }
            state.pendingWithdrawals.removeAll { $0 == consent }
            try persist()
            serverConsent = DevelopmentServerConsent(consent_id: consent.id,
                policy_version: consent.policyVersion, withdrawn_at: nil)
            defaults?.set(false, forKey: Self.stopLatch)
            notice = "Sharing is on. Only new finished recordings may be uploaded."
        } catch {
            state.disable()
            try? persist()
            notice = "Sharing was not enabled. Your recordings remain on this Mac."
        }
    }

    func disable() {
        defaults?.set(true, forKey: Self.stopLatch)
        generation = UUID()
        deliveryTask?.cancel()
        deliveryTask = nil
        busy = false
        state.disable()
        do { try persist(); notice = "Sharing is off. Pending uploads were cancelled." }
        catch { notice = "Sharing stopped for this launch. Recheck it after relaunch." }
        Task { _ = await synchronizeWithdrawals() }
    }

    @discardableResult
    func synchronizeWithdrawals() async -> Bool {
        guard !state.pendingWithdrawals.isEmpty else { return true }
        guard let api = account.api, let owner = account.session?.user.id else { return false }
        let pending = state.pendingWithdrawals.filter {
            $0.owner == owner && $0.origin == api.configuration.origin.absoluteString
        }
        do {
            for consent in pending {
                let session = try await account.validSession()
                guard session.user.id == owner else { return false }
                try await api.setDevelopmentConsent(id: consent.id, version: consent.policyVersion,
                                                     enabled: false, session: session)
                state.pendingWithdrawals.removeAll { $0 == consent }
                try persist()
            }
            serverConsent = nil
            return state.pendingWithdrawals.isEmpty
        } catch {
            notice = "Sharing is off here. Server withdrawal will retry when you reconnect and sign in."
            return false
        }
    }

    func finished(folder: URL, startedAt: Date, captured: DevelopmentConsent?) {
        guard enabled, let saved = try? SavedSession(folder: folder),
              saved.schemaVersion == RecordingContract.schemaVersion,
              saved.recordingContract?.finalized == true else { return }
        let old = state
        if state.enqueue(folder: folder, startedAt: startedAt, captured: captured) {
            do { try persist(); checkDue() }
            catch { state = old; notice = "A recording could not be queued for sharing. It remains local." }
        }
    }

    func checkDue(at date: Date = Date()) {
        guard !busy, !state.pending.isEmpty, date >= retryAt else { return }
        deliveryTask = Task { [weak self] in
            guard let self else { return }
            await self.refresh()
            guard self.enabled else { return }
            await self.deliverNext()
        }
    }

    private func deliverNext() async {
        guard !busy, let consent = capturedConsent, let upload = state.pending.first,
              upload.consentID == consent.id, let api = account.api,
              let storage, let recordings else { return }
        busy = true
        let token = generation
        let file = storage.appendingPathComponent("\(UUID().uuidString).zip")
        defer { try? FileManager.default.removeItem(at: file); if token == generation { busy = false } }
        do {
            let path = "\(consent.owner.uuidString.lowercased())/\(consent.id.uuidString.lowercased())/\(upload.id.lowercased()).zip"
            var session = try await account.validSession()
            guard token == generation, capturedConsent == consent, session.user.id == consent.owner else { return }
            if !(await api.developmentObjectExists(path: path, session: session)) {
                let data = try await Task.detached {
                    try DevelopmentArchive.prepare(id: upload.id, root: recordings, consent: consent, destination: file)
                }.value
                session = try await account.validSession()
                guard !Task.isCancelled, token == generation, capturedConsent == consent,
                      session.user.id == consent.owner else { return }
                do { try await api.uploadDevelopmentArchive(data, path: path, session: session) }
                catch {
                    guard await api.developmentObjectExists(path: path, session: session) else { throw error }
                }
            }
            guard !Task.isCancelled, token == generation, capturedConsent == consent else { return }
            state.pending.removeFirst()
            try persist()
            retryAt = .distantPast
            notice = "One recording was sent for FocusFix product development. Local files remain."
            if !state.pending.isEmpty { Task { self.checkDue() } }
        } catch {
            guard token == generation else { return }
            retryAt = Date().addingTimeInterval(3600)
            notice = "Delivery paused. The recording remains local and will retry later."
        }
    }

    func requestDeletion() async {
        disable()
        guard !deletionPending, let api = account.api, account.session != nil else { return }
        deletionPending = true
        defer { deletionPending = false }
        do {
            let session = try await account.validSession()
            try await api.requestDevelopmentDeletion(session: session)
            notice = "Hosted recordings were deleted. The developer must also review any downloaded copies."
        } catch {
            notice = "The deletion request could not finish. Sharing is off; reconnect and try again."
        }
    }
}
