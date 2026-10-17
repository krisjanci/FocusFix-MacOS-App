import Foundation

// Keep permission decisions separate from macOS so they can be tested without
// showing real permission dialogs or changing someone's notification settings.
enum NotificationPermission: Equatable {
    case checking, notDetermined, denied, quiet, enabled, unavailable

    var needsAttention: Bool { self != .checking && self != .enabled }
    var opensSettings: Bool { self == .denied || self == .quiet }
}

@MainActor
protocol NotificationPermissionClient {
    func status() async -> NotificationPermission
    func request() async throws
}

@MainActor
final class NotificationAccess {
    private let client: any NotificationPermissionClient
    private(set) var state: NotificationPermission = .checking
    private(set) var busy = false
    var onChange: ((NotificationPermission, Bool) -> Void)?

    init(client: any NotificationPermissionClient) { self.client = client }

    func refresh() async {
        guard !busy else { return }
        busy = true
        publish()
        state = await client.status()
        busy = false
        publish()
    }

    // Only an explicit button press calls this. Starting a session never asks.
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

    private func publish() { onChange?(state, busy) }
}
