import Foundation

nonisolated enum ChecklistDragItem: Equatable {
    case project(UUID)
    case task(project: UUID, id: UUID)

    var token: String {
        switch self {
        case .project(let id): return "project:\(id.uuidString)"
        case .task(let project, let id): return "task:\(project.uuidString):\(id.uuidString)"
        }
    }
    func canMove(to target: Self) -> Bool {
        guard self != target else { return false }
        switch (self, target) {
        case (.project, .project): return true
        case (.task(let sourceProject, _), .task(let targetProject, _)): return sourceProject == targetProject
        default: return false
        }
    }
}

nonisolated struct ChecklistInsertion: Equatable {
    let target: ChecklistDragItem
    let after: Bool

    init?(source: ChecklistDragItem?, target: ChecklistDragItem, y: Double, rowHeight: Double) {
        guard let source, source.canMove(to: target), y.isFinite, rowHeight.isFinite, rowHeight > 0 else { return nil }
        self.target = target
        after = y >= rowHeight / 2
    }
}
