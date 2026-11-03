import Foundation
import ServiceManagement

@MainActor final class FakeLogin: LoginLaunchClient {
    var status: SMAppService.Status = .notRegistered
    var registered = 0
    var unregistered = 0
    var fail = false
    func register() throws {
        registered += 1
        if fail { throw CocoaError(.fileWriteUnknown) }
        status = .requiresApproval
    }
    func unregister() throws { unregistered += 1; status = .notRegistered }
}
@main struct AutomaticRecordingPreferencesTests {
    @MainActor static func main() {
        let suite = "focusfix.test.automatic.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }
        let notice = RecordingNotice(defaults: defaults)
        let fresh = AutomaticRecordingPreferences(defaults: defaults)
        fresh.enable()
        precondition(!fresh.enabled && fresh.acknowledgedAt == nil)
        notice.acknowledge()
        precondition(!fresh.enabled) // Old recording consent and OS permission cannot opt in.
        fresh.enable(at: Date(timeIntervalSince1970: 100))
        precondition(fresh.enabled && fresh.acknowledgedAt == Date(timeIntervalSince1970: 100))
        let oldGeneration = fresh.generation
        fresh.disable()
        precondition(!fresh.enabled && fresh.generation != oldGeneration)
        fresh.enable()
        fresh.setUserPaused(true)
        let restored = AutomaticRecordingPreferences(defaults: defaults)
        precondition(restored.enabled && restored.userPaused)
        notice.decline()
        precondition(!restored.enabled)
        notice.acknowledge()
        // Explicit global recording revocation also calls disable in tracker.
        restored.disable()
        precondition(!AutomaticRecordingPreferences(defaults: defaults).enabled)
        defaults.set(99, forKey: "focusfix.automatic.scopeVersion")
        defaults.set(true, forKey: "focusfix.automatic.enabled")
        precondition(!AutomaticRecordingPreferences(defaults: defaults).enabled)
        let fake = FakeLogin()
        let login = LoginLaunch(client: fake)
        login.refresh()
        precondition(!login.enabled && fake.registered == 0 && fake.unregistered == 0)
        login.setEnabled(true)
        precondition(login.status == .requiresApproval && !login.enabled && fake.registered == 1)
        fake.status = .enabled; login.refresh()
        precondition(login.enabled)
        login.setEnabled(false)
        precondition(!login.enabled && fake.unregistered == 1)
        fake.fail = true; login.setEnabled(true)
        precondition(!login.enabled && login.error != nil)
        print("PASS: explicit automatic scope, old-install/manual default, revoke, persistent pause, callback generation and fake login registration/failure")
    }
}
