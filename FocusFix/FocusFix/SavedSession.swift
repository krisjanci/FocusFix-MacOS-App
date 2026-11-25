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
    let conditions: [SessionCondition]
    let tags: [String]
    let tagColors: [String: String]
    let schemaVersion: Int
    let recordingContract: RecordingContract?
    private struct DurationMetadata: Decodable {
        let duration_seconds: Double?
    }
    var legacyContext: ActivityContext { .unknown }
    // Use the unique session folder name as the library row's identity.
    var id: String { folder.lastPathComponent }

    // Read one session's metadata, including compatibility with older or unfinished recordings.
    init(folder: URL) throws {
        self.folder = folder
        let values = try folder.resourceValues(forKeys: [.creationDateKey])
        let metadata: [String: Any]
        let metadataData: Data
        if try SessionStorage.contains("session.json", in: folder) {
            metadataData = try SessionStorage.data("session.json", in: folder)
            guard let decoded = try JSONSerialization.jsonObject(with: metadataData) as? [String: Any] else {
                throw RecordingContract.Invalid.contract
            }
            metadata = decoded
        } else { metadata = [:]; metadataData = Data("{}".utf8) }
        schemaVersion = metadata["schema_version"] as? Int ?? 0
        if schemaVersion < RecordingContract.schemaVersion,
           try SessionStorage.contains("context_intervals.json", in: folder) { throw RecordingContract.Invalid.contract }
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
        // Display timestamps in older metadata omit fractional seconds. The
        // capture manifest preserves the exact segment start, even after rotation.
        let capture = try? ResearchCaptureManifest.load(from: folder)
        let preciseStart = recordingContract.flatMap { contract -> Date? in
            guard let capture, capture.segmentID == contract.segmentID,
                  capture.recordingID == contract.recordingID else { return nil }
            return capture.capturedAtUTC
        }
        startedAt = preciseStart ?? start ?? values.creationDate ?? .distantPast
        // JSONSerialization can round a fractional NSNumber one ULP differently
        // from JSONDecoder. Use the contract's decoder for new-schema durations,
        // preserving the strict equality check without accepting mismatched bounds.
        let seconds = recordingContract != nil
            ? try JSONDecoder().decode(DurationMetadata.self, from: metadataData).duration_seconds
            : metadata["duration_seconds"] as? Double
        let validDuration = seconds.flatMap { $0.isFinite && $0 >= 0 ? $0 : nil }
        if let contract = recordingContract, contract.finalized {
            guard validDuration == contract.observedThrough - contract.elapsedOrigin else { throw RecordingContract.Invalid.bounds }
        }
        duration = validDuration
        endedAt = (metadata["ended_at_utc"] as? String).flatMap { formatter.date(from: $0) }
            ?? start.flatMap { date in validDuration.map { date.addingTimeInterval($0) } }
        status = metadata["status"] as? String ?? "metadata_unavailable"
        if let values = metadata["conditions"] {
            conditions = try SessionConditions.validated(JSONDecoder().decode([SessionCondition].self,
                from: JSONSerialization.data(withJSONObject: values)))
        } else { conditions = [] }
        tags = metadata["tags"] as? [String] ?? []
        tagColors = (try? SessionTags.colors(metadata["tag_colors"] as? [String: String] ?? [:], for: tags)) ?? [:]
    }

    var assignedWork: [AssignedWorkInterval] {
        (try? assignmentHistory()) ?? []
    }

    func assignmentHistory() throws -> [AssignedWorkInterval] {
        guard let recordingContract else { return [] }
        let journal = try WorkAssignmentJournal.load(from: folder)
        let coverage = try RecordingCoverage.load(session: self)
        return journal.intervals(in: recordingContract, observedWork: coverage.workSlices.map { ($0.start, $0.end) })
    }

    // Sum every recorded stint of this task, clipped to the completion instant.
    // Reads are performed off the main actor; missing legacy sidecars contain no task work.
    static func totalTaskWork(project: UUID, task: UUID, through finish: Date, root: URL) throws -> Double {
        let listing = try SessionFiles.inspect(in: root)
        guard listing.unreadable == 0 else { throw CocoaError(.fileReadCorruptFile) }
        var seconds = 0.0
        var seen = Set<UUID>()
        for session in listing.sessions {
            try Task.checkCancellation()
            guard let contract = session.recordingContract,
                  try SessionStorage.contains(WorkAssignmentJournal.filename, in: session.folder)
            else { continue }
            guard seen.insert(contract.segmentID).inserted else { throw CocoaError(.fileReadCorruptFile) }
            let cutoff = finish.timeIntervalSince(session.startedAt) + contract.elapsedOrigin
            for interval in try session.assignmentHistory()
            where interval.assignment.projectID == project && interval.assignment.taskID == task {
                seconds += max(0, min(interval.end, cutoff) - interval.start)
            }
        }
        return seconds
    }

    var assignmentNotice: String? {
        guard (try? SessionStorage.contains(WorkAssignmentJournal.filename, in: folder)) == true else { return nil }
        do { _ = try WorkAssignmentJournal.load(from: folder); return nil }
        catch { return "Project/task history could not be read. The original file was kept." }
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

// The same day grouping drives the library and exports without moving local originals.
nonisolated struct SessionDay: Identifiable {
    let id: String
    let date: Date
    let sessions: [SavedSession]
    var folderName: String { "FocusFix Day [\(id)]" }

    static func groups(_ sessions: [SavedSession], calendar: Calendar = .current) -> [SessionDay] {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.timeZone = calendar.timeZone
        formatter.dateFormat = "yyyy-MM-dd"
        let buckets = Dictionary(grouping: sessions) { calendar.startOfDay(for: $0.startedAt) }
        return buckets.keys.sorted(by: >).map { day in
            SessionDay(id: formatter.string(from: day), date: day, sessions: buckets[day]!.sorted {
                $0.startedAt == $1.startedAt ? $0.id < $1.id : $0.startedAt > $1.startedAt
            })
        }
    }
}

// File operations have no UI state and must not inherit the app's MainActor default.
nonisolated enum SessionFiles {
    static let minimumDuration: Double = 0

    static func qualifies(duration: Double) -> Bool {
        duration.isFinite && duration >= minimumDuration
    }

    // In-progress data stays hidden until Stop; every completed recording is retained.
    static func pendingRoot(in root: URL) -> URL {
        root.appendingPathComponent(".pending", isDirectory: true)
    }

    // Only the current recording is removed; existing saved sessions are never pruned.
    static func retainRecording(_ folder: URL, duration: Double, root: URL) throws -> URL? {
        try validate(folder, in: pendingRoot(in: root), active: nil)
        _ = try SavedSession(folder: folder)
        // Invalid durations leave the original files intact for recovery.
        guard qualifies(duration: duration) else { throw RecordingContract.Invalid.bounds }
        let destination = root.appendingPathComponent(folder.lastPathComponent, isDirectory: true)
        try FileManager.default.moveItem(at: folder, to: destination)
        return destination
    }

    // Never extend a crashed recording to launch time. Keep unreadable files for inspection.
    static func recoverPending(in root: URL) throws -> Int {
        let pending = pendingRoot(in: root)
        guard FileManager.default.fileExists(atPath: pending.path) else { return 0 }
        var count = 0
        var failures = 0
        for folder in try FileManager.default.contentsOfDirectory(at: pending, includingPropertiesForKeys: nil) {
            do {
                try validate(folder, in: pending, active: nil)
                var contract = try RecordingContract.load(from: folder)
                let url = folder.appendingPathComponent("session.json")
                let properties = try url.resourceValues(forKeys: [.isRegularFileKey, .isSymbolicLinkKey])
                guard properties.isRegularFile == true, properties.isSymbolicLink != true else { throw RecordingContract.Invalid.contract }
                guard var metadata = try JSONSerialization.jsonObject(with: Data(contentsOf: url)) as? [String: Any],
                      metadata["schema_version"] as? Int == RecordingContract.schemaVersion,
                      metadata["recording_format"] as? String == RecordingContract.format,
                      metadata["required_capabilities"] as? [String] == RecordingContract.requiredCapabilities,
                      metadata["recording_id"] as? String == contract.recordingID.uuidString,
                      metadata["segment_id"] as? String == contract.segmentID.uuidString,
                      metadata["recording_mode"] as? String == contract.mode.rawValue else { throw RecordingContract.Invalid.contract }
                if !contract.finalized { try contract.finish(at: contract.observedThrough); try contract.save(to: folder) }
                metadata["duration_seconds"] = contract.observedThrough - contract.elapsedOrigin
                metadata["status"] = "crash_recovered_observed_only"
                // Raw CSV tails beyond the checkpoint remain original bytes; readers must exclude them.
                metadata["recovery_policy"] = "Only data strictly before observedThrough are eligible; ignore any uncheckpointed raw tail. No downtime filled."
                try JSONSerialization.data(withJSONObject: metadata, options: [.sortedKeys, .prettyPrinted]).write(to: url, options: .atomic)
                let destination = root.appendingPathComponent(folder.lastPathComponent)
                try FileManager.default.moveItem(at: folder, to: destination)
                        count += 1
            } catch { failures += 1 }
        }
        if failures > 0 {
            throw NSError(domain: "FocusFix.Recovery", code: failures, userInfo: [
                NSLocalizedDescriptionKey: "An interrupted recording could not be finalized; original files were kept.",
                "recoveredCount": count
            ])
        }
        return count
    }

    // Directory URLs may differ only by a trailing slash or a parent-directory alias.
    static func sameFolder(_ first: URL, _ second: URL?) -> Bool {
        guard let second else { return false }
        return first.resolvingSymlinksInPath().standardizedFileURL.path
            == second.resolvingSymlinksInPath().standardizedFileURL.path
    }
    static func updateConditions(_ values: [SessionCondition], for session: SavedSession, root: URL, active: URL?) throws {
        try validate(session.folder, in: root, active: active)
        if SessionStorage.isArchived(session.folder) {
            try SessionStorage.edit(session.folder) { stage in
                try updateConditions(values, for: SavedSession(folder: stage), root: stage.deletingLastPathComponent(), active: nil)
            }
            return
        }
        let valid = try SessionConditions.validated(values)
        let url = session.folder.appendingPathComponent("session.json")
        var metadata: [String: Any]
        if FileManager.default.fileExists(atPath: url.path) {
            let properties = try url.resourceValues(forKeys: [.isRegularFileKey, .isSymbolicLinkKey])
            guard properties.isRegularFile == true, properties.isSymbolicLink != true,
                  let existing = try JSONSerialization.jsonObject(with: Data(contentsOf: url)) as? [String: Any] else {
                throw SessionTags.TagError("This session's metadata could not be read. Its file has been kept.")
            }
            metadata = existing
        } else {
            metadata = ["session_id": session.id, "started_at_utc": ISO8601DateFormatter().string(from: session.startedAt),
                        "status": session.status]
        }
        metadata["conditions"] = try JSONSerialization.jsonObject(with: JSONEncoder().encode(valid))
        try JSONSerialization.data(withJSONObject: metadata, options: [.prettyPrinted, .sortedKeys]).write(to: url, options: .atomic)
    }

    // Edit labels without recreating metadata or touching activity/survey files.
    static func updateTags(_ tags: [String], colors: [String: String] = [:], for session: SavedSession, root: URL, active: URL?) throws {
        try validate(session.folder, in: root, active: active)
        if SessionStorage.isArchived(session.folder) {
            try SessionStorage.edit(session.folder) { stage in
                try updateTags(tags, colors: colors, for: SavedSession(folder: stage), root: stage.deletingLastPathComponent(), active: nil)
            }
            return
        }
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

    static func correctContext(_ context: ActivityContext, start: Double, end: Double,
                               for session: SavedSession, root: URL, active: URL?,
                               actionID: UUID = UUID(), expectedRevision: Int) throws {
        try validate(session.folder, in: root, active: active)
        if SessionStorage.isArchived(session.folder) {
            try SessionStorage.edit(session.folder) { stage in
                try correctContext(context, start: start, end: end, for: SavedSession(folder: stage), root: stage.deletingLastPathComponent(), active: nil, actionID: actionID, expectedRevision: expectedRevision)
            }
            return
        }
        var contract = try RecordingContract.load(from: session.folder)
        try contract.correctContext(context, start: start, end: end,
            effectiveAt: session.startedAt.addingTimeInterval(start - contract.elapsedOrigin),
            recordedAt: Date(), actionID: actionID, expectedRevision: expectedRevision)
        try contract.save(to: session.folder)
    }

    // Locate the app's local Sessions directory in Application Support.
    static func root() throws -> URL {
        try FileManager.default.url(for: .applicationSupportDirectory,
            in: .userDomainMask, appropriateFor: nil, create: true)
            .appendingPathComponent("FocusFix/Sessions", isDirectory: true)
    }

    // Read valid session folders and sort them newest first, without following symlinks.
    static func list(in root: URL) throws -> [SavedSession] {
        try inspect(in: root).sessions
    }
    static func inspect(in root: URL) throws -> (sessions: [SavedSession], unreadable: Int) {
        try Task.checkCancellation()
        guard FileManager.default.fileExists(atPath: root.path) else { return ([], 0) }
        let folders = try FileManager.default.contentsOfDirectory(at: root,
            includingPropertiesForKeys: [.isDirectoryKey, .isSymbolicLinkKey], options: [.skipsHiddenFiles])
            .filter { url in
                try Task.checkCancellation()
                let values = try url.resourceValues(forKeys: [.isDirectoryKey, .isSymbolicLinkKey])
                return values.isDirectory == true && values.isSymbolicLink != true
            }
        var sessions: [SavedSession] = [], unreadable = 0
        for folder in folders {
            try Task.checkCancellation()
            do { sessions.append(try SavedSession(folder: folder)) }
            catch { unreadable += 1 }
        }
        return (sessions.sorted { $0.startedAt > $1.startedAt }, unreadable)
    }

    struct DeletionResult {
        var deleted: [SavedSession] = []
        var failures: [String] = []
    }
    static func deleteSelected(_ sessions: [SavedSession], root: URL, active: URL?,
                               remove: (URL) throws -> Void = { try FileManager.default.trashItem(at: $0, resultingItemURL: nil) }) throws -> DeletionResult {
        // Revalidate the entire selection before any recoverable Trash moves.
        for session in sessions { try validate(session.folder, in: root, active: active) }
        var result = DeletionResult()
        for session in sessions {
            do {
                try validate(session.folder, in: root, active: active)
                try remove(session.folder)
                result.deleted.append(session)
            }
            catch { result.failures.append("\(session.id): \(error.localizedDescription)") }
        }
        return result
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
    static func exportOriginal(_ session: SavedSession, to destination: URL, root: URL, active: URL?) throws -> URL {
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
        try SessionStorage.withFolder(session.folder) { source in
            try FileManager.default.copyItem(at: source, to: copy)
        }
        do {
            try normalizeExportContexts(in: copy)
            return copy
        } catch {
            try? FileManager.default.removeItem(at: copy)
            throw error
        }
    }

    // Change only known activity-context fields in the exported copy. In particular,
    // tags, free text, IDs, timestamps and intervention phases are never substituted.
    private static func replacingLegacyContext(_ value: Any, path: ArraySlice<String>) -> (Any, Bool) {
        guard let key = path.first else {
            return (value as? String == "non_work" ? "unknown" : value, value as? String == "non_work")
        }
        if key == "*", var array = value as? [Any] {
            var changed = false
            for index in array.indices {
                let result = replacingLegacyContext(array[index], path: path.dropFirst())
                array[index] = result.0; changed = changed || result.1
            }
            return (array, changed)
        }
        guard var object = value as? [String: Any], let child = object[key] else { return (value, false) }
        let result = replacingLegacyContext(child, path: path.dropFirst())
        object[key] = result.0
        return (object, result.1)
    }

    private static func normalizedExportJSON(_ data: Data, paths: [[String]]) throws -> Data {
        var value = try JSONSerialization.jsonObject(with: data)
        var changed = false
        for path in paths {
            let result = replacingLegacyContext(value, path: path[...])
            value = result.0; changed = changed || result.1
        }
        return try changed ? JSONSerialization.data(withJSONObject: value, options: [.sortedKeys]) : data
    }

    private static func normalizeExportContexts(in folder: URL) throws {
        let files = Set(try FileManager.default.contentsOfDirectory(atPath: folder.path))
        let specifications: [(String, [[String]], Bool)] = [
            ("context_intervals.json", [["intervals", "*", "context"], ["revisions", "*", "previousIntervals", "*", "context"]], false),
            ("reminders.jsonl", [["request", "context"]], true),
            ("study_check_ins.jsonl", [["prompt", "contextAtPrompt"]], true)
        ]
        for (name, paths, lines) in specifications where files.contains(name) {
            let file = folder.appendingPathComponent(name)
            let properties = try file.resourceValues(forKeys: [.isRegularFileKey, .isSymbolicLinkKey])
            guard properties.isRegularFile == true, properties.isSymbolicLink != true else {
                throw CocoaError(.fileReadUnsupportedScheme)
            }
            if !lines {
                let data = try Data(contentsOf: file)
                let normalized = try normalizedExportJSON(data, paths: paths)
                if normalized != data { try normalized.write(to: file, options: .atomic) }
                continue
            }
            // Stream logs, retaining byte-for-byte formatting on unchanged lines.
            let temporary = folder.appendingPathComponent(".normalized-\(UUID().uuidString)")
            FileManager.default.createFile(atPath: temporary.path, contents: nil)
            let input = try FileHandle(forReadingFrom: file)
            let output = try FileHandle(forWritingTo: temporary)
            defer { try? input.close(); try? output.close(); try? FileManager.default.removeItem(at: temporary) }
            var pending = Data()
            func writeLine(_ data: Data) throws {
                guard data.count <= 16 * 1024 * 1024 else { throw CocoaError(.fileReadTooLarge) }
                if data.allSatisfy({ $0 == 32 || $0 == 9 || $0 == 13 }) { try output.write(contentsOf: data) }
                else { try output.write(contentsOf: normalizedExportJSON(data, paths: paths)) }
            }
            while let chunk = try input.read(upToCount: 64 * 1024), !chunk.isEmpty {
                pending.append(chunk)
                while let newline = pending.firstIndex(of: 10) {
                    try writeLine(Data(pending[..<newline]))
                    try output.write(contentsOf: Data([10]))
                    pending.removeSubrange(...newline)
                }
                // Consistent with the context snapshot's per-document safety bound.
                guard pending.count <= 16 * 1024 * 1024 else { throw CocoaError(.fileReadTooLarge) }
            }
            if !pending.isEmpty { try writeLine(pending) }
            try output.close(); try input.close()
            try FileManager.default.removeItem(at: file)
            try FileManager.default.moveItem(at: temporary, to: file)
        }
        let note = """
        FocusFix local export
        Activity context labels are work and unknown. Historical non_work labels in context intervals,
        revision history, reminder requests and study check-in prompts are exported as unknown.
        Saved originals are unchanged. Times, identifiers, unrelated text and activity CSVs are preserved.
        If present, work_assignments.json contains private project/task name snapshots on the logical recording clock.
        Assignment time counts only observed declared work, excluding breaks, check-ins and Unknown activity.
        This private sidecar is included in local exports and excluded from shared recording uploads.
        Work is a declaration of intent; breaks and missing observations remain separate.
        """
        let noteFile = folder.appendingPathComponent("export-notes.txt")
        // Do not follow a copied symlink when writing the reserved export note.
        if files.contains("export-notes.txt") { try FileManager.default.removeItem(at: noteFile) }
        try note.write(to: noteFile, atomically: true, encoding: .utf8)
    }

    // Re-read storage and copy every inactive session into one new folder.
    // Remove an incomplete batch if any copy fails, leaving originals untouched.
    static func exportAllOriginal(to destination: URL, root: URL, active: URL?) throws -> (folder: URL, count: Int) {
        let target = try exportDestination(destination, root: root)
        let listing = try inspect(in: root)
        guard listing.unreadable == 0 else { throw RecordingContract.Invalid.contract }
        let sessions = listing.sessions.filter { !sameFolder($0.folder, active) }
        guard !sessions.isEmpty else {
            throw NSError(domain: "FocusFix", code: 3, userInfo: [NSLocalizedDescriptionKey:
                "There are no saved sessions to export. Stop and save the current recording first."])
        }
        return try exportSelectedOriginal(sessions, to: target, root: root, active: active)
    }

    // Validate the entire explicit selection before copying; never silently skip a selected recording.
    static func exportSelectedOriginal(_ sessions: [SavedSession], to destination: URL, root: URL,
                               active: URL?) throws -> (folder: URL, count: Int) {
        let target = try exportDestination(destination, root: root)
        guard !sessions.isEmpty, Set(sessions.map(\.id)).count == sessions.count else {
            throw NSError(domain: "FocusFix", code: 3, userInfo: [NSLocalizedDescriptionKey:
                "Select one or more distinct saved sessions to export."])
        }
        for session in sessions { try validate(session.folder, in: root, active: active) }
        var batch = target.appendingPathComponent("FocusFix Sessions", isDirectory: true)
        var number = 2
        while FileManager.default.fileExists(atPath: batch.path) {
            batch = target.appendingPathComponent("FocusFix Sessions (\(number))", isDirectory: true)
            number += 1
        }
        try FileManager.default.createDirectory(at: batch, withIntermediateDirectories: false)
        do {
            for day in SessionDay.groups(sessions) {
                let destination: URL
                if day.sessions.count > 1 {
                    destination = batch.appendingPathComponent(day.folderName, isDirectory: true)
                    try FileManager.default.createDirectory(at: destination, withIntermediateDirectories: false)
                } else { destination = batch }
                for session in day.sessions {
                    _ = try exportOriginal(session, to: destination, root: root, active: active)
                }
            }
        } catch {
            try? FileManager.default.removeItem(at: batch)
            throw error
        }
        return (batch, sessions.count)
    }

    // User-facing exports combine every selected session into one timeline per day.
    static func export(_ session: SavedSession, to destination: URL, root: URL, active: URL?) throws -> URL {
        try exportSelected([session], to: destination, root: root, active: active).folder
    }
    static func exportAll(to destination: URL, root: URL, active: URL?) throws -> (folder: URL, count: Int) {
        let listing = try inspect(in: root)
        guard listing.unreadable == 0 else { throw RecordingContract.Invalid.contract }
        return try exportSelected(listing.sessions.filter { !sameFolder($0.folder, active) }, to: destination, root: root, active: active)
    }
    static func exportSelected(_ sessions: [SavedSession], to destination: URL, root: URL, active: URL?,
                               timeZone: TimeZone = .current) throws -> (folder: URL, count: Int) {
        let target = try exportDestination(destination, root: root)
        guard !sessions.isEmpty, Set(sessions.map(\.id)).count == sessions.count else {
            throw NSError(domain: "FocusFix", code: 3, userInfo: [NSLocalizedDescriptionKey: "Select one or more distinct saved sessions to export."])
        }
        for session in sessions { try validate(session.folder, in: root, active: active) }
        let manager = FileManager.default
        var batch = target.appendingPathComponent("FocusFix Activity"), number = 2
        while manager.fileExists(atPath: batch.path) {
            batch = target.appendingPathComponent("FocusFix Activity (\(number))"); number += 1
        }
        try manager.createDirectory(at: batch, withIntermediateDirectories: false, attributes: [.posixPermissions: 0o700])
        do {
            try DailyTimeline.export(sessions, to: batch, timeZone: timeZone)
            return (batch, sessions.count)
        } catch {
            try? manager.removeItem(at: batch)
            throw error
        }
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

// One latest-request owner for library scans. Cancelling a wrapper also cancels its
// worker; requests superseded before execution never start detached disk work.
@MainActor
final class SessionLibraryLoader {
    typealias Listing = (sessions: [SavedSession], unreadable: Int)
    private var task: Task<Void, Never>?
    func cancel() { task?.cancel() }
    func load(root: URL, inspect: @escaping @Sendable (URL) throws -> Listing = { try SessionFiles.inspect(in: $0) },
              completion: @escaping (Result<Listing, Error>) -> Void) {
        task?.cancel()
        task = Task {
            guard !Task.isCancelled else { return }
            let worker = Task.detached(priority: .utility) { try Task.checkCancellation(); return try inspect(root) }
            do {
                let listing = try await withTaskCancellationHandler(operation: { try await worker.value }, onCancel: { worker.cancel() })
                guard !Task.isCancelled else { return }
                completion(.success(listing))
            } catch {
                guard !Task.isCancelled else { return }
                completion(.failure(error))
            }
        }
    }
}
