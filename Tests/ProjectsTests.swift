import Foundation

@main @MainActor struct ProjectsTests {
    static func fails(_ action: () throws -> Void) {
        do { try action(); preconditionFailure("Expected failure") } catch { }
    }
    static func main() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("projects-tests-\(UUID())")
        defer { try? FileManager.default.removeItem(at: root) }
        let file = root.appendingPathComponent("projects.json")
        let store = ProjectStore(file: file)
        precondition(store.projects.count == 1)
        let random = store.projects[0]
        precondition(random.name == "Random Tasks" && random.isRandomTasks)
        fails { try store.deleteProject(random.id) }
        fails { try store.editProject(random.id, name: "Renamed", color: "#168B80") }
        try store.editProject(random.id, name: "Random Tasks", color: "#7963CF")
        precondition(ProjectStore(file: file).projects == store.projects)

        let id = try store.addProject("  FocusFix  ", color: "#168b80")
        func project() -> WorkProject { store.projects.first { $0.id == id }! }
        try store.addTask("First", project: id)
        try store.addTask("Second", project: id)
        try store.addTask("Third", project: id)
        let original = project().tasks.map(\.id)
        try store.completeTask(original[1], project: id, at: Date(timeIntervalSince1970: 20))
        precondition(project().tasks.map(\.id) == original)
        precondition(project().tasks[1].completedAt != nil)
        try store.completeTask(original[1], project: id, at: nil)
        try store.completeTask(original[1], project: id)
        try store.completeTask(original[1], project: id, at: nil)
        precondition(project().tasks.map(\.id) == original)
        try store.moveTask(original[2], before: original[0], project: id)
        precondition(project().tasks.map(\.id) == [original[2], original[0], original[1]])
        try store.moveTask(original[2], after: original[1], project: id)
        precondition(project().tasks.map(\.id) == original)
        try store.renameTask(original[0], project: id, title: "Updated")
        try store.editProject(id, name: "Project", color: "#7963CF")
        precondition(ProjectStore(file: file).projects == store.projects)
        for invalid in ["", "  ", "a\nb", String(repeating: "x", count: 201)] {
            fails { try store.addTask(invalid, project: id) }
        }
        fails { _ = try store.addProject(String(repeating: "x", count: 41), color: "#168B80") }
        fails { try store.editProject(id, name: "Valid", color: "broken") }
        let before = store.projects
        fails { try store.renameTask(UUID(), project: id, title: "Missing") }
        precondition(before == store.projects)

        let second = try store.addProject("Second project", color: "#168B80")
        try store.recordWork(on: id, at: Date(timeIntervalSince1970: 10))
        precondition(store.projects.map(\.id) == [id, random.id, second])
        try store.recordWork(on: second, at: Date(timeIntervalSince1970: 20))
        precondition(store.projects.map(\.id) == [second, id, random.id])
        // Reads, task edits, project edits, and completion do not promote a project.
        _ = project()
        try store.renameTask(original[0], project: id, title: "Still second")
        try store.editProject(id, name: "Still second", color: "#168B80")
        try store.completeTask(original[0], project: id)
        precondition(store.projects.map(\.id) == [second, id, random.id])
        precondition(project().lastWorkedAt == Date(timeIntervalSince1970: 10))
        try store.moveProject(random.id, relativeTo: second)
        precondition(store.projects.map(\.id) == [random.id, second, id])
        try store.moveProject(random.id, relativeTo: id, after: true)
        precondition(store.projects.map(\.id) == [second, id, random.id])
        precondition(ProjectStore(file: file).projects == store.projects)
        // Manual ordering persists on reload; the next work action promotes its project again.
        try store.moveProject(second, relativeTo: random.id, after: true)
        precondition(ProjectStore(file: file).projects.map(\.id) == [id, random.id, second])
        try store.recordWork(on: second, at: Date(timeIntervalSince1970: 30))
        precondition(store.projects.map(\.id) == [second, id, random.id])
        let completedProject = try store.addProject("Completed order", color: "#168B80")
        for title in ["A", "B", "C"] { try store.addTask(title, project: completedProject) }
        let completedIDs = store.projects.first { $0.id == completedProject }!.tasks.map(\.id)
        try store.completeTask(completedIDs[0], project: completedProject, at: Date(timeIntervalSince1970: 1))
        try store.completeTask(completedIDs[1], project: completedProject, at: Date(timeIntervalSince1970: 2))
        try store.moveTask(completedIDs[1], before: completedIDs[0], project: completedProject)
        precondition(store.projects.first { $0.id == completedProject }!.completedTasks.map(\.id) == [completedIDs[1], completedIDs[0]])
        try store.completeTask(completedIDs[2], project: completedProject, at: Date(timeIntervalSince1970: 3))
        precondition(ProjectStore(file: file).projects.first { $0.id == completedProject }!.completedTasks.map(\.id) == [completedIDs[1], completedIDs[0], completedIDs[2]])
        try store.moveTask(completedIDs[1], after: completedIDs[2], project: completedProject)
        precondition(store.projects.first { $0.id == completedProject }!.completedTasks.map(\.id) == [completedIDs[0], completedIDs[2], completedIDs[1]])
        try store.completeTask(completedIDs[1], project: completedProject, at: nil)
        precondition(store.projects.first { $0.id == completedProject }!.tasks.last!.id == completedIDs[1])
        precondition(store.projects.first { $0.id == completedProject }!.completedTasks.map(\.id) == [completedIDs[0], completedIDs[2]])
        try store.deleteProject(completedProject)
        try store.deleteTask(original[1], project: id)
        precondition(project().tasks.count == 2)
        try store.deleteProject(id)
        try store.deleteProject(second)
        precondition(ProjectStore(file: file).projects.map(\.id) == [random.id])

        // Old array-format catalogs acquire one default without losing task IDs/order.
        let legacyFile = root.appendingPathComponent("legacy.json")
        let legacy = WorkProject(name: "Legacy", color: "#168B80", tasks: [ProjectTask(title: "Keep me")])
        try JSONEncoder().encode([legacy]).write(to: legacyFile)
        let migrated = ProjectStore(file: legacyFile)
        precondition(migrated.projects.count == 2 && migrated.projects.filter(\.isRandomTasks).count == 1)
        precondition(migrated.projects.last == legacy)
        precondition(ProjectStore(file: legacyFile).projects == migrated.projects)
        // An existing Random Tasks folder is adopted without changing historical references.
        var existing = legacy; existing.name = "Random Tasks"
        try JSONEncoder().encode([existing]).write(to: legacyFile)
        let adopted = ProjectStore(file: legacyFile)
        precondition(adopted.projects.count == 1 && adopted.projects[0].isRandomTasks)
        precondition(adopted.projects[0].id == existing.id && adopted.projects[0].tasks == existing.tasks)
        fails { try adopted.deleteProject(existing.id) }

        try Data("broken".utf8).write(to: file)
        let broken = ProjectStore(file: file)
        precondition(broken.notice != nil)
        fails { _ = try broken.addProject("Must not overwrite", color: "#168B80") }
        let kept = try String(contentsOf: file, encoding: .utf8)
        precondition(kept == "broken")
        let blocked = root.appendingPathComponent("blocked")
        let writer = ProjectStore(file: blocked.appendingPathComponent("projects.json"))
        let preserved = writer.projects
        try FileManager.default.removeItem(at: blocked)
        try Data().write(to: blocked)
        fails { _ = try writer.addProject("Failure", color: "#168B80") }
        fails { try writer.recordWork(on: WorkProject.randomTasksID) }
        precondition(writer.projects == preserved)
        print("ProjectsTests passed: protected default, migration, tasks, work recency, manual order, persistence and write failures")
    }
}
