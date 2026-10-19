// MARK: - FF: NOTIFICATIONS
// Creates quiet macOS reminders and routes their buttons back to FocusFix. The OS can still delay or hide banners.

import Foundation
import UserNotifications

@MainActor
struct SystemNotificationPermissionClient: NotificationPermissionClient {
    // Translate macOS notification settings into the app's permission states.
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
    // Ask macOS to allow notification alerts.
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
    private var breakIDs: Set<String> = []
    private var checkInID: String?
    private var checkInGeneration = 0

    // Register break/check-in action buttons and remove stale notifications from earlier runs.
    func configure() {
        center.delegate = self
        let take = UNNotificationAction(identifier: "take", title: "Take a break", options: [.foreground])
        let skip = UNNotificationAction(identifier: "skip", title: "Skip", options: [])
        let snooze = UNNotificationAction(identifier: "snooze", title: "Snooze 10 min", options: [])
        let back = UNNotificationAction(identifier: "back", title: "I'm back", options: [.foreground])
        let answer = UNNotificationAction(identifier: "answer_check_in", title: "Answer", options: [.foreground])
        let skipCheckIn = UNNotificationAction(identifier: "skip_check_in", title: "Skip", options: [])
        center.setNotificationCategories([
            UNNotificationCategory(identifier: "break_prompt", actions: [take, skip, snooze], intentIdentifiers: []),
            UNNotificationCategory(identifier: "break_finished", actions: [back], intentIdentifiers: []),
            UNNotificationCategory(identifier: "work_check_in", actions: [answer, skipCheckIn], intentIdentifiers: [])
        ])
        clear()
    }
    // Show either a break suggestion or a break-timer-finished banner for the current prompt.
    func send(session: String, token: String, finished: Bool) {
        let version = generation
        let id = "focusfix-\(session)-\(token)-\(finished ? "end" : "prompt")"
        breakIDs.insert(id)
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
    // Remove both kinds of reminders and invalidate pending notification callbacks.
    func clear() {
        clearBreaks()
        clearCheckIn()
        // On launch/start/stop also remove leftovers from earlier app runs.
        center.removeAllPendingNotificationRequests()
        center.removeAllDeliveredNotifications()
    }
    // Remove break reminders without clearing a separate survey reminder.
    func clearBreaks() {
        generation += 1
        center.removePendingNotificationRequests(withIdentifiers: Array(breakIDs))
        center.removeDeliveredNotifications(withIdentifiers: Array(breakIDs))
        breakIDs.removeAll()
    }
    // Show an Answer/Skip notification; the sliders themselves open in the app.
    func sendCheckIn(session: String, token: String) {
        clearCheckIn()
        let version = checkInGeneration
        let id = "focusfix-\(session)-\(token)-check-in"
        checkInID = id
        let content = UNMutableNotificationContent()
        content.title = "Time for a check-in"
        content.body = "Mental fatigue and productivity"
        content.categoryIdentifier = "work_check_in"
        content.userInfo = ["session": session, "token": token]
        Task {
            do {
                try await center.add(UNNotificationRequest(identifier: id, content: content, trigger: nil))
                if version != checkInGeneration {
                    center.removePendingNotificationRequests(withIdentifiers: [id])
                    center.removeDeliveredNotifications(withIdentifiers: [id])
                }
            } catch {
                onStatus?("Couldn't deliver the check-in notification. You can answer it in FocusFix or the menu bar.")
            }
        }
    }
    // Remove only the check-in notification and invalidate its pending callbacks.
    func clearCheckIn() {
        checkInGeneration += 1
        if let checkInID {
            center.removePendingNotificationRequests(withIdentifiers: [checkInID])
            center.removeDeliveredNotifications(withIdentifiers: [checkInID])
        }
        checkInID = nil
    }
    // Allow a banner/list entry even while FocusFix is the foreground app.
    nonisolated func userNotificationCenter(_ center: UNUserNotificationCenter,
        willPresent notification: UNNotification, withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void) {
        completionHandler([.banner, .list])
    }
    // Forward a clicked notification action to the main thread with its session and prompt IDs.
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
