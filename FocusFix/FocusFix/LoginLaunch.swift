import Foundation
import Combine
import ServiceManagement

@MainActor protocol LoginLaunchClient {
    var status: SMAppService.Status { get }
    func register() throws
    func unregister() throws
}
@MainActor struct SystemLoginLaunchClient: LoginLaunchClient {
    var status: SMAppService.Status { SMAppService.mainApp.status }
    func register() throws { try SMAppService.mainApp.register() }
    func unregister() throws { try SMAppService.mainApp.unregister() }
}
@MainActor final class LoginLaunch: ObservableObject {
    @Published private(set) var status: SMAppService.Status = .notRegistered
    @Published private(set) var error: String?
    private let client: any LoginLaunchClient
    init(client: (any LoginLaunchClient)? = nil) { self.client = client ?? SystemLoginLaunchClient(); refresh() }
    var enabled: Bool { status == .enabled }
    var requested: Bool { status == .enabled || status == .requiresApproval }
    var explanation: String {
        switch status {
        case .enabled: "FocusFix will open at login. Recording still follows your consent and pause choices."
        case .requiresApproval: "Allow FocusFix in System Settings → General → Login Items to finish setup."
        case .notFound: "macOS could not locate this app as a login item. Try a stable installed, signed copy."
        default: "Off. Enable this to open FocusFix at login. Closing its window keeps the menu-bar app running; Quit stops it."
        }
    }
    func refresh() { status = client.status }
    // Merely reading/showing settings never changes OS registration.
    func setEnabled(_ enabled: Bool) {
        error = nil
        do { if enabled { try client.register() } else { try client.unregister() } }
        catch { self.error = error.localizedDescription }
        refresh()
    }
}
