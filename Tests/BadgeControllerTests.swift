import Foundation

@main struct BadgeControllerTests {
    @MainActor static func main() async throws {
        let content = BadgeController.notificationContent(for: FocusBadge.all[1])
        precondition(content.title == "You've gained a badge!" && content.body == "Full Week")
        precondition(content.userInfo["focusfix_badge"] as? String == "work-5")
        let suite = "focusfix-badge-tests-\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }
        let tracker = ActivityTracker()
        var sent: [String] = []
        let controller = BadgeController(defaults: defaults, deliverNotification: { sent.append($0.id) })
        controller.start(tracker: tracker)
        precondition(!controller.hasUnread && controller.celebration == nil)
        precondition(!controller.isEarned(FocusBadge.all[0]))
        let calendar = DailyProgress.calendar()
        let today = calendar.date(bySettingHour: 14, minute: 0, second: 0, of: Date())!
        var progress = DailyProgress()
        progress.reconcile(at: calendar.date(byAdding: .day, value: -4, to: today)!, calendar: calendar)
        for offset in -4...0 {
            progress.addWork(seconds: 3600, endingAt: calendar.date(byAdding: .day, value: offset, to: today)!, calendar: calendar)
        }
        tracker.dailyProgress = progress
        precondition(sent == ["work-5"] && controller.celebration?.id == "work-5" && controller.hasUnread)
        tracker.dailyProgress = progress
        precondition(sent.count == 1, "Repeated publications must not repeat notifications")
        let queuedAfterRestart = BadgeController(defaults: defaults, deliverNotification: { _ in })
        precondition(queuedAfterRestart.celebration?.id == "work-5" && queuedAfterRestart.hasUnread)
        controller.dismissCelebration(FocusBadge.all[1])
        precondition(controller.celebration == nil && controller.hasUnread, "Celebrating does not mark a badge as seen")
        var restoredSent: [String] = []
        let restored = BadgeController(defaults: defaults, deliverNotification: { restoredSent.append($0.id) })
        restored.start(tracker: tracker)
        precondition(restored.hasUnread && restored.isEarned(FocusBadge.all[1]) && restoredSent.isEmpty)
        restored.openCollection()
        precondition(!restored.hasUnread)
        let reread = BadgeController(defaults: defaults, deliverNotification: { _ in })
        precondition(!reread.hasUnread)
        let account = AccountController.shared
        account.session = .init(user: .init(id: UUID()))
        for _ in 0..<10 { await Task.yield() }
        precondition(controller.isEarned(FocusBadge.all[0]) && controller.hasUnread)
        precondition(sent == ["work-5", "joined"])
        controller.openCollection()
        precondition(!controller.hasUnread && controller.celebration == nil)
        account.session = nil
        for _ in 0..<10 { await Task.yield() }
        precondition(!controller.isEarned(FocusBadge.all[0]))
        precondition(controller.isEarned(FocusBadge.all[1]))
        var century = DailyProgress()
        let first = calendar.date(byAdding: .day, value: -99, to: today)!
        century.reconcile(at: first, calendar: calendar)
        for offset in -99...0 {
            century.addWork(seconds: 3600, endingAt: calendar.date(byAdding: .day, value: offset, to: today)!, calendar: calendar)
        }
        tracker.dailyProgress = century
        precondition(controller.celebration?.id == "work-10")
        precondition(controller.awards.pending == ["work-10", "work-20", "work-30", "work-50", "work-75", "work-100"])
        controller.dismissCelebration(FocusBadge.all[2])
        precondition(controller.celebration?.id == "work-20" && controller.hasUnread)
        controller.openCollection()
        precondition(controller.celebration == nil && !controller.hasUnread)
        print("Badge controller tests passed: live awards, duplicate prevention, durable unread/queues, sign-in and guest boundaries")
    }
}
