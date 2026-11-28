import Foundation

@main @MainActor struct AIPlanningTests {
    static func main() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("ai-plan-tests-\(UUID())")
        defer { try? FileManager.default.removeItem(at: root) }
        let file = root.appendingPathComponent("projects.json")
        let store = ProjectStore(file: file)
        let tasks = [ProjectTask(title: "Sketch homepage", predictedFocusSessions: 0.5),
                     ProjectTask(title: "Build contact form", predictedFocusSessions: 2.5)]
        let id = try store.savePlan(projectID: nil, name: "  Website redesign  ", color: "#168b80", tasks: tasks)
        let project = store.projects.first { $0.id == id }!
        precondition(project.name == "Website redesign" && project.tasks.map(\.estimate) == [0.5, 2.5])
        precondition(project.tasks.allSatisfy { $0.createdAt != nil && $0.completedAt == nil })
        precondition(ProjectStore(file: file).projects == store.projects)
        let count = store.projects.count
        // Existing-project mode appends tasks without renaming, recoloring, or creating a project.
        try store.savePlan(projectID: id, name: "Ignored", color: "ignored", tasks: tasks)
        let updated = store.projects.first { $0.id == id }!
        precondition(store.projects.count == count && updated.name == project.name && updated.color == project.color)
        precondition(updated.tasks.count == 4 && Set(updated.tasks.map(\.id)).count == 4)
        precondition(updated.tasks.prefix(2).map(\.id) == project.tasks.map(\.id))
        // Save to Random Tasks preserves its protected identity.
        try store.savePlan(projectID: store.projects[0].id, name: "Ignored", color: "ignored", tasks: tasks)
        precondition(store.projects[0].name == "Random Tasks" && store.projects[0].isRandomTasks)
        let before = store.projects
        let bytes = try Data(contentsOf: file)
        func rejects(_ action: () throws -> Void) {
            do { try action(); preconditionFailure("Invalid plan saved") } catch { }
            precondition(store.projects == before)
            precondition((try? Data(contentsOf: file)) == bytes, "Failure must not persist any part of the plan")
        }
        rejects { try store.savePlan(projectID: nil, name: "Partial project", color: "#168B80", tasks: tasks + [ProjectTask(title: "")]) }
        rejects { try store.savePlan(projectID: id, name: "Ignored", color: "ignored", tasks: tasks + [ProjectTask(title: "Invalid", predictedFocusSessions: 1.2)]) }
        rejects { try store.savePlan(projectID: UUID(), name: "Deleted project", color: "#168B80", tasks: tasks) }
        rejects { try store.savePlan(projectID: nil, name: "", color: "#168B80", tasks: tasks) }
        rejects { try store.savePlan(projectID: nil, name: String(repeating: "x", count: 41), color: "#168B80", tasks: tasks) }
        rejects { try store.savePlan(projectID: nil, name: "Plan", color: "bad", tasks: tasks) }
        rejects { try store.savePlan(projectID: nil, name: "Plan", color: "#168B80", tasks: []) }
        rejects { try store.savePlan(projectID: nil, name: "Plan", color: "#168B80", tasks: Array(repeating: tasks[0], count: 31)) }
        // A real write failure leaves memory untouched; fixing the destination permits one complete retry.
        let failureFile = root.appendingPathComponent("failure/projects.json")
        let failureStore = ProjectStore(file: failureFile)
        let failureBefore = failureStore.projects
        try FileManager.default.removeItem(at: failureFile)
        try FileManager.default.createDirectory(at: failureFile, withIntermediateDirectories: false)
        do {
            try failureStore.savePlan(projectID: nil, name: "Retry plan", color: "#168B80", tasks: tasks)
            preconditionFailure("Expected a write failure")
        } catch { precondition(failureStore.projects == failureBefore) }
        try FileManager.default.removeItem(at: failureFile)
        try failureStore.savePlan(projectID: nil, name: "Retry plan", color: "#168B80", tasks: tasks)
        precondition(failureStore.projects.count == failureBefore.count + 1)
        precondition(failureStore.projects.last!.tasks.count == 2)
        precondition(ProjectStore(file: failureFile).projects == failureStore.projects)
        print("AI planning atomic saves, estimates, validation, and retry tests passed")
    }
}
