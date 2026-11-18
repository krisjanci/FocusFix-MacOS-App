import AppKit
import Combine
import UserNotifications

@MainActor
final class BadgeController: ObservableObject {
    static let shared = BadgeController()
    @Published private(set) var awards: BadgeAwards
    @Published var collectionRequest = UUID()
    private let defaults: UserDefaults
    private let storageKey = "focusfix.badges.v1"
    private var subscriptions: Set<AnyCancellable> = []
    private var started = false
    private var lastProgress: DailyProgress?
    private var lastDay: String?
    private var account: AccountController { .shared }
    private var joinedKey: String? {
        guard let id = account.session?.user.id else { return nil }
        return "joined|\(account.api?.configuration.origin.absoluteString ?? "")|\(id)"
    }
    private var visibleKeys: Set<String> {
        Set(FocusBadge.all.filter { $0.days > 0 }.map(\.id)).union(joinedKey.map { [$0] } ?? [])
    }
    var hasUnread: Bool { !awards.unread.intersection(visibleKeys).isEmpty }
    var celebration: FocusBadge? {
        guard let key = awards.pending.first(where: { visibleKeys.contains($0) }) else { return nil }
        return FocusBadge.all.first { $0.id == key || ($0.id == "joined" && key == joinedKey) }
    }
    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        awards = defaults.data(forKey: storageKey).flatMap { try? JSONDecoder().decode(BadgeAwards.self, from: $0) } ?? BadgeAwards()
    }
    func start(tracker: ActivityTracker) {
        guard !started else { return }; started = true
        update(tracker.dailyProgress)
        tracker.$dailyProgress.dropFirst().sink { [weak self] in self?.update($0) }.store(in: &subscriptions)
        account.$session.dropFirst().sink { [weak self] _ in
            // Published session emits before assignment; resolve the identity on the next main-actor turn.
            Task { @MainActor in
                guard let self else { return }
                self.objectWillChange.send()
                self.issue(streak: 0)
            }
        }.store(in: &subscriptions)
        NotificationCenter.default.publisher(for: Notification.Name("FocusFixAccountDeleted")).sink { [weak self] note in
            guard let self, let id = note.userInfo?["userID"] as? UUID,
                  let origin = note.userInfo?["origin"] as? URL else { return }
            let key = "joined|\(origin.absoluteString)|\(id)"
            self.awards.earned.remove(key); self.awards.unread.remove(key)
            self.awards.pending.removeAll { $0 == key }; self.save()
        }.store(in: &subscriptions)
    }
    private func update(_ progress: DailyProgress) {
        let calendar = DailyProgress.calendar()
        let today = DailyProgress.key(for: Date(), calendar: calendar)
        guard progress != lastProgress || today != lastDay else { return }
        let historical = !awards.initialized
        // Scan history only on initial migration or a ledger correction; live work only changes today's row.
        let historyChanged = lastProgress.map { previous in
            previous.days.filter { $0.key != today } != progress.days.filter { $0.key != today }
        } ?? true
        let best = historyChanged ? BadgeAwards.historicalBest(progress, calendar: calendar) : 0
        lastProgress = progress; lastDay = today
        issue(streak: max(best, progress.streakStatus(at: Date(), calendar: calendar).count), historical: historical)
    }
    private func issue(streak: Int, historical: Bool = false) {
        let added = awards.award(streak: streak, joinedKey: joinedKey, historical: historical)
        save()
        for badge in added {
            let content = UNMutableNotificationContent()
            content.title = "You've gained a badge!"; content.body = badge.name
            content.userInfo = ["focusfix_badge": badge.id]
            Task {
                let center = UNUserNotificationCenter.current()
                let settings = await center.notificationSettings()
                guard settings.authorizationStatus == .authorized || settings.authorizationStatus == .provisional else { return }
                try? await center.add(UNNotificationRequest(identifier: "focusfix-badge-\(UUID().uuidString)", content: content, trigger: nil))
            }
        }
    }
    func isEarned(_ badge: FocusBadge) -> Bool {
        guard let key = badge.days == 0 ? joinedKey : badge.id else { return false }
        return awards.earned.contains(key)
    }
    func openCollection() {
        awards.unread.subtract(visibleKeys)
        // Opening the collection acknowledges queued celebrations as well.
        awards.pending.removeAll { visibleKeys.contains($0) }
        save()
    }
    func dismissCelebration(_ badge: FocusBadge) {
        let key = badge.days == 0 ? joinedKey : badge.id
        awards.pending.removeAll { $0 == key }; save()
    }
    func requestCollection() {
        collectionRequest = UUID()
        ActivityTracker.shared.openMainWindow?()
        NSApp.activate(ignoringOtherApps: true)
    }
    private func save() {
        if let data = try? JSONEncoder().encode(awards) { defaults.set(data, forKey: storageKey) }
    }
}
