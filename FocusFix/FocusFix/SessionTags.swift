import Foundation
import Combine

// Tags are user-authored session labels, independent of accounts and research consent.
nonisolated enum SessionTags {
    static let defaults = ["Focused work", "Creative work", "Repetitive work"]
    static let legacyDefaults = ["Focused work", "Distracted work", "Repetitive work", "Creative work",
                                 "Learning", "Planning", "Meetings", "Administrative work"]
    static let palette = ["#168B80", "#7963CF", "#D48326", "#C64B66", "#367CC5", "#5D9345", "#93654C", "#64748B"]
    static let maximumPerSession = 20

    static func color(_ value: String) throws -> String {
        let hex = value.uppercased()
        guard hex.count == 7, hex.first == "#", hex.dropFirst().allSatisfy({ $0.isHexDigit && $0.isASCII }) else {
            throw TagError("Choose a valid tag color.")
        }
        return hex
    }

    static func defaultColor(for name: String) -> String {
        if let index = defaults.firstIndex(of: name) { return palette[index] }
        let hash = key(name).utf8.reduce(0) { ($0 * 31 + Int($1)) % palette.count }
        return palette[hash]
    }

    static func colors(_ values: [String: String], for names: [String]) throws -> [String: String] {
        var result: [String: String] = [:]
        for name in names { result[name] = try color(values[name] ?? defaultColor(for: name)) }
        return result
    }

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
    @Published private(set) var colors: [String: String] = [:]
    private var file: URL?
    private struct Catalog: Codable {
        let names: [String]
        let colors: [String: String]
    }

    func color(for name: String, saved: [String: String] = [:]) -> String {
        colors[name] ?? saved[name] ?? SessionTags.defaultColor(for: name)
    }

    func resolvedColors(for names: [String], saved: [String: String] = [:]) -> [String: String] {
        names.reduce(into: [:]) { $0[$1] = color(for: $1, saved: saved) }
    }

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
                let data = try Data(contentsOf: file)
                if let legacy = try? JSONDecoder().decode([String].self, from: data) {
                    // Shorten the original starter list without losing appended custom labels.
                    let migrated = legacy.starts(with: SessionTags.legacyDefaults)
                        ? SessionTags.defaults + legacy.dropFirst(SessionTags.legacyDefaults.count) : legacy
                    names = try SessionTags.validated(migrated, limit: 100)
                    colors = try SessionTags.colors([:], for: names)
                } else {
                    let catalog = try JSONDecoder().decode(Catalog.self, from: data)
                    let valid = try SessionTags.validated(catalog.names, limit: 100)
                    let validColors = try SessionTags.colors(catalog.colors, for: valid)
                    names = valid; colors = validColors
                }
            } else {
                names = SessionTags.defaults
                colors = try SessionTags.colors([:], for: names)
            }
            loaded = true
            notice = nil
        } catch {
            loaded = false
            notice = "Your saved tag list could not be opened. Its file has been kept. \(error.localizedDescription)"
        }
    }

    @discardableResult
    func add(_ value: String, color: String? = nil) throws -> String {
        let name = try SessionTags.name(value)
        if let existing = names.first(where: { SessionTags.key($0) == SessionTags.key(name) }) { return existing }
        var updatedColors = colors
        updatedColors[name] = try SessionTags.color(color ?? SessionTags.defaultColor(for: name))
        try save(names + [name], colors: updatedColors)
        return name
    }

    func rename(_ old: String, to value: String, color: String? = nil) throws {
        let name = try SessionTags.name(value)
        guard let index = names.firstIndex(of: old) else { throw SessionTags.TagError("This tag is no longer in the list.") }
        guard !names.enumerated().contains(where: { $0.offset != index && SessionTags.key($0.element) == SessionTags.key(name) }) else {
            throw SessionTags.TagError("A tag with that name already exists.")
        }
        var updated = names
        updated[index] = name
        var updatedColors = colors
        updatedColors.removeValue(forKey: old)
        updatedColors[name] = try SessionTags.color(color ?? self.color(for: old))
        try save(updated, colors: updatedColors)
    }

    func remove(_ name: String) throws { try save(names.filter { $0 != name }, colors: colors) }

    private func save(_ values: [String], colors: [String: String]) throws {
        guard loaded, let file else { throw SessionTags.TagError("Reload your saved tag list before editing it.") }
        let valid = try SessionTags.validated(values, limit: 100)
        let validColors = try SessionTags.colors(colors, for: valid)
        try FileManager.default.createDirectory(at: file.deletingLastPathComponent(), withIntermediateDirectories: true,
                                               attributes: [.posixPermissions: 0o700])
        try JSONEncoder().encode(Catalog(names: valid, colors: validColors)).write(to: file, options: .atomic)
        names = valid
        self.colors = validColors
    }
}
