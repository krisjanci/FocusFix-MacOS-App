// MARK: - FF: WELCOME
// One shared startup decision gates the collector and menu-bar recording controls.
import Foundation
import Combine

@MainActor
final class LaunchCoordinator: ObservableObject {
    enum Page: Equatable { case welcome, createAccount, login, restoring, profileSetup, app }
    static let shared = LaunchCoordinator(account: .shared)
    @Published private(set) var page: Page
    let account: AccountController
    private let defaults: UserDefaults
    private static let guestKey = "focusfix.launch.guest"
    private var started = false
    private var restoreTask: Task<Void, Never>?
    private var observation: AnyCancellable?
    private var generation = UUID()

    var canRecord: Bool { page == .app }

    init(account: AccountController, defaults: UserDefaults = .standard) {
        self.account = account
        self.defaults = defaults
        // Rendering this state never accesses Keychain or the network.
        page = defaults.bool(forKey: Self.guestKey) ? .app : .welcome
        observation = account.$session.sink { [weak self] session in
            guard let self else { return }
            if session != nil {
                self.defaults.set(false, forKey: Self.guestKey)
                if self.page != .app {
                    self.page = self.account.isNewAccount ? .profileSetup : .app
                }
            } else if self.page == .app || self.page == .profileSetup {
                // Explicit sign-out leaves a working guest app; it doesn't erase local data.
                self.defaults.set(true, forKey: Self.guestKey)
                self.page = .app
            }
        }
    }

    // Start restoration only once and only after the existing intro finishes.
    func begin() {
        guard !started else { return }
        started = true
        guard account.session == nil else { page = .app; return }
        if account.remembersSignIn && account.configured { restore() }
    }

    func showAccount(create: Bool) {
        guard account.configured else { return }
        page = create ? .createAccount : .login
    }

    func showWelcome() {
        guard !account.busy else { return }
        page = .welcome
    }

    func restore() {
        guard account.configured, !account.busy else { return }
        generation = UUID()
        let token = generation
        page = .restoring
        restoreTask = Task { [weak self] in
            guard let self else { return }
            await self.account.restore()
            guard self.generation == token, !Task.isCancelled else { return }
            if self.account.session == nil { self.page = .welcome }
            self.restoreTask = nil
        }
    }

    func useGuest() {
        generation = UUID()
        restoreTask?.cancel()
        restoreTask = nil
        account.continueAsGuest()
        defaults.set(true, forKey: Self.guestKey)
        page = .app
    }

    func finishProfileSetup() { page = .app }

    // An unresolved launch must not request recording permission or start a survey.
    func requestStart(start: () -> Void, showWindow: () -> Void) {
        guard canRecord else { showWindow(); return }
        start()
    }
}
