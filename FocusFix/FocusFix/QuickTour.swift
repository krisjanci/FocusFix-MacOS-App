import Foundation
import Combine
import CoreGraphics

// Practice data only. This model has no recording, storage, credentials, or service dependencies.
enum QuickTourPhase: String, CaseIterable {
    case start, plan, duration, confirmStart, work, takeBreak, startBreak, returned
    case progress, save, sessions, savedSession, profile, editName, name

    var index: Int {
        switch self {
        case .start: return 0
        case .plan, .duration, .confirmStart: return 1
        case .work: return 2
        case .takeBreak, .startBreak, .returned: return 3
        case .progress: return 4
        case .save, .sessions, .savedSession: return 5
        case .profile, .editName, .name: return 6
        }
    }
    var caption: String {
        switch self {
        case .start: return "Click Start to begin."
        case .plan: return "Want a goal? Click Plan session."
        case .duration: return "Pick a time."
        case .confirmStart: return "Ready? Click Start."
        case .work: return "Your work time grows here."
        case .takeBreak: return "Time for a little break."
        case .startBreak: return "Click Start break."
        case .returned: return "Back? Click I’m back."
        case .progress: return "Aim for one hour each day."
        case .save: return "Click Stop to save."
        case .sessions: return "Find your work in Sessions."
        case .savedSession: return "Your work is saved here."
        case .profile: return "Make it yours."
        case .editName: return "Click your name to change it."
        case .name: return "All set!"
        }
    }
    var offersNext: Bool { self == .work || self == .progress || self == .savedSession }
    var offersDone: Bool { self == .name }
}

enum QuickTourAction: Equatable {
    case start, plan, minutes(Int), confirmStart, takeBreak, startBreak, returned
    case save, sessions, profile, editName, next, done
}

@MainActor
final class QuickTourController: ObservableObject {
    static let shared = QuickTourController()
    @Published private(set) var isPresented = false
    @Published private(set) var phase: QuickTourPhase = .start
    @Published private(set) var visit = UUID()
    @Published private(set) var minutes = 60
    @Published private(set) var elapsed = 0
    @Published private(set) var dailyMinutes = 32
    @Published private(set) var breaks = 0
    @Published private(set) var saved = false
    @Published private(set) var demoName = "Alex"

    var index: Int { phase.index }
    var isFirst: Bool { index == 0 }
    var position: String { "\(index + 1)/7" }

    func restart() { reset(to: .start); isPresented = true }
    func finish() { isPresented = false; reset(to: .start) }
    func back() {
        guard isPresented, !isFirst else { return }
        let starts: [QuickTourPhase] = [.start, .plan, .work, .takeBreak, .progress, .save, .profile]
        reset(to: starts[index - 1])
    }

    // A callback belongs to exactly one rendered phase of one visit.
    func perform(_ action: QuickTourAction, phase expected: QuickTourPhase, visit token: UUID) {
        guard isPresented, phase == expected, visit == token else { return }
        switch (phase, action) {
        case (.start, .start): phase = .plan
        case (.plan, .plan): phase = .duration
        case (.duration, .minutes(let value)) where [30, 60, 90].contains(value):
            minutes = value; phase = .confirmStart
        case (.confirmStart, .confirmStart): elapsed = 0; phase = .work
        case (.work, .next): phase = .takeBreak
        case (.takeBreak, .takeBreak): phase = .startBreak
        case (.startBreak, .startBreak): phase = .returned
        case (.returned, .returned): breaks = 1; phase = .progress
        case (.progress, .next): phase = .save
        case (.save, .save): saved = true; phase = .sessions
        case (.sessions, .sessions): phase = .savedSession
        case (.savedSession, .next): phase = .profile
        case (.profile, .profile): phase = .editName
        case (.editName, .editName): phase = .name
        case (.name, .done): finish()
        default: break
        }
    }

    func illustrate(phase expected: QuickTourPhase, visit token: UUID, reducedMotion: Bool = false) {
        guard isPresented, phase == expected, visit == token else { return }
        if phase == .work { elapsed = reducedMotion ? 5 : min(5, elapsed + 1) }
        if phase == .progress { dailyMinutes = 60 }
    }

    func editName(_ value: String) {
        guard isPresented, phase == .name else { return }
        demoName = String(value.prefix(40))
    }

    private func reset(to value: QuickTourPhase) {
        visit = UUID(); phase = value; minutes = 60; demoName = "Alex"
        elapsed = value.index > 2 ? 5 : 0
        breaks = value.index > 3 ? 1 : 0
        dailyMinutes = value.index > 4 ? 60 : 32
        saved = value.index == 6
    }
}

// Pure placement and hit-area calculations, shared with synthetic tests.
struct QuickTourLayout {
    static func spotlight(_ target: CGRect, in size: CGSize) -> CGRect {
        target.insetBy(dx: -6, dy: -6).intersection(
            CGRect(origin: .zero, size: size).insetBy(dx: 8, dy: 8))
    }

    static func caption(target: CGRect, in size: CGSize, hasButton: Bool) -> CGRect {
        let available = CGRect(x: 12, y: 56, width: max(0, size.width - 24), height: max(0, size.height - 68))
        let width = min(248, available.width)
        let height: CGFloat = hasButton ? 112 : 76
        let x = min(max(available.minX, target.midX - width / 2), available.maxX - width)
        let candidates = [
            CGRect(x: x, y: target.maxY + 12, width: width, height: height),
            CGRect(x: x, y: target.minY - height - 12, width: width, height: height)
        ]
        if let result = candidates.first(where: { available.contains($0) }) { return result }
        // Compact targets always leave room on one side in the supported demo layouts.
        let above = max(0, target.minY - 12 - available.minY)
        let below = max(0, available.maxY - target.maxY - 12)
        if above > below {
            return CGRect(x: x, y: available.minY, width: width, height: min(height, above))
        }
        return CGRect(x: x, y: target.maxY + 12, width: width, height: min(height, below))
    }
}
