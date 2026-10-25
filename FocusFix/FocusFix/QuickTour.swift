import Foundation
import Combine

// Offline teaching content only. No recording, authentication, or sharing dependencies.
struct QuickTourStep: Identifiable {
    let id: String
    let title: String
    let subtitle: String
    let symbol: String
    let exampleTitle: String
    let exampleDetail: String
    let tips: [Tip]

    struct Tip {
        let title: String
        let detail: String
    }

    var target: QuickTourTarget {
        switch id {
        case "start": return .start
        case "work": return .timer
        case "break": return .breaks
        case "progress": return .progress
        case "sessions": return .sessions
        case "personalize": return .profile
        default: return .overview
        }
    }

    static let all: [QuickTourStep] = [
        .init(id: "meet", title: "Meet FocusFix", subtitle: "A little structure for work and recovery.",
            symbol: "leaf.circle", exampleTitle: "Focus → Recharge → Return",
            exampleDetail: "You decide when to start, take a break, and stop.", tips: [
                .init(title: "Build your rhythm", detail: "Record work, plan breaks, and reflect with optional check-ins. FocusFix records activity timing—not typed text or screenshots—and does not diagnose fatigue."),
                .init(title: "Guest is ready", detail: "Use as guest gives you local recording, profiles, and progress. Accounts are optional and available only in connected builds."),
                .init(title: "Sharing is a separate choice", detail: "Recordings stay on this Mac unless you export or enable approved research sharing. Creating an account does not opt you into research.")
            ]),
        .init(id: "start", title: "Start and plan", subtitle: "Set an intention for this session, if you like.",
            symbol: "calendar.badge.clock", exampleTitle: "Planned session · 0 / 60 min",
            exampleDetail: "A fresh, optional plan for each start.", tips: [
                .init(title: "Get set up", detail: "On first use, review Before recording, then press Start session again. If monitoring is unavailable, choose Enable Input Monitoring and allow FocusFix in System Settings → Privacy & Security."),
                .init(title: "Choose your plan", detail: "Before you start offers Plan session: choose 30, 60, 90 minutes, or Custom (1–480 whole minutes). Remove plan clears the target; Cancel discards this start attempt."),
                .init(title: "Answer or skip", detail: "If the fatigue survey is on, choose a rating or Skip & start. Skipping keeps your plan. With the survey off, simply choose Start session. Nothing records until a session starts.")
            ]),
        .init(id: "work", title: "Work normally", subtitle: "Reading quietly is work, too.",
            symbol: "book", exampleTitle: "Session time · 00:25:00",
            exampleDetail: "Planned session · 18 / 60 min. Credited work excludes breaks.", tips: [
                .init(title: "Know your timers", detail: "The main timer shows total session time. Planned work and daily progress include quiet reading but exclude breaks, open check-ins, sleep, and screen lock."),
                .init(title: "Keep the window out of your way", detail: "Closing the main window leaves recording running. Use the FocusFix menu-bar icon to reopen it, take a break, or Stop & save. Stop before tasks you don't want recorded."),
                .init(title: "Check in when it suits you", detail: "An optional check-in becomes available about 10 minutes after starting or returning from a break. Choose Answer or Skip; notifications are optional, and controls remain in the app.")
            ]),
        .init(id: "break", title: "Take a break", subtitle: "Choose something that helps you recharge.",
            symbol: "cup.and.saucer", exampleTitle: "5 minutes · Stretch",
            exampleDetail: "A walk, water, or a moment away from the screen.", tips: [
                .init(title: "Make room to recharge", detail: "Choose Take a break, then an activity and 5, 10, 15, or Custom minutes (1–120). Answer optional ratings or use Skip ratings & start break."),
                .init(title: "Return your way", detail: "Choose I'm back when ready. Meaningful typing, clicking, scrolling, or pointer movement in another app can also finish the break automatically, including an early return."),
                .init(title: "Understand the timer", detail: "Detailed activity tracking pauses during the planned break. It resumes when the timer ends or you return early. Your break remains open until a return is detected or you choose I'm back.")
            ]),
        .init(id: "progress", title: "Understand your progress", subtitle: "Small, consistent steps add up.",
            symbol: "chart.bar", exampleTitle: "Today · 32 / 60 min",
            exampleDetail: "Daily progress adds work across all your sessions.", tips: [
                .init(title: "Build a weekday streak", detail: "Reach 60 minutes of work to earn a weekday streak day. Weekends are optional: they neither increase nor break your streak. The daily goal stays separate from your session plan."),
                .init(title: "Give breaks credit", detail: "A break lasting at least one minute counts when you return, early or late. Stopping the session during a break doesn't earn break credit."),
                .init(title: "Finish on your terms", detail: "At your session target, Plan complete offers Stop & save or Keep going. Recording continues until you stop; Keep going acknowledges the reminder without resetting your work.")
            ]),
        .init(id: "sessions", title: "Save and find sessions", subtitle: "Your recordings are already being saved locally.",
            symbol: "folder", exampleTitle: "Stop & save → Sessions",
            exampleDetail: "Export only when you want a separate copy.", tips: [
                .init(title: "Finish your recording", detail: "Choose Stop & save from the main window or menu bar. Sessions are saved automatically on this Mac; exporting after every session is unnecessary."),
                .init(title: "Find or export", detail: "Open Sessions and select a recording. Show in Finder reveals its folder. Export… creates a separate copy of a finished session in a location you choose."),
                .init(title: "Delete deliberately", detail: "Delete… moves a saved session to Trash. Exports, backups, and already uploaded copies remain separate. Deleting a recording does not remove earned daily progress.")
            ]),
        .init(id: "personalize", title: "Make it yours", subtitle: "Adjust the details, then get back to your day.",
            symbol: "person.crop.circle", exampleTitle: "Profile · Your name, your photo",
            exampleDetail: "Click your name to edit it in place.", tips: [
                .init(title: "Personalize your profile", detail: "Click the profile button, then your name or Add your name. Click the photo circle to add or replace a picture; Remove photo clears it. Save profile applies changes; Cancel discards them."),
                .init(title: "Choose your preferences", detail: "Profile lets you switch surveys on or off for your next session. The main window's appearance menu offers System, Light, and Dark. Account profiles sync only when connected and saved."),
                .init(title: "Come back anytime", detail: "Profile → Advanced → Preview welcome screen lets you explore account layouts without changing your account or history. Replay this Quick tour from Profile, Welcome, Help, or the menu bar.")
            ])
    ]
}

enum QuickTourTarget: String, CaseIterable {
    case overview, start, timer, breaks, progress, sessions, profile
}

@MainActor
final class QuickTourController: ObservableObject {
    static let shared = QuickTourController()
    @Published private(set) var isPresented = false
    @Published private(set) var index = 0
    // Each entry creates a fresh guided visit, without saving a preference.
    @Published private(set) var visit = UUID()
    var step: QuickTourStep { QuickTourStep.all[index] }
    var isFirst: Bool { index == 0 }
    var isLast: Bool { index == QuickTourStep.all.count - 1 }
    var position: String { "Step \(index + 1) of \(QuickTourStep.all.count)" }

    func restart() { index = 0; visit = UUID(); isPresented = true }
    func finish() { isPresented = false; index = 0 }
    func next() { if isPresented && !isLast { index += 1 } }
    func back() { if isPresented && !isFirst { index -= 1 } }
}
