import Foundation
import Combine
import CoreGraphics

// Practice data only. This model has no recording, storage, credentials, or service dependencies.
enum QuickTourPhase: String, CaseIterable {
    case start, plan, duration, confirmStart, work, takeBreak, startBreak, returned
    case progress, save, sessions, savedSession, profile, editName, name
    case groups, rankings, freezes

    var index: Int {
        switch self {
        case .start: return 0
        case .plan, .duration, .confirmStart: return 1
        case .work: return 2
        case .takeBreak, .startBreak, .returned: return 3
        case .progress: return 4
        case .save, .sessions, .savedSession: return 5
        case .profile, .editName, .name: return 6
        case .groups: return 7
        case .rankings: return 8
        case .freezes: return 9
        }
    }
    var caption: String {
        switch self {
        case .start: return "Click Start session to begin."
        case .plan: return "Click Plan session to choose a goal."
        case .duration: return "Choose 30, 60, or 90 minutes."
        case .confirmStart: return "Click Start session when ready."
        case .work: return "Your work time grows here."
        case .takeBreak: return "Click Take a break to recharge."
        case .startBreak: return "Click Start break."
        case .returned: return "Back? Click I’m back."
        case .progress: return "Aim for one hour each day."
        case .save: return "Click Stop & save to finish."
        case .sessions: return "Find your work in Sessions."
        case .savedSession: return "Your work is saved here."
        case .profile: return "Click Profile to make it yours."
        case .editName: return "Click your name to change it."
        case .name: return "Try a name, then click Next."
        case .groups: return "Create or join a private group."
        case .rankings: return "One qualifying day earns one point."
        case .freezes: return "Three monthly freezes protect your weekday streak."
        }
    }
    var offersNext: Bool { self == .work || self == .progress || self == .savedSession || self == .name || self == .rankings }
    var offersDone: Bool { self == .freezes }
}

enum QuickTourAction: Equatable {
    case start, plan, minutes(Int), confirmStart, takeBreak, startBreak, returned
    case save, sessions, profile, editName, createGroup, joinGroup, next, done
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
    var position: String { "\(index + 1)/10" }

    func restart() { reset(to: .start); isPresented = true }
    func finish() { isPresented = false; reset(to: .start) }
    func back() {
        guard isPresented, !isFirst else { return }
        let starts: [QuickTourPhase] = [.start, .plan, .work, .takeBreak, .progress, .save, .profile, .groups, .rankings, .freezes]
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
        case (.name, .next): phase = .groups
        case (.groups, .createGroup), (.groups, .joinGroup): phase = .rankings
        case (.rankings, .next): phase = .freezes
        case (.freezes, .done): finish()
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

    // A missing placement requests a separate instruction panel. Never shorten text
    // or squeeze a caption into the remaining gap.
    static func caption(target: CGRect, in size: CGSize, measured: CGSize) -> CGRect? {
        let available = CGRect(origin: .zero, size: size).insetBy(dx: 12, dy: 12)
        guard !target.isNull, measured.width > 0, measured.height > 0,
              measured.width <= available.width, measured.height <= available.height else { return nil }
        let x = min(max(available.minX, target.midX - measured.width / 2), available.maxX - measured.width)
        let y = min(max(available.minY, target.midY - measured.height / 2), available.maxY - measured.height)
        let candidates = [
            CGRect(origin: CGPoint(x: x, y: target.maxY + 12), size: measured),
            CGRect(origin: CGPoint(x: x, y: target.minY - measured.height - 12), size: measured),
            CGRect(origin: CGPoint(x: target.maxX + 12, y: y), size: measured),
            CGRect(origin: CGPoint(x: target.minX - measured.width - 12, y: y), size: measured)
        ]
        return candidates.first { available.contains($0) && !$0.intersects(target) }
    }
}
