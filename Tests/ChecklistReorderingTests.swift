import Foundation

@main struct ChecklistReorderingTests {
    static func main() {
        let first = ChecklistDragItem.project(UUID()), second = ChecklistDragItem.project(UUID())
        precondition(first.canMove(to: second) && !first.canMove(to: first))
        for height in [26.0, 44, 68, 120] {
            precondition(ChecklistInsertion(source: first, target: second, y: 0, rowHeight: height)?.after == false)
            precondition(ChecklistInsertion(source: first, target: second, y: height / 2 - 0.01, rowHeight: height)?.after == false)
            precondition(ChecklistInsertion(source: first, target: second, y: height / 2, rowHeight: height)?.after == true)
            precondition(ChecklistInsertion(source: first, target: second, y: height, rowHeight: height)?.after == true)
        }
        let project = UUID(), otherProject = UUID()
        let a = ChecklistDragItem.task(project: project, id: UUID(), completed: false)
        let b = ChecklistDragItem.task(project: project, id: UUID(), completed: false)
        let foreign = ChecklistDragItem.task(project: otherProject, id: UUID(), completed: false)
        let finishedA = ChecklistDragItem.task(project: project, id: UUID(), completed: true)
        let finishedB = ChecklistDragItem.task(project: project, id: UUID(), completed: true)
        precondition(finishedA.canMove(to: finishedB) && !a.canMove(to: finishedB) && !finishedA.canMove(to: a))
        precondition(ChecklistInsertion(source: a, target: finishedB, y: 20, rowHeight: 44) == nil)
        precondition(a.canMove(to: b) && !a.canMove(to: foreign))
        precondition(!a.canMove(to: first) && !first.canMove(to: a))
        for (source, target) in [(a, a), (a, foreign), (a, first), (first, a)] {
            precondition(ChecklistInsertion(source: source, target: target, y: 10, rowHeight: 44) == nil)
        }
        precondition(ChecklistInsertion(source: nil, target: second, y: 10, rowHeight: 44) == nil)
        for height in [0.0, -1, .infinity, .nan] {
            precondition(ChecklistInsertion(source: first, target: second, y: 1, rowHeight: height) == nil)
        }
        precondition(ChecklistInsertion(source: first, target: second, y: .nan, rowHeight: 44) == nil)
        precondition(ChecklistInsertion(source: first, target: second, y: .infinity, rowHeight: 44) == nil)
        precondition(first.token != second.token && a.token != b.token && a.token != foreign.token)
        precondition(first.token.hasPrefix("project:") && a.token.hasPrefix("task:"))
        print("ChecklistReorderingTests passed: measured midpoints, before/after, self/cross-scope rejection and valid payload identity")
    }
}
