import Foundation
import UniformTypeIdentifiers

nonisolated enum ChecklistDragItem: Equatable {
    case project(UUID)
    case task(project: UUID, id: UUID, completed: Bool)

    var token: String {
        switch self {
        case .project(let id): return "project:\(id.uuidString)"
        case .task(let project, let id, let completed): return "task:\(project.uuidString):\(id.uuidString):\(completed)"
        }
    }
    func canMove(to target: Self) -> Bool {
        guard self != target else { return false }
        switch (self, target) {
        case (.project, .project): return true
        case (.task(let sourceProject, _, let sourceComplete), .task(let targetProject, _, let targetComplete)):
            return sourceProject == targetProject && sourceComplete == targetComplete
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

// Share the exact native payload path between drag sources, drop validation, and tests.
nonisolated enum ChecklistDragPayload {
    static let type = UTType.utf8PlainText
    static func provider(for item: ChecklistDragItem) -> NSItemProvider {
        let provider = NSItemProvider()
        provider.registerDataRepresentation(forTypeIdentifier: type.identifier, visibility: .all) { completion in
            completion(Data(item.token.utf8), nil); return nil
        }
        return provider
    }
    static func matches(_ data: Data?, source: ChecklistDragItem) -> Bool { data == Data(source.token.utf8) }
}
