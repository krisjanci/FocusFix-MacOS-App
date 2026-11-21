import Foundation
import Combine

// Snapshot names keep historical sessions independent of later catalog edits.
nonisolated struct SessionCondition: Codable, Hashable, Identifiable {
    let categoryID: UUID
    let labelID: UUID
    let category: String
    let label: String
    var id: UUID { categoryID }
}

nonisolated struct ConditionLabel: Codable, Hashable, Identifiable {
    var id = UUID()
    var name: String
}

nonisolated struct ConditionCategory: Codable, Hashable, Identifiable {
    var id = UUID()
    var name: String
    var labels: [ConditionLabel] = []
}

nonisolated enum SessionConditions {
    static func validated(_ values: [SessionCondition]) throws -> [SessionCondition] {
        guard values.count <= 20, Set(values.map(\.categoryID)).count == values.count else {
            throw SessionTags.TagError("Choose one label per category, up to 20 categories.")
        }
        return try values.map {
            SessionCondition(categoryID: $0.categoryID, labelID: $0.labelID,
                category: try SessionTags.name($0.category), label: try SessionTags.name($0.label))
        }
    }

    static var defaults: [ConditionCategory] {
        [("Location", ["Home", "Office", "Library", "Café"]),
         ("Music", ["No music", "Instrumental", "Music with lyrics"]),
         ("Work setting", ["Individual", "Group"])].map { name, labels in
            ConditionCategory(name: name, labels: labels.map { ConditionLabel(name: $0) })
        }
    }
}

@MainActor
final class SessionConditionLibrary: ObservableObject {
    static let shared = SessionConditionLibrary()
    @Published private(set) var categories: [ConditionCategory] = []
    @Published private(set) var notice: String?
    @Published private(set) var loaded = false
    private var file: URL?

    init(file: URL? = nil) {
        do {
            self.file = try file ?? FileManager.default.url(for: .applicationSupportDirectory,
                in: .userDomainMask, appropriateFor: nil, create: true)
                .appendingPathComponent("FocusFix/session-conditions.json")
            reload()
        } catch { notice = error.localizedDescription }
    }

    func reload() {
        do {
            guard let file else { throw CocoaError(.fileReadUnknown) }
            if FileManager.default.fileExists(atPath: file.path) {
                categories = try checked(JSONDecoder().decode([ConditionCategory].self, from: Data(contentsOf: file)))
            } else {
                // Persist starter IDs immediately so snapshots resolve after relaunch.
                let defaults = SessionConditions.defaults
                try write(defaults, to: file)
                categories = defaults
            }
            loaded = true; notice = nil
        } catch {
            loaded = false
            notice = "Your condition list could not be opened. Its file has been kept. \(error.localizedDescription)"
        }
    }

    func saveCategory(id: UUID?, name: String) throws {
        var updated = categories
        if let id, let index = updated.firstIndex(where: { $0.id == id }) {
            updated[index].name = try SessionTags.name(name)
        } else { updated.append(ConditionCategory(name: try SessionTags.name(name))) }
        try save(updated)
    }

    func saveLabel(categoryID: UUID, id: UUID?, name: String) throws {
        var updated = categories
        guard let index = updated.firstIndex(where: { $0.id == categoryID }) else {
            throw SessionTags.TagError("This category is no longer in the list.")
        }
        if let id, let labelIndex = updated[index].labels.firstIndex(where: { $0.id == id }) {
            updated[index].labels[labelIndex].name = try SessionTags.name(name)
        } else { updated[index].labels.append(ConditionLabel(name: try SessionTags.name(name))) }
        try save(updated)
    }

    func removeCategory(_ id: UUID) throws { try save(categories.filter { $0.id != id }) }
    func removeLabel(_ id: UUID, categoryID: UUID) throws {
        var updated = categories
        guard let index = updated.firstIndex(where: { $0.id == categoryID }) else { return }
        updated[index].labels.removeAll { $0.id == id }
        try save(updated)
    }

    private func checked(_ values: [ConditionCategory]) throws -> [ConditionCategory] {
        guard values.count <= 100, Set(values.map(\.id)).count == values.count else {
            throw SessionTags.TagError("Use up to 100 unique categories.")
        }
        _ = try SessionTags.validated(values.map(\.name), limit: 100)
        guard Set(values.map { SessionTags.key($0.name) }).count == values.count else {
            throw SessionTags.TagError("A category with that name already exists.")
        }
        for category in values {
            let names = try SessionTags.validated(category.labels.map(\.name), limit: 100)
            guard names.count == category.labels.count,
                  Set(category.labels.map(\.id)).count == category.labels.count else {
                throw SessionTags.TagError("A label with that name already exists in this category.")
            }
        }
        return values
    }

    private func write(_ values: [ConditionCategory], to file: URL) throws {
        try FileManager.default.createDirectory(at: file.deletingLastPathComponent(), withIntermediateDirectories: true,
                                               attributes: [.posixPermissions: 0o700])
        try JSONEncoder().encode(values).write(to: file, options: .atomic)
    }

    private func save(_ values: [ConditionCategory]) throws {
        guard loaded, let file else { throw SessionTags.TagError("Reload your condition list before editing it.") }
        let valid = try checked(values)
        try write(valid, to: file)
        categories = valid
    }
}
