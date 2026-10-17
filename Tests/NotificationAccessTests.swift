import Foundation

@MainActor
final class FakeNotificationClient: NotificationPermissionClient {
    enum Failure: Error { case unavailable }
    var permission: NotificationPermission = .notDetermined
    var response: NotificationPermission = .enabled
    var requests = 0
    var fails = false
    var duringRequest: (() async -> Void)?
    func status() async -> NotificationPermission { permission }
    func request() async throws {
        requests += 1
        await duringRequest?()
        if fails { throw Failure.unavailable }
        permission = response
    }
}

@main
struct NotificationAccessTests {
    @MainActor
    static func main() async {
        let client = FakeNotificationClient()
        let access = NotificationAccess(client: client)
        var updates: [(NotificationPermission, Bool)] = []
        access.onChange = { updates.append(($0, $1)) }
        precondition(!access.state.needsAttention)

        await access.refresh()
        precondition(access.state == .notDetermined && access.state.needsAttention)
        precondition(client.requests == 0) // Checking/launching never asks macOS.
        precondition(!access.state.opensSettings)
        client.duringRequest = {
            // A second click or app-activation refresh during the OS dialog is ignored.
            precondition(access.busy)
            await access.enable()
            await access.refresh()
        }
        await access.enable()
        precondition(client.requests == 1 && access.state == .enabled && !access.busy)
        precondition(!access.state.needsAttention)
        precondition(updates.contains { $0.1 } && updates.last?.1 == false)
        await access.enable()
        precondition(client.requests == 1) // Already allowed: no repeated request.

        client.permission = .denied
        await access.refresh()
        precondition(access.state.needsAttention && access.state.opensSettings)
        await access.enable()
        precondition(client.requests == 1) // A denial requires Settings, not another dialog.
        client.permission = .quiet
        await access.refresh()
        precondition(access.state.needsAttention && access.state.opensSettings)
        client.permission = .enabled
        await access.refresh()
        precondition(!access.state.needsAttention) // Returning from Settings removes the card.

        client.permission = .notDetermined
        client.response = .denied
        await access.enable()
        precondition(access.state == .denied && !access.busy)
        client.permission = .notDetermined
        client.fails = true
        await access.enable()
        precondition(access.state == .unavailable && access.state.needsAttention && !access.busy)
        client.fails = false
        client.response = .enabled
        await access.enable()
        precondition(access.state == .enabled && !access.busy) // Retry after transient failure.
        print("PASS: notification onboarding, explicit permission requests, denial, banners off, settings refresh, duplicate clicks, failure and retry.")
    }
}
