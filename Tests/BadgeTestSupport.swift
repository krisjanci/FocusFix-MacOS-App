// Synthetic stand-ins: badge tests/previews never construct the real tracker or account client.
import Foundation
import Combine

@MainActor final class ActivityTracker: ObservableObject {
    static let shared = ActivityTracker()
    @Published var dailyProgress = DailyProgress()
    var openMainWindow: (() -> Void)?
}
@MainActor final class AccountController: ObservableObject {
    static let shared = AccountController()
    struct User { let id: UUID }
    struct Session { let user: User }
    struct Configuration { let origin = URL(string: "https://badges.invalid")! }
    struct API { let configuration = Configuration() }
    let api: API? = API()
    @Published var session: Session?
}
