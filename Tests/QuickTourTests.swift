import Foundation

@main @MainActor
struct QuickTourTests {
    static func main() {
        let tour = QuickTourController()
        precondition(QuickTourStep.all.map(\.id) == ["meet", "start", "work", "break", "progress", "sessions", "personalize"])
        precondition(Set(QuickTourStep.all.map(\.id)).count == 7)
        for step in QuickTourStep.all {
            precondition(!step.title.isEmpty && !step.subtitle.isEmpty && !step.symbol.isEmpty)
            precondition(!step.exampleTitle.isEmpty && !step.exampleDetail.isEmpty)
            precondition(step.tips.count == 3 && step.tips.allSatisfy { !$0.title.isEmpty && !$0.detail.isEmpty })
        }
        precondition(tour.index == 0 && tour.isFirst && !tour.isLast && tour.position == "Step 1 of 7")
        precondition(!tour.isPresented)
        tour.next()
        precondition(tour.index == 0)
        tour.restart()
        precondition(tour.isPresented)
        precondition(Set(QuickTourStep.all.map(\.target)) == Set(QuickTourTarget.allCases))
        tour.back()
        precondition(tour.index == 0)
        for index in 1..<7 {
            tour.next()
            precondition(tour.index == index && tour.step.id == QuickTourStep.all[index].id)
        }
        precondition(tour.isLast && tour.position == "Step 7 of 7")
        tour.next()
        precondition(tour.index == 6)
        tour.back()
        precondition(tour.index == 5 && !tour.isLast)
        let visit = tour.visit
        tour.restart()
        precondition(tour.isFirst && tour.visit != visit)
        let firstVisit = tour.visit
        tour.restart()
        precondition(tour.index == 0 && tour.visit != firstVisit) // Reopening page one also resets scrolling.
        // Independent navigation instances have no global preferences or service side effects.
        let other = QuickTourController()
        other.restart()
        other.next()
        precondition(tour.index == 0 && other.index == 1)
        tour.finish()
        precondition(!tour.isPresented && tour.index == 0)
        tour.next()
        precondition(tour.index == 0)
        tour.restart()
        precondition(tour.isPresented && tour.isFirst)
        print("Guided tour targets, presentation, navigation, replay and isolation passed")
    }
}
