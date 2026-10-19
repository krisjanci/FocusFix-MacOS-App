// MARK: - FF: STORAGE
// Reads saved sessions and safely copies them for export. Local originals stay in Application Support.

import Foundation

// Read existing sessions without changing their CSVs or requiring a migration.
struct SavedSession: Identifiable, Hashable {
    let folder: URL
    let startedAt: Date
    let endedAt: Date?
    let duration: Double?
    let status: String
    // Use the unique session folder name as the library row's identity.
    var id: String { folder.lastPathComponent }

    // Read one session's metadata, including compatibility with older or unfinished recordings.
    init(folder: URL) throws {
        self.folder = folder
        let values = try folder.resourceValues(forKeys: [.creationDateKey])
        let metadataURL = folder.appendingPathComponent("session.json")
        let data = try? Data(contentsOf: metadataURL)
        let metadata = data.flatMap { try? JSONSerialization.jsonObject(with: $0) as? [String: Any] } ?? [:]
        let formatter = ISO8601DateFormatter()
        let start = (metadata["started_at_utc"] as? String).flatMap { formatter.date(from: $0) }
        startedAt = start ?? values.creationDate ?? .distantPast
        let seconds = metadata["duration_seconds"] as? Double
        let validDuration = seconds.flatMap { $0.isFinite && $0 >= 0 ? $0 : nil }
        duration = validDuration
        endedAt = (metadata["ended_at_utc"] as? String).flatMap { formatter.date(from: $0) }
            ?? start.flatMap { date in validDuration.map { date.addingTimeInterval($0) } }
        status = metadata["status"] as? String ?? "metadata_unavailable"
    }

    // Build the readable FocusFix Session name from local start and end dates.
    func exportName(timeZone: TimeZone = .current) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.timeZone = timeZone
        // Hyphens in the time avoid characters that are unsafe in file names.
        formatter.dateFormat = "yyyy-MM-dd HH-mm-ss"
        let end = endedAt.map { formatter.string(from: $0) } ?? "unfinished"
        return "FocusFix Session [\(formatter.string(from: startedAt))-\(end)]"
    }
}

enum SessionFiles {
    // Locate the app's local Sessions directory in Application Support.
    static func root() throws -> URL {
        try FileManager.default.url(for: .applicationSupportDirectory,
            in: .userDomainMask, appropriateFor: nil, create: true)
            .appendingPathComponent("FocusFix/Sessions", isDirectory: true)
    }

    // Read valid session folders and sort them newest first, without following symlinks.
    static func list(in root: URL) throws -> [SavedSession] {
        guard FileManager.default.fileExists(atPath: root.path) else { return [] }
        return try FileManager.default.contentsOfDirectory(at: root,
            includingPropertiesForKeys: [.isDirectoryKey, .isSymbolicLinkKey], options: [.skipsHiddenFiles])
            .filter { url in
                let values = try url.resourceValues(forKeys: [.isDirectoryKey, .isSymbolicLinkKey])
                return values.isDirectory == true && values.isSymbolicLink != true
            }
            .map { try SavedSession(folder: $0) }
            .sorted { $0.startedAt > $1.startedAt }
    }

    // Only operate on a direct session directory, never the storage root or a symlink.
    // Reject active sessions, symlinks and folders outside the expected session directory.
    static func validate(_ folder: URL, in root: URL, active: URL?) throws {
        let source = folder.standardizedFileURL
        let values = try source.resourceValues(forKeys: [.isDirectoryKey, .isSymbolicLinkKey])
        guard source.deletingLastPathComponent() == root.standardizedFileURL,
              values.isDirectory == true, values.isSymbolicLink != true,
              source != active?.standardizedFileURL else {
            throw NSError(domain: "FocusFix", code: 1, userInfo: [NSLocalizedDescriptionKey:
                "This session is recording or is not a valid saved session."])
        }
    }

    // Copy a session to a new export folder, adding a suffix instead of overwriting an existing export.
    static func export(_ session: SavedSession, to destination: URL, root: URL, active: URL?) throws -> URL {
        try validate(session.folder, in: root, active: active)
        let target = destination.resolvingSymlinksInPath().standardizedFileURL
        let storage = root.resolvingSymlinksInPath().standardizedFileURL
        guard target != storage, !target.path.hasPrefix(storage.path + "/") else {
            throw NSError(domain: "FocusFix", code: 2, userInfo: [NSLocalizedDescriptionKey:
                "Choose an export location outside FocusFix's session storage."])
        }
        let name = session.exportName()
        var copy = target.appendingPathComponent(name, isDirectory: true)
        var number = 2
        while FileManager.default.fileExists(atPath: copy.path) {
            copy = target.appendingPathComponent("\(name) (\(number))", isDirectory: true)
            number += 1
        }
        // copyItem fails rather than overwriting if another file appears here.
        try FileManager.default.copyItem(at: session.folder, to: copy)
        return copy
    }
}
