import Foundation
import Combine

nonisolated struct ProjectTask: Codable, Identifiable, Equatable {
    var id = UUID()
    var title: String
    var completedAt: Date?
}

nonisolated struct WorkProject: Codable, Identifiable, Equatable {
    var id = UUID()
    var name: String
    var color: String
    // Canonical order includes completed tasks, preserving their restoration position.
    var tasks: [ProjectTask] = []
}

@MainActor final class ProjectStore: ObservableObject {
    static let shared = ProjectStore()
    @Published private(set) var projects: [WorkProject] = []
    @Published private(set) var notice: String?
    private let file: URL
    private var loaded = false

    init(file: URL? = nil) {
        self.file = file ?? URL.applicationSupportDirectory.appendingPathComponent("FocusFix/projects.json")
        reload()
    }

    func reload() {
        do {
            let values = FileManager.default.fileExists(atPath: file.path)
                ? try JSONDecoder().decode([WorkProject].self, from: Data(contentsOf: file)) : []
            guard Set(values.map(\.id)).count == values.count else { throw CocoaError(.fileReadCorruptFile) }
            for project in values {
                _ = try Self.title(project.name, limit: 40)
                _ = try SessionTags.color(project.color)
                guard Set(project.tasks.map(\.id)).count == project.tasks.count else { throw CocoaError(.fileReadCorruptFile) }
                for task in project.tasks { _ = try Self.title(task.title, limit: 200) }
            }
            projects = values; loaded = true; notice = nil
        } catch { loaded = false; notice = "Projects could not be opened. Your saved file was kept. \(error.localizedDescription)" }
    }

    static func title(_ value: String, limit: Int) throws -> String {
        let value = value.trimmingCharacters(in: .whitespacesAndNewlines).precomposedStringWithCanonicalMapping
        guard !value.isEmpty, value.count <= limit, value.rangeOfCharacter(from: .controlCharacters) == nil else {
            throw SessionTags.TagError("Use 1–\(limit) characters on one line.")
        }
        return value
    }

    private func save(_ values: [WorkProject]) throws {
        guard loaded else { throw SessionTags.TagError("Reload your projects before editing them.") }
        try FileManager.default.createDirectory(at: file.deletingLastPathComponent(), withIntermediateDirectories: true,
                                               attributes: [.posixPermissions: 0o700])
        try JSONEncoder().encode(values).write(to: file, options: .atomic)
        projects = values; notice = nil
    }

    @discardableResult func addProject(_ name: String, color: String) throws -> UUID {
        let project = WorkProject(name: try Self.title(name, limit: 40), color: try SessionTags.color(color))
        try save(projects + [project]); return project.id
    }

    func editProject(_ id: UUID, name: String, color: String) throws {
        try edit(id) { $0.name = try Self.title(name, limit: 40); $0.color = try SessionTags.color(color) }
    }
    func deleteProject(_ id: UUID) throws { try save(projects.filter { $0.id != id }) }
    func addTask(_ title: String, project: UUID) throws {
        try edit(project) { $0.tasks.append(ProjectTask(title: try Self.title(title, limit: 200))) }
    }
    func renameTask(_ id: UUID, project: UUID, title: String) throws {
        try editTask(id, project: project) { $0.title = try Self.title(title, limit: 200) }
    }
    func completeTask(_ id: UUID, project: UUID, at date: Date? = Date()) throws {
        try editTask(id, project: project) { $0.completedAt = date }
    }
    func deleteTask(_ id: UUID, project: UUID) throws {
        try edit(project) { $0.tasks.removeAll { $0.id == id } }
    }
    func moveTask(_ id: UUID, before target: UUID, project: UUID) throws {
        guard id != target else { return }
        try edit(project) { value in
            guard let old = value.tasks.firstIndex(where: { $0.id == id }),
                  value.tasks.contains(where: { $0.id == target }) else { return }
            let task = value.tasks.remove(at: old)
            let index = value.tasks.firstIndex { $0.id == target }!
            value.tasks.insert(task, at: index)
        }
    }
    private func edit(_ id: UUID, change: (inout WorkProject) throws -> Void) throws {
        var values = projects
        guard let index = values.firstIndex(where: { $0.id == id }) else { throw SessionTags.TagError("This project no longer exists.") }
        try change(&values[index]); try save(values)
    }
    private func editTask(_ id: UUID, project: UUID, change: (inout ProjectTask) throws -> Void) throws {
        try edit(project) { value in
            guard let index = value.tasks.firstIndex(where: { $0.id == id }) else { throw SessionTags.TagError("This task no longer exists.") }
            try change(&value.tasks[index])
        }
    }
}
