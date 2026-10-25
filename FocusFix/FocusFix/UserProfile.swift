// MARK: - FF: PROFILE
// Personal presentation stays separate from participant IDs and recording metadata.
import Foundation

nonisolated struct UserProfile: Codable, Equatable {
    static let symbols = ["person.fill", "leaf.fill", "sun.max.fill", "moon.stars.fill", "bolt.fill", "book.fill"]
    static let colors = ["teal", "blue", "purple", "orange", "pink"]
    var name: String
    var symbol: String
    var color: String
    var photo: Data?

    init(name: String = "", symbol: String = "person.fill", color: String = "teal", photo: Data? = nil) {
        self.name = name
        self.symbol = symbol
        self.color = color
        self.photo = photo
    }

    func validated() throws -> UserProfile {
        let name = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty, name.count <= 40,
              !name.unicodeScalars.contains(where: { CharacterSet.controlCharacters.contains($0) }),
              Self.symbols.contains(symbol), Self.colors.contains(color),
              photo.map({ !$0.isEmpty && $0.count <= 1_048_576 }) ?? true else {
            throw ProfileError.invalid
        }
        return UserProfile(name: name, symbol: symbol, color: color, photo: photo)
    }
}

nonisolated enum ProfileError: LocalizedError {
    case invalid
    var errorDescription: String? { "Use a name of 1–40 characters and choose a supported avatar. Photos must be under 1 MB." }
}

nonisolated struct ProfileStore {
    let url: URL

    static func local() throws -> ProfileStore {
        let root = try FileManager.default.url(for: .applicationSupportDirectory,
            in: .userDomainMask, appropriateFor: nil, create: true)
        return ProfileStore(url: root.appendingPathComponent("FocusFix/profile.json"))
    }

    func load() throws -> UserProfile? {
        guard FileManager.default.fileExists(atPath: url.path) else { return nil }
        return try JSONDecoder().decode(UserProfile.self, from: Data(contentsOf: url)).validated()
    }

    func save(_ profile: UserProfile) throws {
        let valid = try profile.validated()
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true,
            attributes: [.posixPermissions: 0o700])
        try JSONEncoder().encode(valid).write(to: url, options: .atomic)
    }
}
