import Foundation
import Combine

nonisolated struct CompletedTaskWork: Codable, Equatable {
    let projectID: UUID
    let projectName: String
    let taskTitle: String
    let finishedAt: Date
    var seconds: Double?
}

nonisolated struct ProjectTask: Codable, Identifiable, Equatable {
    var id = UUID()
    var title: String
    var completedAt: Date?
    var completedWork: CompletedTaskWork?
}

nonisolated struct WorkProject: Codable, Identifiable, Equatable {
    var id = UUID()
    var name: String
    var color: String
    var lastWorkedAt: Date?
    var builtIn: Bool?
    var isRandomTasks: Bool { builtIn == true }
    static let randomTasksID = UUID(uuidString: "72746173-6B73-4000-8000-000000000001")!
    static var randomTasks: WorkProject {
        WorkProject(id: randomTasksID, name: "Random Tasks", color: "#168B80", builtIn: true)
    }
    // Canonical order includes completed tasks, preserving their restoration position.
    var tasks: [ProjectTask] = []
    var completedTaskOrder: [UUID]?

    var completedTasks: [ProjectTask] {
        let completed = tasks.filter { $0.completedAt != nil }.sorted { $0.completedAt! < $1.completedAt! }
        let lookup = Dictionary(completed.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
        var seen = Set<UUID>()
        return ((completedTaskOrder ?? []) + completed.map(\.id)).compactMap { id in
            guard seen.insert(id).inserted else { return nil }
            return lookup[id]
        }
    }
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
            var values = FileManager.default.fileExists(atPath: file.path)
                ? try JSONDecoder().decode([WorkProject].self, from: Data(contentsOf: file)) : []
            guard Set(values.map(\.id)).count == values.count else { throw CocoaError(.fileReadCorruptFile) }
            for project in values {
                _ = try Self.title(project.name, limit: 40)
                _ = try SessionTags.color(project.color)
                guard Set(project.tasks.map(\.id)).count == project.tasks.count else { throw CocoaError(.fileReadCorruptFile) }
                for task in project.tasks {
                    _ = try Self.title(task.title, limit: 200)
                    if let work = task.completedWork {
                        guard work.projectID == project.id, work.finishedAt == task.completedAt,
                              work.seconds.map({ $0.isFinite && $0 >= 0 }) ?? true else { throw CocoaError(.fileReadCorruptFile) }
                        _ = try Self.title(work.projectName, limit: 40)
                        _ = try Self.title(work.taskTitle, limit: 200)
                    }
                }
            }
            guard values.filter(\.isRandomTasks).count <= 1 else { throw CocoaError(.fileReadCorruptFile) }
            var migrated = false
            if let index = values.firstIndex(where: \.isRandomTasks) {
                if values[index].name != "Random Tasks" { values[index].name = "Random Tasks"; migrated = true }
            } else if let index = values.firstIndex(where: { SessionTags.key($0.name) == SessionTags.key("Random Tasks") }) {
                // Adopt a user's existing folder without changing its ID or task references.
                values[index].builtIn = true; values[index].name = "Random Tasks"; migrated = true
            } else {
                values.insert(.randomTasks, at: 0); migrated = true
            }
            if migrated { try write(values) }
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
        try write(values)
        projects = values; notice = nil
    }

    private func write(_ values: [WorkProject]) throws {
        try FileManager.default.createDirectory(at: file.deletingLastPathComponent(), withIntermediateDirectories: true,
                                               attributes: [.posixPermissions: 0o700])
        try JSONEncoder().encode(values).write(to: file, options: .atomic)
    }

    @discardableResult func addProject(_ name: String, color: String) throws -> UUID {
        let project = WorkProject(name: try Self.title(name, limit: 40), color: try SessionTags.color(color))
        try save(projects + [project]); return project.id
    }

    func editProject(_ id: UUID, name: String, color: String) throws {
        try edit(id) {
            let name = try Self.title(name, limit: 40)
            guard !$0.isRandomTasks || name == "Random Tasks" else { throw SessionTags.TagError("Random Tasks keeps its default name.") }
            $0.name = name; $0.color = try SessionTags.color(color)
        }
    }
    func deleteProject(_ id: UUID) throws {
        guard !projects.contains(where: { $0.id == id && $0.isRandomTasks }) else {
            throw SessionTags.TagError("Random Tasks cannot be deleted.")
        }
        try save(projects.filter { $0.id != id })
    }

    // Actual work actions promote a project; merely opening/editing it never changes order.
    func recordWork(on id: UUID, at date: Date = Date()) throws {
        var values = projects
        guard let index = values.firstIndex(where: { $0.id == id }) else { throw SessionTags.TagError("This project no longer exists.") }
        var project = values.remove(at: index)
        project.lastWorkedAt = date
        values.insert(project, at: 0)
        try save(values)
    }

    // A manual move persists until a subsequent work action promotes a project again.
    func moveProject(_ id: UUID, relativeTo target: UUID, after: Bool = false) throws {
        guard id != target else { return }
        var values = projects
        guard let old = values.firstIndex(where: { $0.id == id }), values.contains(where: { $0.id == target }) else { return }
        let project = values.remove(at: old)
        let index = values.firstIndex { $0.id == target }!
        values.insert(project, at: index + (after ? 1 : 0))
        try save(values)
    }
    @discardableResult func addTask(_ title: String, project: UUID) throws -> UUID {
        let id = UUID()
        try edit(project) { $0.tasks.append(ProjectTask(id: id, title: try Self.title(title, limit: 200))) }
        return id
    }
    func renameTask(_ id: UUID, project: UUID, title: String) throws {
        try editTask(id, project: project) { $0.title = try Self.title(title, limit: 200) }
    }
    func completeTask(_ id: UUID, project: UUID, at date: Date? = Date(), work: CompletedTaskWork? = nil) throws {
        if let work {
            guard work.projectID == project, work.finishedAt == date,
                  work.seconds.map({ $0.isFinite && $0 >= 0 }) ?? true else { throw SessionTags.TagError("The saved task time is invalid.") }
        }
        try edit(project) { value in
            guard let index = value.tasks.firstIndex(where: { $0.id == id }) else { throw SessionTags.TagError("This task no longer exists.") }
            let order = value.completedTasks.map(\.id).filter { $0 != id }
            value.tasks[index].completedAt = date
            value.tasks[index].completedWork = date == nil ? nil : work
            value.completedTaskOrder = date == nil ? order : order + [id]
        }
    }
    func saveCompletedWork(_ work: CompletedTaskWork, task id: UUID) throws {
        guard let seconds = work.seconds, seconds.isFinite, seconds >= 0 else {
            throw SessionTags.TagError("The saved task time is invalid.")
        }
        // A background result must not overwrite a task reopened or completed again.
        guard let task = projects.first(where: { $0.id == work.projectID })?.tasks.first(where: { $0.id == id }),
              task.completedAt == work.finishedAt, task.completedWork?.finishedAt == work.finishedAt else { return }
        try editTask(id, project: work.projectID) { $0.completedWork = work }
    }
    func deleteTask(_ id: UUID, project: UUID) throws {
        try edit(project) { $0.tasks.removeAll { $0.id == id }; $0.completedTaskOrder?.removeAll { $0 == id } }
    }
    func moveTask(_ id: UUID, before target: UUID, project: UUID) throws {
        guard id != target else { return }
        try edit(project) { value in
            guard let old = value.tasks.firstIndex(where: { $0.id == id }),
                  value.tasks.contains(where: { $0.id == target }) else { return }
            reorderCompleted(id, relativeTo: target, after: false, in: &value)
            let task = value.tasks.remove(at: old)
            let index = value.tasks.firstIndex { $0.id == target }!
            value.tasks.insert(task, at: index)
        }
    }
    func moveTask(_ id: UUID, after target: UUID, project: UUID) throws {
        guard id != target else { return }
        try edit(project) { value in
            guard let old = value.tasks.firstIndex(where: { $0.id == id }),
                  value.tasks.contains(where: { $0.id == target }) else { return }
            reorderCompleted(id, relativeTo: target, after: true, in: &value)
            let task = value.tasks.remove(at: old)
            let index = value.tasks.firstIndex { $0.id == target }!
            value.tasks.insert(task, at: index + 1)
        }
    }
    private func reorderCompleted(_ id: UUID, relativeTo target: UUID, after: Bool, in value: inout WorkProject) {
        var order = value.completedTasks.map(\.id)
        guard let old = order.firstIndex(of: id), order.contains(target) else { return }
        order.remove(at: old)
        let index = order.firstIndex(of: target)!
        order.insert(id, at: index + (after ? 1 : 0))
        value.completedTaskOrder = order
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
