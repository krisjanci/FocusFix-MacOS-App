// MARK: - FF: RESEARCH SHARING
// Explicitly consented, finished sessions only. Profiles and account secrets are never archived.
import Foundation

nonisolated struct ResearchConsent: Codable, Equatable {
    let id: UUID
    let owner: UUID
    let origin: String
    let startedAt: Date
    let studyVersion: String
}
nonisolated struct ResearchSession: Codable, Equatable, Identifiable {
    let id: String
    let consentID: UUID
    let startedAt: Date
    let endedAt: Date
}
nonisolated struct ResearchBatch: Codable, Equatable {
    let id: UUID
    let sessionIDs: [String]
}
nonisolated struct ResearchSharingState: Codable, Equatable {
    var consent: ResearchConsent?
    var sessions: [ResearchSession] = []
    var batch: ResearchBatch?

    mutating func enable(owner: UUID, origin: String, at date: Date, studyVersion: String) {
        consent = ResearchConsent(id: UUID(), owner: owner, origin: origin, startedAt: date, studyVersion: studyVersion)
        sessions = []
        batch = nil
    }
    mutating func disable() { self = ResearchSharingState() }
    mutating func enqueue(id: String, startedAt: Date, endedAt: Date, captured: ResearchConsent?) -> Bool {
        guard let consent, captured == consent, startedAt >= consent.startedAt, endedAt >= startedAt,
              UUID(uuidString: id) != nil, !sessions.contains(where: { $0.id == id }) else { return false }
        sessions.append(ResearchSession(id: id, consentID: consent.id, startedAt: startedAt, endedAt: endedAt))
        return true
    }
    mutating func acknowledge(batchID: UUID, at date: Date) {
        guard let batch, batch.id == batchID else { return }
        let ids = Set(batch.sessionIDs)
        sessions.removeAll { ids.contains($0.id) }
        self.batch = nil
    }
}

nonisolated enum ResearchArchive {
    static let files = ["events.csv", "mouse_movement.csv", "breaks.csv", "surveys.csv", "survey_prompts.csv", "session.json"]
    static let maximumRawBytes = 100 * 1024 * 1024
    static let maximumZIPBytes = 25 * 1024 * 1024

    // Select whole sessions in order. Never truncate or silently drop a recording.
    static func select(_ sessions: [ResearchSession], root: URL) throws -> [String] {
        var selected: [String] = []
        var total = 0
        for session in sessions {
            let size = try sources(id: session.id, root: root).reduce(0) { sum, url in
                sum + (try url.resourceValues(forKeys: [.fileSizeKey]).fileSize ?? maximumRawBytes + 1)
            }
            guard size <= maximumRawBytes else { throw AccountFailure(message: "A recording exceeds the session ZIP limit. Export it from Sessions; no recordings were removed.") }
            if total + size > maximumRawBytes { break }
            selected.append(session.id)
            total += size
            break // One complete recording per archive.
        }
        return selected
    }

    private static func sources(id: String, root: URL) throws -> [URL] {
        guard UUID(uuidString: id) != nil else { throw AccountFailure(message: "Invalid recording identifier.") }
        let folder = root.appendingPathComponent(id, isDirectory: true)
        let values = try folder.resourceValues(forKeys: [.isDirectoryKey, .isSymbolicLinkKey])
        guard values.isDirectory == true, values.isSymbolicLink != true else {
            throw AccountFailure(message: "A queued recording is missing or unsafe. It was not shared.")
        }
        return try files.map { name in
            let url = folder.appendingPathComponent(name)
            let info = try url.resourceValues(forKeys: [.isRegularFileKey, .isSymbolicLinkKey])
            guard info.isRegularFile == true, info.isSymbolicLink != true else {
                throw AccountFailure(message: "A recording file is missing or unsafe. It was not shared.")
            }
            return url
        }
    }

    static func prepare(ids: [String], root: URL, destination: URL) throws -> Data {
        guard !ids.isEmpty else { throw AccountFailure(message: "No new consented sessions are ready.") }
        let manager = FileManager.default
        let staging = destination.deletingLastPathComponent().appendingPathComponent(UUID().uuidString, isDirectory: true)
        try manager.createDirectory(at: staging, withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
        defer { try? manager.removeItem(at: staging) }
        var total = 0
        var arguments: [String] = []
        for id in ids {
            let target = staging.appendingPathComponent(id, isDirectory: true)
            try manager.createDirectory(at: target, withIntermediateDirectories: false)
            for source in try sources(id: id, root: root) {
                total += try source.resourceValues(forKeys: [.fileSizeKey]).fileSize ?? maximumRawBytes + 1
                guard total <= maximumRawBytes else { throw AccountFailure(message: "The ZIP exceeds its raw-data limit. Your recordings are kept locally.") }
                try manager.copyItem(at: source, to: target.appendingPathComponent(source.lastPathComponent))
                arguments.append("\(id)/\(source.lastPathComponent)")
            }
        }
        let zip = staging.appendingPathComponent("session.zip")
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/zip")
        process.currentDirectoryURL = staging
        process.arguments = ["-q", "-X", zip.path] + arguments
        process.standardOutput = FileHandle.nullDevice
        process.standardError = FileHandle.nullDevice
        try process.run()
        process.waitUntilExit()
        guard process.terminationStatus == 0 else { throw AccountFailure(message: "The session ZIP could not be prepared.") }
        let size = try zip.resourceValues(forKeys: [.fileSizeKey]).fileSize ?? 0
        guard size > 0, size <= maximumZIPBytes else {
            throw AccountFailure(message: "The compressed ZIP exceeds 25 MB. Export recordings individually from Sessions; automatic delivery is paused.")
        }
        let data = try Data(contentsOf: zip)
        try data.write(to: destination, options: .atomic)
        try manager.setAttributes([.posixPermissions: 0o600], ofItemAtPath: destination.path)
        return data
    }
}
