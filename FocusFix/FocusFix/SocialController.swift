import Foundation
import Combine

@MainActor
final class SocialController: ObservableObject {
    static let shared = SocialController(account: .shared)
    @Published private(set) var ledger: SocialLedger?
    @Published private(set) var declaredWorkSyncVersion = 0
    @Published private(set) var groups: [SocialGroup] = []
    @Published private(set) var invitations: [GroupInvitation] = []
    @Published private(set) var busy = false
    @Published private(set) var notice: String?
    @Published private(set) var invitationNotice: String?
    @Published private(set) var pendingConfirmation = false
    @Published private(set) var selection = GroupSelection()
    @Published private(set) var hasLoadedGroups = false
    @Published private(set) var syncFailed = false
    private let selectionDefaults: UserDefaults?
    private let account: AccountController
    private let storageDirectory: URL?
    init(account: AccountController, storageDirectory: URL? = nil, selectionDefaults: UserDefaults? = .standard) {
        self.account = account; self.storageDirectory = storageDirectory; self.selectionDefaults = selectionDefaults
        // The incoming session is used synchronously: old members disappear before a new account renders.
        account.$session.sink { [weak self] incoming in
            guard let self else { return }
            let incomingKey = incoming.map { "\(account.api?.configuration.origin.absoluteString ?? "")|\($0.user.id)" }
            let changed = incomingKey != self.identity
            if changed { self.clearAccountState() }
            if self.started && changed { Task { @MainActor in self.alignAccount(); await self.automaticRefresh() } }
        }.store(in: &subscriptions)
    }
    private var identitySince = Date()
    private var identity: String?
    private var file: URL?
    private var persistedLedger: SocialLedger?
    private var generation = UUID()
    private var subscriptions: Set<AnyCancellable> = []
    private var inFlight: Set<UUID> = []
    private var started = false
    private var repairedWorkOutbox = false
    private var groupReaders: Set<UUID> = []
    private var needsGroupRead = false
    private var lastGroupRead = Date.distantPast
    private var groupVersion: String?
    private var photos: [UUID: (version: String, data: Data)] = [:]
    private var failures = 0
    private(set) var nextAutomaticSyncAt = Date.distantPast

    // Multiple windows can display Groups. A disappearing panel must not stop another.
    func setGroupViewVisible(_ id: UUID, visible: Bool) {
        if visible {
            guard groupReaders.insert(id).inserted else { return }
            if !hasLoadedGroups || Date().timeIntervalSince(lastGroupRead) >= 2 {
                needsGroupRead = true
                Task { await automaticRefresh() }
            }
        } else { groupReaders.remove(id) }
    }

    @discardableResult
    func automaticRefresh(at date: Date = Date()) async -> Bool {
        alignAccount()
        guard !busy, date >= nextAutomaticSyncAt, account.session != nil else { return false }
        let pending = ledger?.pending.isEmpty == false || ledger?.declaredWorkPending?.isEmpty == false
        guard !groupReaders.isEmpty || pending else { return false }
        return await refresh(includeGroups: !groupReaders.isEmpty)
    }

    private func failed(_ error: Error) {
        failures = min(failures + 1, 8)
        let exponential = min(3600, 30 * pow(2, Double(failures - 1)))
        let delay = max(min(3600, exponential * Double.random(in: 0.8...1.2)), (error as? AccountFailure)?.retryAfter ?? 0)
        nextAutomaticSyncAt = Date().addingTimeInterval(delay)
    }

    private func succeeded() {
        failures = 0; nextAutomaticSyncAt = .distantPast
    }

    var enabled: Bool { ledger != nil }
    var declaredWorkSyncHeld: Bool { declaredWorkSyncVersion == 0 && ledger?.declaredWorkPending?.isEmpty == false }
    var calendar: Calendar { DailyProgress.calendar(timeZone: TimeZone(identifier: ledger?.timezone ?? "") ?? .current) }
    var userID: UUID? { account.session?.user.id }

    func start() {
        guard !started else { return }; started = true
        Timer.publish(every: 30, on: .main, in: .common).autoconnect().sink { [weak self] _ in
            Task { @MainActor in await self?.automaticRefresh() }
        }.store(in: &subscriptions)
        NotificationCenter.default.publisher(for: Notification.Name("FocusFixAccountDeleted")).sink { [weak self] note in
            guard let id = note.userInfo?["userID"] as? UUID, let origin = note.userInfo?["origin"] as? URL else { return }
            Task { @MainActor in self?.discardCache(userID: id, origin: origin) }
        }.store(in: &subscriptions)
        alignAccount()
        Task { await automaticRefresh() }
    }

    var selectedGroup: SocialGroup? { groups.first { $0.id == selection.groupID } ?? groups.first }
    var accessState: GroupAccessState {
        GroupAccessState.resolve(signedIn: userID != nil, enabled: enabled, busy: busy,
            loaded: hasLoadedGroups, failed: syncFailed, notice: notice != nil)
    }
    func selectGroup(_ id: UUID) {
        guard selection.groupID != id, groups.contains(where: { $0.id == id }) else { return }
        selection.groupID = id; saveSelection()
    }
    func selectMetric(_ metric: LeaderboardMetric) {
        guard selection.metric != metric else { return }
        selection.metric = metric; saveSelection()
    }
    private func selectionKey(_ identity: String) -> String { "focusfix.groups.selection." + identity }
    private func saveSelection() {
        guard let identity, let data = try? JSONEncoder().encode(selection) else { return }
        selectionDefaults?.set(data, forKey: selectionKey(identity))
    }
    private func clearAccountState() {
        generation = UUID(); identitySince = Date(); identity = nil; file = nil
        ledger = nil; persistedLedger = nil; declaredWorkSyncVersion = 0; groups = []; invitations = []; selection = GroupSelection(); notice = nil; invitationNotice = nil
        busy = false; inFlight = []; pendingConfirmation = false; hasLoadedGroups = false; syncFailed = false
        repairedWorkOutbox = false
        groupVersion = nil; photos = [:]; lastGroupRead = .distantPast
        needsGroupRead = !groupReaders.isEmpty
        succeeded()
    }
    func retry() async {
        repairedWorkOutbox = false
        groupVersion = nil // Manual retry repairs an evicted/incomplete group cache.
        if !enabled { identity = nil; alignAccount() }
        await refresh()
    }

    func discardCache(userID: UUID, origin: URL) {
        let key = "\(origin.absoluteString)|\(userID)"
        do {
            let root = try storageDirectory ?? FileManager.default.url(for: .applicationSupportDirectory, in: .userDomainMask, appropriateFor: nil, create: true)
            let name = Data(key.utf8).base64EncodedString().replacingOccurrences(of: "/", with: "_").replacingOccurrences(of: "+", with: "-")
            let url = root.appendingPathComponent("FocusFix/Social/\(name).json")
            if FileManager.default.fileExists(atPath: url.path) { try FileManager.default.removeItem(at: url) }
            let journal = workJournal(for: url)
            if FileManager.default.fileExists(atPath: journal.path) { try FileManager.default.removeItem(at: journal) }
            selectionDefaults?.removeObject(forKey: selectionKey(key))
            if identity == key { clearAccountState() }
        } catch { notice = "The account was deleted, but its cached group progress could not be removed from this Mac." }
    }

    private func alignAccount() {
        let key = account.session.map { "\(account.api?.configuration.origin.absoluteString ?? "")|\($0.user.id)" }
        guard key != identity else { return }
        clearAccountState()
        identity = key
        guard let key else { return }
        if let data = selectionDefaults?.data(forKey: selectionKey(key)),
           let saved = try? JSONDecoder().decode(GroupSelection.self, from: data) { selection = saved }
        do {
            let root = try storageDirectory ?? FileManager.default.url(for: .applicationSupportDirectory, in: .userDomainMask, appropriateFor: nil, create: true)
            let name = Data(key.utf8).base64EncodedString().replacingOccurrences(of: "/", with: "_").replacingOccurrences(of: "+", with: "-")
            file = root.appendingPathComponent("FocusFix/Social/\(name).json")
            if let file, FileManager.default.fileExists(atPath: file.path) {
                ledger = try JSONDecoder().decode(SocialLedger.self, from: Data(contentsOf: file))
                persistedLedger = ledger
                try replayWorkJournal(file: file)
                pendingConfirmation = true
            }
        } catch { ledger = nil; notice = "Group progress could not be opened. Your existing file has been kept." }
    }

    func enable() async {
        alignAccount()
        guard identity != nil, ledger == nil, notice == nil else { return }
        var fresh = SocialLedger(timezone: TimeZone.current.identifier)
        fresh.progress.reconcile(at: Date(), calendar: calendar)
        ledger = fresh; pendingConfirmation = true
        persist()
        await refresh()
    }

    private func persist() {
        guard let file, let ledger, ledger != persistedLedger else { return }
        do {
            try FileManager.default.createDirectory(at: file.deletingLastPathComponent(), withIntermediateDirectories: true,
                                                    attributes: [.posixPermissions: 0o700])
            try JSONEncoder().encode(ledger).write(to: file, options: .atomic)
            persistedLedger = ledger
            // The snapshot is durable before removing its now-redundant segment updates.
            let journal = workJournal(for: file)
            if FileManager.default.fileExists(atPath: journal.path) { try FileManager.default.removeItem(at: journal) }
        } catch { notice = "Progress could not be saved on this Mac. Keep FocusFix open and retry." }
    }

    // Main-actor ordering makes each atomic segment replacement durable before it
    // can be sent. A crash between snapshot replacement and journal removal is safe:
    // replay only accepts revisions newer than the durable full snapshot.
    private func workJournal(for file: URL) -> URL { file.appendingPathExtension("work") }
    private func persistWork(_ value: DeclaredWorkPending) {
        guard let file else { return }
        do {
            let folder = workJournal(for: file)
            try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true,
                attributes: [.posixPermissions: 0o700])
            try JSONEncoder().encode(value).write(to: folder.appendingPathComponent(value.segmentID.uuidString + ".json"), options: .atomic)
        } catch { notice = "Progress could not be saved on this Mac. Keep FocusFix open and retry." }
    }
    private func replayWorkJournal(file: URL) throws {
        let folder = workJournal(for: file)
        guard FileManager.default.fileExists(atPath: folder.path), let owner = userID,
              let origin = account.api?.configuration.origin.absoluteString else { return }
        for url in try FileManager.default.contentsOfDirectory(at: folder, includingPropertiesForKeys: nil) {
            let info = try url.resourceValues(forKeys: [.isRegularFileKey, .isSymbolicLinkKey, .fileSizeKey])
            guard info.isRegularFile == true, info.isSymbolicLink != true,
                  (info.fileSize ?? Int.max) <= 16 * 1024 * 1024 else { throw RecordingContract.Invalid.contract }
            let value = try JSONDecoder().decode(DeclaredWorkPending.self, from: Data(contentsOf: url))
            var validation = SocialLedger(timezone: ledger?.timezone ?? "UTC")
            guard value.ready, validation.stageDeclaredWork(value, owner: owner, origin: origin),
                  url.lastPathComponent == value.segmentID.uuidString + ".json" else { throw RecordingContract.Invalid.contract }
            let key = value.segmentID.uuidString
            let current = ledger?.declaredWorkSnapshots?[key] ?? ledger?.declaredWorkPending?[key]
            guard (value.revision ?? 0) > (current?.revision ?? 0) else { continue }
            if ledger?.declaredWorkSnapshots == nil { ledger?.declaredWorkSnapshots = [:] }
            if ledger?.declaredWorkPending == nil { ledger?.declaredWorkPending = [:] }
            ledger?.declaredWorkSnapshots?[key] = value
            ledger?.declaredWorkPending?[key] = value
        }
    }

    var declaredWorkScope: (owner: UUID, origin: String)? {
        guard ledger != nil, let owner = userID, let origin = account.api?.configuration.origin.absoluteString else { return nil }
        return (owner, origin)
    }
    func needsDeclaredWorkDetails(_ segmentID: UUID, days: [String: Double], startedAt: Double? = nil) -> Bool {
        let snapshot = ledger?.declaredWorkSnapshots?[segmentID.uuidString]
        return snapshot?.ready != true || snapshot?.days != days
            || (startedAt != nil && snapshot?.startedAt != startedAt)
    }
    func stageDeclaredWork(segmentID: UUID, days: [String: Double], capturedOwner: UUID?, capturedOrigin: String?,
                           startedAt: Double? = nil, observedThrough: Double? = nil, intervals: [DeclaredWorkInterval]? = nil) {
        alignAccount()
        guard let scope = declaredWorkScope, let capturedOwner, let capturedOrigin, var value = ledger,
              value.stageDeclaredWork(DeclaredWorkPending(ownerID: capturedOwner, origin: capturedOrigin,
                segmentID: segmentID, contractVersion: 2, days: days, startedAt: startedAt, observedThrough: observedThrough, intervals: intervals), owner: scope.owner, origin: scope.origin) else { return }
        let previous = ledger?.declaredWorkSnapshots?[segmentID.uuidString] ?? ledger?.declaredWorkPending?[segmentID.uuidString]
        if previous == nil && days.values.allSatisfy({ $0 == 0 }) { return }
        if previous == value.declaredWorkPending?[segmentID.uuidString] { return }
        ledger = value
        if let staged = value.declaredWorkPending?[segmentID.uuidString] { persistWork(staged) }
        pendingConfirmation = true
        notice = "Work progress is waiting to sync."
    }
    func record(kind: String, seconds: Double, at date: Date = Date(), id: UUID = UUID()) {
        alignAccount()
        guard var value = ledger, seconds.isFinite, seconds > 0 else { return }
        if kind == "work", seconds > 60 {
            var remaining = seconds
            while remaining > 0 {
                let part = min(60, remaining)
                record(kind: kind, seconds: part, at: date.addingTimeInterval(-remaining + part))
                remaining -= part
            }
            return
        }
        let boundary = max(identitySince.timeIntervalSince1970, value.activatedAt)
        let eligibleSeconds = max(0, min(seconds, date.timeIntervalSince1970 - boundary))
        guard eligibleSeconds > 0, kind != "break" || eligibleSeconds >= seconds else { return }
        // Coalesce unsent adjacent work ticks without ever modifying an in-flight event.
        if kind == "work", let last = value.pending.last, last.kind == kind,
           !value.submitted.contains(last.id), abs(date.timeIntervalSince1970 - eligibleSeconds - last.at) < 0.1,
           last.seconds + eligibleSeconds <= 60 {
            value.pending.removeLast()
            let combined = SocialEvent(id: last.id, kind: kind, at: date, seconds: last.seconds + eligibleSeconds)
            value.pending.append(combined)
            value.apply(SocialEvent(kind: kind, at: date, seconds: eligibleSeconds))
        } else {
            value.append(SocialEvent(id: id, kind: kind, at: date, seconds: eligibleSeconds))
        }
        value.progress.reconcile(at: date, calendar: calendar)
        ledger = value; pendingConfirmation = true; persist()
    }

    @discardableResult
    func refresh(action: String = "sync", fields: [String: String] = [:], includeGroups: Bool = true) async -> Bool {
        alignAccount()
        if ledger == nil { return await refreshInvitations() }
        guard !busy, let current = ledger, let api = account.api else { return false }
        let token = generation; busy = true
        let batch = Array(current.pending.prefix(200)); inFlight = Set(batch.map(\.id))
        ledger?.submitted.formUnion(inFlight)
        persist() // A lost response must never allow a submitted summary to be edited on retry.
        if includeGroups { needsGroupRead = false }
        defer {
            if generation == token {
                busy = false; inFlight = []
                // A group panel may have opened while a write-only request was in flight.
                if needsGroupRead && !groupReaders.isEmpty { Task { await automaticRefresh() } }
            }
        }
        do {
            let session = try await account.validSession()
            guard generation == token else { return false }
            await repairWorkOutbox(token: token)
            guard generation == token else { return false }
            let segments = Array((ledger?.declaredWorkPending ?? [:]).values.filter(\.ready)
                .sorted { $0.segmentID.uuidString < $1.segmentID.uuidString }.prefix(50))
            var payload: [String: Any] = fields
            // Old servers ignore these additive fields and retain the tested legacy path.
            payload["syncVersion"] = 2
            payload["includeGroups"] = includeGroups || action != "sync"
            payload["segments"] = try JSONSerialization.jsonObject(with: JSONEncoder().encode(segments))
            if ledger?.serverProgress != nil {
                payload["progressRevision"] = ledger?.progressRevision
                payload["progressMetadataVersion"] = ledger?.progressMetadataVersion
            }
            payload["groupVersion"] = groupVersion
            payload["photoVersions"] = Dictionary(uniqueKeysWithValues: photos.map { ($0.key.uuidString.lowercased(), $0.value.version) })
            payload["timezone"] = current.timezone
            payload["activatedAt"] = current.activatedAt
            payload["events"] = try JSONSerialization.jsonObject(with: JSONEncoder().encode(batch))
            let body = try JSONSerialization.data(withJSONObject: ["p_action": action, "p_payload": payload])
            let data = try await api.request(path: "rest/v1/rpc/social_state", body: body, token: session.access_token)
            guard generation == token, account.session?.user.id == session.user.id else { return false }
            if let object = try JSONSerialization.jsonObject(with: data) as? [String: Any], let message = object["error"] as? String {
                notice = message
                if action == "sync" { failed(AccountFailure(message: message)) }
                return false
            }
            let state = try JSONDecoder().decode(SocialState.self, from: data)
            if state.socialSyncVersion == 2 {
                guard state.progressRevision != nil, state.acknowledgedWork != nil,
                      state.progressIsDelta != nil,
                      state.progressIsDelta != true || ledger?.serverProgress != nil else {
                    throw AccountFailure(message: "Group sync needs a fresh snapshot. Please refresh to retry.")
                }
            }
            try acceptGroups(state)
            ledger?.accept(state, sent: Set(batch.map(\.id)))
            if state.socialSyncVersion == 2 {
                ledger?.acknowledgeDeclaredWork(state.acknowledgedWork ?? [], sent: segments)
            }
            ledger?.progress.reconcile(at: Date(), calendar: calendar)
            invitations = state.invitations ?? []
            invitationNotice = state.invitations == nil ? "Invitations are temporarily unavailable. Refresh to retry." : nil
            syncFailed = false; notice = nil
            declaredWorkSyncVersion = state.declaredWorkSyncVersion ?? 0
            persist()
            succeeded()
            if state.socialSyncVersion != 2 && declaredWorkSyncVersion >= 1 {
                do { try await syncDeclaredWork(api: api, session: session, token: token) }
                catch {
                    guard generation == token else { return false }
                    notice = "Work progress could not sync. It is saved on this Mac for retry."
                    syncFailed = true; failed(error)
                }
            }
            pendingConfirmation = ledger?.pending.isEmpty == false || ledger?.declaredWorkPending?.isEmpty == false
            persist()
            return true
        } catch {
            guard generation == token else { return false }
            pendingConfirmation = true; syncFailed = true; failed(error)
            notice = "Groups could not sync. Progress is saved for retry. \(error.localizedDescription)"
            return false
        }
    }
    private func acceptGroups(_ state: SocialState) throws {
        guard state.groupsIncluded != false else {
            if state.groupVersion != nil { lastGroupRead = Date(); needsGroupRead = false }
            return
        }
        var updated = state.groups
        var retained: [UUID: (version: String, data: Data)] = [:]
        if state.progressIsDelta != nil {
            for g in updated.indices {
                for m in updated[g].members.indices {
                    var member = updated[g].members[m]
                    if let version = member.photoVersion {
                        if member.photo == nil, let cached = photos[member.id], cached.version == version { member.photo = cached.data }
                        guard let data = member.photo else {
                            groupVersion = nil; photos = [:]
                            throw AccountFailure(message: "Group photos need a fresh snapshot. Please refresh to retry.")
                        }
                        retained[member.id] = (version, data)
                    } else { member.photo = nil }
                    updated[g].members[m] = member
                }
            }
        }
        photos = retained; groupVersion = state.groupVersion
        groups = updated; hasLoadedGroups = true; lastGroupRead = Date(); needsGroupRead = false
        selection.reconcile(groups: groups); saveSelection()
    }

    private func syncDeclaredWork(api: AccountAPI, session: AccountSession, token: UUID) async throws {
        await repairWorkOutbox(token: token)
        guard generation == token, userID == session.user.id else { throw CancellationError() }
        guard let ledger else { return }
        let sent = Array((ledger.declaredWorkPending ?? [:]).values.filter(\.ready)
            .sorted { $0.segmentID.uuidString < $1.segmentID.uuidString }.prefix(50))
        guard !sent.isEmpty else { return }
        let segments = try JSONSerialization.jsonObject(with: JSONEncoder().encode(sent))
        let body = try JSONSerialization.data(withJSONObject: ["p_segments": segments, "p_timezone": ledger.timezone])
        let data = try await api.request(path: "rest/v1/rpc/sync_declared_work", body: body, token: session.access_token)
        guard generation == token, userID == session.user.id else { throw CancellationError() }
        let result = try JSONDecoder().decode(DeclaredWorkResponse.self, from: data)
        guard result.version == 1 else { throw AccountFailure(message: "Work sync needs an updated service.") }
        self.ledger?.acknowledgeDeclaredWork(result.acknowledged, sent: sent)
        persist()
        // Read updated scores without repeating create/invite/other user actions or old events.
        let refreshBody = try JSONSerialization.data(withJSONObject: ["p_action": "sync", "p_payload": ["timezone": ledger.timezone]])
        let updated = try await api.request(path: "rest/v1/rpc/social_state", body: refreshBody, token: session.access_token)
        guard generation == token, userID == session.user.id else { throw CancellationError() }
        let state = try JSONDecoder().decode(SocialState.self, from: updated)
        self.ledger?.accept(state, sent: [])
        try acceptGroups(state)
        invitations = state.invitations ?? []
    }

    // Recover the outbox itself, even when the separate daily-progress ledger
    // no longer has an ownership entry that would trigger history reconciliation.
    private func repairWorkOutbox(token: UUID) async {
        guard !repairedWorkOutbox, let pending = ledger?.declaredWorkPending,
              !pending.isEmpty, let scope = declaredWorkScope else { return }
        repairedWorkOutbox = true
        let directory = storageDirectory
        let calendar = calendar
        let incomplete = Set(pending.filter { !$0.value.ready }.keys)
        let repairs = await Task.detached(priority: .utility) {
            var repairs: [(DeclaredWorkPending, SavedSession, RecordingCoverage)] = []
            guard let root = try? directory?.appendingPathComponent("FocusFix/Sessions") ?? SessionFiles.root(),
                  let sessions = try? SessionFiles.list(in: root) else { return repairs }
            for session in sessions {
                guard let contract = session.recordingContract, contract.finalized,
                      let previous = pending[contract.segmentID.uuidString],
                      previous.ownerID == scope.owner, previous.origin == scope.origin, previous.contractVersion == 2,
                      incomplete.contains(contract.segmentID.uuidString) || previous.startedAt != session.startedAt.timeIntervalSince1970,
                      let coverage = try? RecordingCoverage.load(session: session) else { continue }
                repairs.append((previous, session, coverage))
            }
            return repairs
        }.value
        guard generation == token else { return }
        for (previous, session, coverage) in repairs {
            guard ledger?.declaredWorkPending?[previous.segmentID.uuidString] == previous,
                  let contract = session.recordingContract else { continue }
            let replacement = DeclaredWorkPending(ownerID: previous.ownerID, origin: previous.origin,
                segmentID: contract.segmentID, contractVersion: 2,
                days: DailyProgress.declaredAllocation(slices: coverage.workSlices, startedAt: session.startedAt,
                    origin: contract.elapsedOrigin, calendar: calendar),
                startedAt: session.startedAt.timeIntervalSince1970,
                observedThrough: session.startedAt.timeIntervalSince1970 + contract.observedThrough - contract.elapsedOrigin,
                intervals: DeclaredWorkInterval.observed(coverage.workSlices, startedAt: session.startedAt, origin: contract.elapsedOrigin))
            _ = ledger?.stageDeclaredWork(replacement, owner: scope.owner, origin: scope.origin)
        }
        if !repairs.isEmpty { persist() }
    }

    // Inbox access never activates progress sharing or creates a local ledger.
    @discardableResult
    func refreshInvitations(declining id: UUID? = nil) async -> Bool {
        guard !busy, userID != nil, let api = account.api else { return false }
        let token = generation
        busy = true
        defer { if generation == token { busy = false } }
        do {
            let session = try await account.validSession()
            let body = try JSONSerialization.data(withJSONObject: id.map { ["p_invitation": $0.uuidString] } ?? [:])
            let data = try await api.request(path: "rest/v1/rpc/" + (id == nil ? "group_invitations" : "decline_group_invitation"),
                body: body, token: session.access_token)
            guard generation == token, account.session?.user.id == session.user.id else { return false }
            invitations = try JSONDecoder().decode([GroupInvitation].self, from: data)
            invitationNotice = nil; succeeded()
            return true
        } catch {
            if generation == token {
                failed(error)
                invitationNotice = id == nil ? "Invitations could not load. Please refresh to retry." : "Your response could not be saved. Please try again."
            }
            return false
        }
    }

    func respond(to invitation: GroupInvitation, accept: Bool) async {
        guard !busy else { return }
        if !accept { _ = await refreshInvitations(declining: invitation.id); return }
        // The invitation card discloses that accepting also enables summary sync.
        let recipient = userID
        if !enabled { await enable() }
        guard userID == recipient, enabled else { return }
        await refresh(action: "accept", fields: ["invitation": invitation.id.uuidString])
    }

}
