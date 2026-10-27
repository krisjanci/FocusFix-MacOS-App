import Foundation
import CoreGraphics

@main @MainActor
struct QuickTourTests {
    static func main() {
        let tour = QuickTourController()
        precondition(!tour.isPresented && tour.phase == .start)
        func act(_ action: QuickTourAction) {
            tour.perform(action, phase: tour.phase, visit: tour.visit)
        }
        act(.start)
        precondition(tour.phase == .start && !tour.isPresented)
        tour.restart()
        for action in [QuickTourAction.save, .done, .minutes(60), .next, .startBreak] { act(action) }
        precondition(tour.phase == .start)
        let originalVisit = tour.visit
        act(.start)
        tour.perform(.start, phase: .start, visit: originalVisit) // Duplicate callback.
        precondition(tour.phase == .plan)
        act(.plan)
        act(.minutes(0)); act(.minutes(480)); act(.minutes(61))
        precondition(tour.phase == .duration)
        act(.minutes(30))
        precondition(tour.phase == .confirmStart && tour.minutes == 30)
        act(.confirmStart)
        precondition(tour.phase == .work && tour.index == 2)
        for _ in 0..<10 { tour.illustrate(phase: .work, visit: tour.visit) }
        precondition(tour.elapsed == 5)
        tour.illustrate(phase: .work, visit: tour.visit, reducedMotion: true)
        precondition(tour.elapsed == 5)
        act(.next); act(.takeBreak); act(.startBreak)
        precondition(tour.phase == .returned && tour.breaks == 0)
        act(.returned)
        precondition(tour.phase == .progress && tour.breaks == 1 && tour.dailyMinutes == 32)
        tour.illustrate(phase: .progress, visit: tour.visit, reducedMotion: true)
        precondition(tour.dailyMinutes == 60)
        act(.next); act(.save)
        precondition(tour.saved && tour.phase == .sessions)
        act(.sessions)
        precondition(tour.phase == .savedSession)
        act(.next); act(.profile); act(.editName)
        precondition(tour.phase == .name && tour.index == 6)
        tour.editName("Practice only")
        precondition(tour.demoName == "Practice only")
        let lateVisit = tour.visit
        tour.back()
        precondition(tour.phase == .save && !tour.saved && tour.demoName == "Alex")
        tour.perform(.done, phase: .name, visit: lateVisit)
        precondition(tour.isPresented && tour.phase == .save)
        let closedVisit = tour.visit
        tour.finish()
        tour.illustrate(phase: .progress, visit: closedVisit)
        precondition(!tour.isPresented && tour.index == 0 && tour.dailyMinutes == 32)
        tour.restart()
        tour.perform(.start, phase: .start, visit: originalVisit)
        precondition(tour.phase == .start && tour.visit != originalVisit)
        tour.back()
        precondition(tour.phase == .start)

        // Complete every phase without a clock, preferences, files, permissions or services.
        let actions: [QuickTourAction] = [.start, .plan, .minutes(90), .confirmStart, .next,
            .takeBreak, .startBreak, .returned, .next, .save, .sessions, .next, .profile, .editName, .next, .createGroup, .next, .done]
        for action in actions { act(action) }
        precondition(!tour.isPresented && tour.demoName == "Alex")
        for phase in QuickTourPhase.allCases {
            precondition(phase.caption.split(separator: " ").count <= 8)
            precondition((0..<10).contains(phase.index))
        }
        let joining = QuickTourController()
        joining.restart()
        for action in actions.prefix(actions.count - 3) {
            joining.perform(action, phase: joining.phase, visit: joining.visit)
        }
        precondition(joining.phase == .groups)
        joining.perform(.joinGroup, phase: joining.phase, visit: joining.visit)
        precondition(joining.phase == .rankings)
        let other = QuickTourController()
        other.restart()
        other.perform(.start, phase: .start, visit: other.visit)
        precondition(other.phase == .plan && !tour.isPresented)

        let starts: [QuickTourPhase] = [.start, .plan, .work, .takeBreak, .progress, .save, .profile, .groups, .rankings, .freezes]
        for stop in 1..<10 {
            let replay = QuickTourController()
            replay.restart()
            for action in actions {
                if replay.index == stop { break }
                replay.perform(action, phase: replay.phase, visit: replay.visit)
            }
            let oldVisit = replay.visit
            replay.back()
            precondition(replay.phase == starts[stop - 1] && replay.visit != oldVisit)
            precondition(replay.minutes == 60 && replay.demoName == "Alex")
        }

        // Measured captions are either wholly visible and clear of the target,
        // or explicitly request docking. No truncated-height fallback is allowed.
        for size in [CGSize(width: 560, height: 650), CGSize(width: 490, height: 650),
                     CGSize(width: 490, height: 550), CGSize(width: 430, height: 600),
                     CGSize(width: 320, height: 260)] {
            let bounds = CGRect(origin: .zero, size: size)
            for target in [CGRect(x: 8, y: 8, width: 60, height: 40),
                           CGRect(x: 24, y: 120, width: size.width - 48, height: 140),
                           CGRect(x: 24, y: size.height - 64, width: 150, height: 40),
                           CGRect(x: size.width - 68, y: 80, width: 60, height: 40),
                           bounds.insetBy(dx: 16, dy: 16)] {
                let hole = QuickTourLayout.spotlight(target, in: size)
                precondition(bounds.contains(hole))
                for height: CGFloat in [44, 76, 112, 156] {
                    let measured = CGSize(width: 248, height: height)
                    if let caption = QuickTourLayout.caption(target: hole, in: size, measured: measured) {
                        precondition(bounds.insetBy(dx: 12, dy: 12).contains(caption))
                        precondition(!caption.intersects(hole) && caption.size == measured)
                    }
                }
            }
            precondition(QuickTourLayout.caption(target: bounds.insetBy(dx: 16, dy: 16),
                in: size, measured: CGSize(width: 248, height: 112)) == nil)
        }
        // Side placement is used when neither vertical gap is tall enough.
        let side = QuickTourLayout.caption(target: CGRect(x: 12, y: 12, width: 60, height: 220),
            in: CGSize(width: 430, height: 250), measured: CGSize(width: 248, height: 112))
        precondition(side != nil && side!.minX > 72)
        precondition(QuickTourLayout.caption(target: .null, in: CGSize(width: 430, height: 600),
            measured: CGSize(width: 248, height: 76)) == nil)
        precondition(QuickTourLayout.caption(target: .zero, in: CGSize(width: 100, height: 100),
            measured: CGSize(width: 248, height: 112)) == nil)
        precondition(QuickTourPhase.start.caption.contains("Start session"))
        precondition(QuickTourPhase.confirmStart.caption.contains("Start session"))
        precondition(QuickTourPhase.save.caption.contains("Stop & save"))
        print("Practice tour actions, stale callbacks, replay, isolation, short copy and measured placement passed")
    }
}
