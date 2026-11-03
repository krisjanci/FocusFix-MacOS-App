import Foundation

nonisolated struct ResearchArchiveScope: Codable, Equatable {
    let version: String
    let archiveVersion: Int
    let automaticActivity: Bool
    let nonWorkActivity: Bool
    let contextAndRevisions: Bool
    let optionalStudyChecks: Bool
    let determinationReference: String
    let reviewedConsentText: String
    let retentionTerms: String
    let downloadedDataDeletionTerms: String
    let modelTrainingTerms: String
    let futureTrainingAllowed: Bool?
    var complete: Bool {
        archiveVersion == 2 && automaticActivity && nonWorkActivity && contextAndRevisions && optionalStudyChecks
            && futureTrainingAllowed != nil
            && [version, determinationReference, reviewedConsentText, retentionTerms, downloadedDataDeletionTerms, modelTrainingTerms]
                .allSatisfy { !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
    }
}
nonisolated struct ResearchCaptureIdentity: Codable, Equatable {
    let owner: UUID
    let origin: String
    let consentID: UUID
    let studyVersion: String
    let consentStartedAtUTC: Date
    let scope: ResearchArchiveScope?
}
nonisolated struct ResearchCaptureManifest: Codable, Equatable {
    let recordingID: UUID
    let segmentID: UUID
    let capturedAtUTC: Date
    let identity: ResearchCaptureIdentity?
    func save(to folder: URL) throws {
        let encoder = JSONEncoder(); encoder.dateEncodingStrategy = .secondsSince1970
        try encoder.encode(self).write(to: folder.appendingPathComponent("research_eligibility.json"), options: .atomic)
    }
    static func load(from folder: URL) throws -> Self {
        let url = folder.appendingPathComponent("research_eligibility.json")
        let info = try url.resourceValues(forKeys: [.isRegularFileKey, .isSymbolicLinkKey, .fileSizeKey])
        guard info.isRegularFile == true, info.isSymbolicLink != true, (info.fileSize ?? Int.max) <= 1024 * 1024 else { throw RecordingContract.Invalid.contract }
        let decoder = JSONDecoder(); decoder.dateDecodingStrategy = .secondsSince1970
        return try decoder.decode(Self.self, from: Data(contentsOf: url))
    }
}
nonisolated enum ResearchArchiveContract {
    // Remains false until reviewed configuration AND disposable-service qualification.
    static let newFormatDeliveryQualified = false
    static let archiveVersion = 2
    static let files = ["session.json", "events.csv", "mouse_movement.csv", "breaks.csv", "surveys.csv",
                        "survey_prompts.csv", "context_intervals.json", "reminders.jsonl", "study_check_ins.jsonl"]
    static let maximumRawBytes = 100 * 1024 * 1024
    static let maximumZIPBytes = 25 * 1024 * 1024
    static let dailyCaptureCapSeconds: Double = 180 * 60
    enum Ineligible: Error { case qualification, scope, boundary, size, path }

    static func validate(folder: URL, current: ResearchCaptureIdentity?, dailyUsedSeconds: Double) throws -> [URL] {
        let info = try folder.resourceValues(forKeys: [.isDirectoryKey, .isSymbolicLinkKey])
        guard info.isDirectory == true, info.isSymbolicLink != true, UUID(uuidString: folder.lastPathComponent) != nil else { throw Ineligible.path }
        let saved = try SavedSession(folder: folder)
        let manifest = try ResearchCaptureManifest.load(from: folder)
        guard let contract = saved.recordingContract, contract.finalized, let duration = saved.duration,
              duration > 0, dailyUsedSeconds.isFinite, dailyUsedSeconds >= 0,
              duration + dailyUsedSeconds <= dailyCaptureCapSeconds else { throw Ineligible.size }
        guard let current, let scope = current.scope, scope.complete else { throw Ineligible.scope }
        guard manifest.identity == current, manifest.recordingID == contract.recordingID,
              manifest.segmentID == contract.segmentID, manifest.capturedAtUTC >= current.consentStartedAtUTC else { throw Ineligible.boundary }
        var total = 0
        return try files.map { name in
            let url = folder.appendingPathComponent(name)
            let properties = try url.resourceValues(forKeys: [.isRegularFileKey, .isSymbolicLinkKey, .fileSizeKey])
            guard properties.isRegularFile == true, properties.isSymbolicLink != true,
                  let bytes = properties.fileSize, bytes >= 0 else { throw Ineligible.path }
            total += bytes
            guard total <= maximumRawBytes else { throw Ineligible.size }
            return url
        }
    }
    static func eligibleForDelivery(folder: URL, current: ResearchCaptureIdentity?, dailyUsedSeconds: Double) -> Bool {
        guard newFormatDeliveryQualified else { return false }
        return (try? validate(folder: folder, current: current, dailyUsedSeconds: dailyUsedSeconds)) != nil
    }

    #if FOCUSFIX_SYNTHETIC_TESTS
    // Not compiled into the app. Explicitly marked generated fixtures only.
    static func prepareSynthetic(folder: URL, current: ResearchCaptureIdentity?, dailyUsedSeconds: Double, destination: URL) throws -> Data {
        let sources = try validate(folder: folder, current: current, dailyUsedSeconds: dailyUsedSeconds)
        let metadata = try JSONSerialization.jsonObject(with: Data(contentsOf: folder.appendingPathComponent("session.json"))) as? [String: Any]
        guard metadata?["synthetic_fixture"] as? Bool == true else { throw Ineligible.qualification }
        let stage = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: stage, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: stage) }
        let id = folder.lastPathComponent
        let target = stage.appendingPathComponent(id)
        try FileManager.default.createDirectory(at: target, withIntermediateDirectories: true)
        for source in sources { try FileManager.default.copyItem(at: source, to: target.appendingPathComponent(source.lastPathComponent)) }
        let manifest: [String: Any] = ["archive_version": archiveVersion, "synthetic": true,
            "recording_format": RecordingContract.format, "required_capabilities": RecordingContract.requiredCapabilities,
            "consent_id": current!.consentID.uuidString, "study_version": current!.studyVersion,
            "scope_version": current!.scope!.version, "files": files,
            "dataset_deletion_key": "archive_id + consent_id + recording_id + segment_id; inventory datasets and model versions externally"]
        try JSONSerialization.data(withJSONObject: manifest, options: [.sortedKeys]).write(to: target.appendingPathComponent("archive_manifest.json"))
        let zip = stage.appendingPathComponent("archive.zip")
        let process = Process(); process.executableURL = URL(fileURLWithPath: "/usr/bin/zip")
        process.currentDirectoryURL = stage
        process.arguments = ["-q", "-X", zip.path] + (files + ["archive_manifest.json"]).map { "\(id)/\($0)" }
        process.standardOutput = FileHandle.nullDevice; process.standardError = FileHandle.nullDevice
        try process.run(); process.waitUntilExit()
        guard process.terminationStatus == 0 else { throw Ineligible.path }
        let data = try Data(contentsOf: zip)
        guard data.count <= maximumZIPBytes else { throw Ineligible.size }
        try data.write(to: destination, options: .atomic)
        return data
    }
    #endif
}
