import Foundation
import Combine

@MainActor
final class SocialController: ObservableObject {
    static let shared = SocialController(account: .shared)
    @Published private(set) var ledger: SocialLedger?
    @Published private(set) var groups: [SocialGroup] = []
    @Published private(set) var busy = false
    @Published private(set) var notice: String?
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
            if incomingKey != self.identity { self.clearAccountState() }
            if self.started { Task { @MainActor in self.alignAccount(); await self.refresh() } }
        }.store(in: &subscriptions)
    }
    private var identitySince = Date()
    private var identity: String?
    private var file: URL?
    private var generation = UUID()
    private var subscriptions: Set<AnyCancellable> = []
    private var inFlight: Set<UUID> = []
    private var started = false

    var enabled: Bool { ledger != nil }
    var calendar: Calendar { DailyProgress.calendar(timeZone: TimeZone(identifier: ledger?.timezone ?? "") ?? .current) }
    var userID: UUID? { account.session?.user.id }

    func start() {
        guard !started else { return }; started = true
        Timer.publish(every: 30, on: .main, in: .common).autoconnect().sink { [weak self] _ in
            Task { @MainActor in await self?.refresh() }
        }.store(in: &subscriptions)
        NotificationCenter.default.publisher(for: Notification.Name("FocusFixAccountDeleted")).sink { [weak self] note in
            guard let id = note.userInfo?["userID"] as? UUID, let origin = note.userInfo?["origin"] as? URL else { return }
            Task { @MainActor in self?.discardCache(userID: id, origin: origin) }
        }.store(in: &subscriptions)
        alignAccount()
        Task { await refresh() }
    }

    var selectedGroup: SocialGroup? { groups.first { $0.id == selection.groupID } ?? groups.first }
    var accessState: GroupAccessState {
        GroupAccessState.resolve(signedIn: userID != nil, enabled: enabled, busy: busy,
            loaded: hasLoadedGroups, failed: syncFailed, notice: notice != nil)
    }
    func selectGroup(_ id: UUID) {
        guard groups.contains(where: { $0.id == id }) else { return }
        selection.groupID = id; saveSelection()
    }
    func selectMetric(_ metric: LeaderboardMetric) { selection.metric = metric; saveSelection() }
    private func selectionKey(_ identity: String) -> String { "focusfix.groups.selection." + identity }
    private func saveSelection() {
        guard let identity, let data = try? JSONEncoder().encode(selection) else { return }
        selectionDefaults?.set(data, forKey: selectionKey(identity))
    }
    private func clearAccountState() {
        generation = UUID(); identitySince = Date(); identity = nil; file = nil
        ledger = nil; groups = []; selection = GroupSelection(); notice = nil
        busy = false; inFlight = []; pendingConfirmation = false; hasLoadedGroups = false; syncFailed = false
    }
    func retry() async {
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
                pendingConfirmation = true
            }
        } catch { notice = "Group progress could not be opened. Your existing file has been kept." }
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
        guard let file, let ledger else { return }
        do {
            try FileManager.default.createDirectory(at: file.deletingLastPathComponent(), withIntermediateDirectories: true,
                                                    attributes: [.posixPermissions: 0o700])
            try JSONEncoder().encode(ledger).write(to: file, options: .atomic)
        } catch { notice = "Progress could not be saved on this Mac. Keep FocusFix open and retry." }
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
    func refresh(action: String = "sync", fields: [String: String] = [:]) async -> Bool {
        alignAccount()
        guard !busy, let current = ledger, let api = account.api else { return false }
        let token = generation; busy = true
        let batch = Array(current.pending.prefix(200)); inFlight = Set(batch.map(\.id))
        ledger?.submitted.formUnion(inFlight)
        persist() // A lost response must never allow a submitted summary to be edited on retry.
        defer { if generation == token { busy = false; inFlight = [] } }
        do {
            let session = try await account.validSession()
            guard generation == token else { return false }
            var payload: [String: Any] = fields
            payload["timezone"] = current.timezone
            payload["activatedAt"] = current.activatedAt
            payload["events"] = try JSONSerialization.jsonObject(with: JSONEncoder().encode(batch))
            let body = try JSONSerialization.data(withJSONObject: ["p_action": action, "p_payload": payload])
            let data = try await api.request(path: "rest/v1/rpc/social_state", body: body, token: session.access_token)
            guard generation == token, account.session?.user.id == session.user.id else { return false }
            if let object = try JSONSerialization.jsonObject(with: data) as? [String: Any], let message = object["error"] as? String {
                notice = message; return false
            }
            let state = try JSONDecoder().decode(SocialState.self, from: data)
            ledger?.accept(state, sent: Set(batch.map(\.id)))
            ledger?.progress.reconcile(at: Date(), calendar: calendar)
            groups = state.groups; hasLoadedGroups = true; syncFailed = false
            selection.reconcile(groups: groups); saveSelection()
            notice = nil
            pendingConfirmation = ledger?.pending.isEmpty == false
            persist()
            return true
        } catch {
            guard generation == token else { return false }
            pendingConfirmation = true; syncFailed = true
            notice = "Groups could not sync. Progress is saved for retry. \(error.localizedDescription)"
            return false
        }
    }
}
