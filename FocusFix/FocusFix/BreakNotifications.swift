import Foundation
import UserNotifications

@MainActor
struct SystemNotificationPermissionClient: NotificationPermissionClient {
    func status() async -> NotificationPermission {
        let settings = await UNUserNotificationCenter.current().notificationSettings()
        switch settings.authorizationStatus {
        case .notDetermined: return .notDetermined
        case .denied: return .denied
        case .authorized, .provisional, .ephemeral:
            return settings.alertSetting == .enabled && settings.alertStyle != .none ? .enabled : .quiet
        @unknown default: return .unavailable
        }
    }
    func request() async throws {
        _ = try await UNUserNotificationCenter.current().requestAuthorization(options: [.alert])
    }
}

// Native notifications are optional: the same actions remain in the app/menu bar.
@MainActor
final class BreakNotifications: NSObject, UNUserNotificationCenterDelegate {
    var onAction: ((String, String, String) -> Void)?
    var onStatus: ((String?) -> Void)?
    private let center = UNUserNotificationCenter.current()
    private var generation = 0

    func configure() {
        center.delegate = self
        let take = UNNotificationAction(identifier: "take", title: "Take a break", options: [.foreground])
        let skip = UNNotificationAction(identifier: "skip", title: "Skip", options: [])
        let snooze = UNNotificationAction(identifier: "snooze", title: "Snooze 10 min", options: [])
        let back = UNNotificationAction(identifier: "back", title: "I'm back", options: [.foreground])
        center.setNotificationCategories([
            UNNotificationCategory(identifier: "break_prompt", actions: [take, skip, snooze], intentIdentifiers: []),
            UNNotificationCategory(identifier: "break_finished", actions: [back], intentIdentifiers: [])
        ])
        clear()
    }
    func send(session: String, token: String, finished: Bool) {
        let version = generation
        let id = "focusfix-\(session)-\(token)-\(finished ? "end" : "prompt")"
        let content = UNMutableNotificationContent()
        content.title = finished ? "Your break timer has finished" : "A moment for a break?"
        content.body = finished ? "Return when you're ready. Extra time away is included in your break." : "Take a short break, skip, or snooze for 10 minutes."
        content.categoryIdentifier = finished ? "break_finished" : "break_prompt"
        content.userInfo = ["session": session, "token": token]
        // No sound, no forced foreground window, and only one prompt per decision.
        Task {
            do {
                try await center.add(UNNotificationRequest(identifier: id, content: content, trigger: nil))
                if generation != version {
                    center.removePendingNotificationRequests(withIdentifiers: [id])
                    center.removeDeliveredNotifications(withIdentifiers: [id])
                }
            } catch { onStatus?("Couldn't deliver the notification. The break controls are still available in FocusFix.") }
        }
    }
    func clear() {
        generation += 1
        center.removeAllPendingNotificationRequests()
        center.removeAllDeliveredNotifications()
    }
    nonisolated func userNotificationCenter(_ center: UNUserNotificationCenter,
        willPresent notification: UNNotification, withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void) {
        completionHandler([.banner, .list])
    }
    nonisolated func userNotificationCenter(_ center: UNUserNotificationCenter,
        didReceive response: UNNotificationResponse, withCompletionHandler completionHandler: @escaping () -> Void) {
        let info = response.notification.request.content.userInfo
        let session = info["session"] as? String ?? ""
        let token = info["token"] as? String ?? ""
        let action = response.actionIdentifier
        Task { @MainActor [weak self] in
            self?.onAction?(session, token, action)
            completionHandler()
        }
    }
}
