// MARK: - FF: STORAGE
// Reads saved sessions and safely copies them for export. Local originals stay in Application Support.

import Foundation

// Read existing sessions without changing their CSVs or requiring a migration.
// Immutable metadata can be read by background exports as well as the UI.
nonisolated struct SavedSession: Identifiable, Hashable {
    let folder: URL
    let startedAt: Date
    let endedAt: Date?
    let duration: Double?
    let status: String
    let tags: [String]
    let tagColors: [String: String]
    let schemaVersion: Int
    let recordingContract: RecordingContract?
    var legacyContext: ActivityContext { .unknown }
    // Use the unique session folder name as the library row's identity.
    var id: String { folder.lastPathComponent }

    // Read one session's metadata, including compatibility with older or unfinished recordings.
    init(folder: URL) throws {
        self.folder = folder
        let values = try folder.resourceValues(forKeys: [.creationDateKey])
        let metadataURL = folder.appendingPathComponent("session.json")
        let data = try? Data(contentsOf: metadataURL)
        let metadata = data.flatMap { try? JSONSerialization.jsonObject(with: $0) as? [String: Any] } ?? [:]
        schemaVersion = metadata["schema_version"] as? Int ?? 0
        if schemaVersion >= RecordingContract.schemaVersion {
            guard schemaVersion == RecordingContract.schemaVersion,
                  metadata["recording_format"] as? String == RecordingContract.format,
                  metadata["required_capabilities"] as? [String] == RecordingContract.requiredCapabilities else {
                throw RecordingContract.Invalid.contract
            }
            let contract = try RecordingContract.load(from: folder)
            guard metadata["recording_id"] as? String == contract.recordingID.uuidString,
                  metadata["segment_id"] as? String == contract.segmentID.uuidString,
                  metadata["recording_mode"] as? String == contract.mode.rawValue else { throw RecordingContract.Invalid.contract }
            recordingContract = contract
        } else { recordingContract = nil }
        let formatter = ISO8601DateFormatter()
        let start = (metadata["started_at_utc"] as? String).flatMap { formatter.date(from: $0) }
        startedAt = start ?? values.creationDate ?? .distantPast
        let seconds = metadata["duration_seconds"] as? Double
        let validDuration = seconds.flatMap { $0.isFinite && $0 >= 0 ? $0 : nil }
        if let contract = recordingContract, contract.finalized {
            guard validDuration == contract.observedThrough else { throw RecordingContract.Invalid.bounds }
        }
        duration = validDuration
        endedAt = (metadata["ended_at_utc"] as? String).flatMap { formatter.date(from: $0) }
            ?? start.flatMap { date in validDuration.map { date.addingTimeInterval($0) } }
        status = metadata["status"] as? String ?? "metadata_unavailable"
        tags = metadata["tags"] as? [String] ?? []
        tagColors = (try? SessionTags.colors(metadata["tag_colors"] as? [String: String] ?? [:], for: tags)) ?? [:]
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

// File operations have no UI state and must not inherit the app's MainActor default.
nonisolated enum SessionFiles {
    static let minimumDuration: Double = 15 * 60

    static func qualifies(duration: Double) -> Bool {
        duration.isFinite && duration >= minimumDuration
    }

    // In-progress data stays hidden from history and exports until Stop qualifies it.
    static func pendingRoot(in root: URL) -> URL {
        root.appendingPathComponent(".pending", isDirectory: true)
    }

    // Only the current recording is removed; existing saved sessions are never pruned.
    static func retainRecording(_ folder: URL, duration: Double, root: URL) throws -> URL? {
        try validate(folder, in: pendingRoot(in: root), active: nil)
        guard qualifies(duration: duration) else {
            try FileManager.default.removeItem(at: folder)
            return nil
        }
        let saved = root.appendingPathComponent(folder.lastPathComponent, isDirectory: true)
        try FileManager.default.moveItem(at: folder, to: saved)
        return saved
    }

    // Directory URLs may differ only by a trailing slash or a parent-directory alias.
    static func sameFolder(_ first: URL, _ second: URL?) -> Bool {
        guard let second else { return false }
        return first.resolvingSymlinksInPath().standardizedFileURL.path
            == second.resolvingSymlinksInPath().standardizedFileURL.path
    }
    // Edit labels without recreating metadata or touching activity/survey files.
    static func updateTags(_ tags: [String], colors: [String: String] = [:], for session: SavedSession, root: URL, active: URL?) throws {
        try validate(session.folder, in: root, active: active)
        let valid = try SessionTags.validated(tags)
        let validColors = try SessionTags.colors(colors, for: valid)
        let url = session.folder.appendingPathComponent("session.json")
        var metadata: [String: Any]
        if FileManager.default.fileExists(atPath: url.path) {
            let values = try url.resourceValues(forKeys: [.isRegularFileKey, .isSymbolicLinkKey])
            guard values.isRegularFile == true, values.isSymbolicLink != true else {
                throw SessionTags.TagError("This session's metadata is not a regular local file.")
            }
            guard let existing = try JSONSerialization.jsonObject(with: Data(contentsOf: url)) as? [String: Any] else {
                throw SessionTags.TagError("This session's metadata could not be read. Its file has been kept.")
            }
            metadata = existing
        } else {
            // Unfinished legacy folders may have no metadata yet.
            metadata = ["session_id": session.id,
                        "started_at_utc": ISO8601DateFormatter().string(from: session.startedAt),
                        "status": session.status]
        }
        metadata["tags"] = valid
        metadata["tag_colors"] = validColors
        try JSONSerialization.data(withJSONObject: metadata, options: [.prettyPrinted, .sortedKeys])
            .write(to: url, options: .atomic)
    }

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
        guard sameFolder(source.deletingLastPathComponent(), root),
              values.isDirectory == true, values.isSymbolicLink != true,
              !sameFolder(source, active) else {
            throw NSError(domain: "FocusFix", code: 1, userInfo: [NSLocalizedDescriptionKey:
                "This session is recording or is not a valid saved session."])
        }
    }

    // Copy a session to a new export folder, adding a suffix instead of overwriting an existing export.
    static func export(_ session: SavedSession, to destination: URL, root: URL, active: URL?) throws -> URL {
        try validate(session.folder, in: root, active: active)
        let target = try exportDestination(destination, root: root)
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

    // Re-read storage and copy every inactive session into one new folder.
    // Remove an incomplete batch if any copy fails, leaving originals untouched.
    static func exportAll(to destination: URL, root: URL, active: URL?) throws -> (folder: URL, count: Int) {
        let target = try exportDestination(destination, root: root)
        let sessions = try list(in: root).filter { !sameFolder($0.folder, active) }
        guard !sessions.isEmpty else {
            throw NSError(domain: "FocusFix", code: 3, userInfo: [NSLocalizedDescriptionKey:
                "There are no saved sessions to export. Stop and save the current recording first."])
        }
        var batch = target.appendingPathComponent("FocusFix Sessions", isDirectory: true)
        var number = 2
        while FileManager.default.fileExists(atPath: batch.path) {
            batch = target.appendingPathComponent("FocusFix Sessions (\(number))", isDirectory: true)
            number += 1
        }
        try FileManager.default.createDirectory(at: batch, withIntermediateDirectories: false)
        do {
            for session in sessions {
                _ = try export(session, to: batch, root: root, active: active)
            }
        } catch {
            try? FileManager.default.removeItem(at: batch)
            throw error
        }
        return (batch, sessions.count)
    }

    private static func exportDestination(_ destination: URL, root: URL) throws -> URL {
        let target = destination.resolvingSymlinksInPath().standardizedFileURL
        let storage = root.resolvingSymlinksInPath().standardizedFileURL
        guard target.path != storage.path, !target.path.hasPrefix(storage.path + "/") else {
            throw NSError(domain: "FocusFix", code: 2, userInfo: [NSLocalizedDescriptionKey:
                "Choose an export location outside FocusFix's session storage."])
        }
        return target
    }
}
