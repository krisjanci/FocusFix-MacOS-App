// MARK: - FF: NOTIFICATIONS
// Keeps permission state separate from recording, so recording can still work without notification banners.

import Foundation

// Keep permission decisions separate from macOS so they can be tested without
// showing real permission dialogs or changing someone's notification settings.
enum NotificationPermission: Equatable {
    case checking, notDetermined, denied, quiet, enabled, unavailable

    // Whether the UI should offer help enabling notification banners.
    var needsAttention: Bool { self != .checking && self != .enabled }
    // Whether permission must be changed in System Settings rather than requested again.
    var opensSettings: Bool { self == .denied || self == .quiet }
}

@MainActor
protocol NotificationPermissionClient {
    // Read the notification permission state without showing a permission dialog.
    func status() async -> NotificationPermission
    // Request permission through the system's notification service.
    func request() async throws
}

@MainActor
final class NotificationAccess {
    private let client: any NotificationPermissionClient
    private(set) var state: NotificationPermission = .checking
    private(set) var busy = false
    var onChange: ((NotificationPermission, Bool) -> Void)?

    // Accept a real or fake permission service so permission behavior can be tested.
    init(client: any NotificationPermissionClient) { self.client = client }

    // Refresh permission state while preventing overlapping permission checks.
    func refresh() async {
        guard !busy else { return }
        busy = true
        publish()
        state = await client.status()
        busy = false
        publish()
    }

    // Only an explicit button press calls this. Starting a session never asks.
    // Request permission only when needed, then publish the resulting state or an unavailable state.
    func enable() async {
        guard !busy else { return }
        busy = true
        publish()
        state = await client.status()
        if state == .notDetermined {
            do {
                try await client.request()
                state = await client.status()
            } catch { state = .unavailable }
        }
        busy = false
        publish()
    }

    // Notify the UI about the current permission and busy state.
    private func publish() { onChange?(state, busy) }
}
