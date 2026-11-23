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
        let id = try store.addProject("  FocusFix  ", color: "#168b80")
        try store.addTask("First", project: id)
        try store.addTask("Second", project: id)
        try store.addTask("Third", project: id)
        let original = store.projects[0].tasks.map(\.id)
        try store.completeTask(original[1], project: id, at: Date(timeIntervalSince1970: 20))
        precondition(store.projects[0].tasks.map(\.id) == original)
        precondition(store.projects[0].tasks[1].completedAt != nil)
        // Repeated completion/reopening never loses canonical position.
        try store.completeTask(original[1], project: id, at: nil)
        try store.completeTask(original[1], project: id)
        try store.completeTask(original[1], project: id, at: nil)
        precondition(store.projects[0].tasks.map(\.id) == original)
        try store.moveTask(original[2], before: original[0], project: id)
        precondition(store.projects[0].tasks.map(\.id) == [original[2], original[0], original[1]])
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
        try store.deleteTask(original[1], project: id)
        precondition(store.projects[0].tasks.count == 2)
        try store.deleteProject(id)
        precondition(ProjectStore(file: file).projects.isEmpty)
        try Data("broken".utf8).write(to: file)
        let broken = ProjectStore(file: file)
        precondition(broken.notice != nil)
        fails { _ = try broken.addProject("Must not overwrite", color: "#168B80") }
        let kept = try String(contentsOf: file, encoding: .utf8)
        precondition(kept == "broken")
        // A write failure leaves published state unchanged.
        let blocked = root.appendingPathComponent("blocked")
        let writer = ProjectStore(file: blocked.appendingPathComponent("projects.json"))
        try Data().write(to: blocked)
        fails { _ = try writer.addProject("Failure", color: "#168B80") }
        precondition(writer.projects.isEmpty)
        print("ProjectsTests passed")
    }
}
