import Foundation
import Combine

// Tags are user-authored session labels, independent of accounts and research consent.
nonisolated enum SessionTags {
    static let defaults = ["Focused work", "Distracted work", "Repetitive work", "Creative work",
                           "Learning", "Planning", "Meetings", "Administrative work"]
    static let maximumPerSession = 20

    static func name(_ value: String) throws -> String {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines).precomposedStringWithCanonicalMapping
        guard !trimmed.isEmpty, trimmed.count <= 40,
              trimmed.rangeOfCharacter(from: .controlCharacters) == nil else {
            throw TagError("Use a tag name of 1–40 characters on one line.")
        }
        return trimmed
    }

    static func key(_ value: String) -> String {
        value.folding(options: [.caseInsensitive], locale: Locale(identifier: "en_US_POSIX"))
    }

    static func validated(_ values: [String], limit: Int = maximumPerSession) throws -> [String] {
        var seen = Set<String>()
        let names = try values.map(name).filter { seen.insert(key($0)).inserted }
        guard names.count <= limit else { throw TagError("Choose up to \(limit) tags.") }
        return names
    }

    struct TagError: LocalizedError {
        let message: String
        init(_ message: String) { self.message = message }
        var errorDescription: String? { message }
    }
}

@MainActor
final class SessionTagLibrary: ObservableObject {
    static let shared = SessionTagLibrary()
    @Published private(set) var names = SessionTags.defaults
    @Published private(set) var notice: String?
    @Published private(set) var loaded = false
    private var file: URL?

    init(file: URL? = nil) {
        do {
            self.file = try file ?? FileManager.default.url(for: .applicationSupportDirectory,
                in: .userDomainMask, appropriateFor: nil, create: true)
                .appendingPathComponent("FocusFix/session-tags.json")
            reload()
        } catch { notice = "Your tag list could not be opened. \(error.localizedDescription)" }
    }

    func reload() {
        do {
            guard let file else { throw CocoaError(.fileReadUnknown) }
            if FileManager.default.fileExists(atPath: file.path) {
                names = try SessionTags.validated(JSONDecoder().decode([String].self,
                    from: Data(contentsOf: file)), limit: 100)
            } else { names = SessionTags.defaults }
            loaded = true
            notice = nil
        } catch {
            loaded = false
            notice = "Your saved tag list could not be opened. Its file has been kept. \(error.localizedDescription)"
        }
    }

    @discardableResult
    func add(_ value: String) throws -> String {
        let name = try SessionTags.name(value)
        if let existing = names.first(where: { SessionTags.key($0) == SessionTags.key(name) }) { return existing }
        try save(names + [name])
        return name
    }

    func rename(_ old: String, to value: String) throws {
        let name = try SessionTags.name(value)
        guard let index = names.firstIndex(of: old) else { throw SessionTags.TagError("This tag is no longer in the list.") }
        guard !names.enumerated().contains(where: { $0.offset != index && SessionTags.key($0.element) == SessionTags.key(name) }) else {
            throw SessionTags.TagError("A tag with that name already exists.")
        }
        var updated = names
        updated[index] = name
        try save(updated)
    }

    func remove(_ name: String) throws { try save(names.filter { $0 != name }) }

    private func save(_ values: [String]) throws {
        guard loaded, let file else { throw SessionTags.TagError("Reload your saved tag list before editing it.") }
        let valid = try SessionTags.validated(values, limit: 100)
        try FileManager.default.createDirectory(at: file.deletingLastPathComponent(), withIntermediateDirectories: true,
                                               attributes: [.posixPermissions: 0o700])
        try JSONEncoder().encode(valid).write(to: file, options: .atomic)
        names = valid
    }
}
