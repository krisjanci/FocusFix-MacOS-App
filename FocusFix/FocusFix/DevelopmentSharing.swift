import Foundation

// Product-development sharing is independent of study consent and study archives.
nonisolated struct DevelopmentConsent: Codable, Equatable {
    let id: UUID
    let owner: UUID
    let origin: String
    let policyVersion: String
    let startedAt: Date
}

nonisolated struct DevelopmentUpload: Codable, Equatable, Identifiable {
    let id: String
    let consentID: UUID
    let startedAt: Date
}

nonisolated struct DevelopmentSharingState: Codable, Equatable {
    var consent: DevelopmentConsent?
    var pending: [DevelopmentUpload] = []
    var pendingWithdrawals: [DevelopmentConsent] = []

    mutating func enable(_ value: DevelopmentConsent) {
        consent = value
        pending = []
    }
    mutating func disable() {
        if let consent, !pendingWithdrawals.contains(consent) { pendingWithdrawals.append(consent) }
        consent = nil
        pending = []
    }
    mutating func enqueue(folder: URL, startedAt: Date, captured: DevelopmentConsent?) -> Bool {
        guard let consent, captured == consent, startedAt >= consent.startedAt,
              UUID(uuidString: folder.lastPathComponent) != nil,
              !pending.contains(where: { $0.id == folder.lastPathComponent }) else { return false }
        pending.append(DevelopmentUpload(id: folder.lastPathComponent, consentID: consent.id, startedAt: startedAt))
        return true
    }
}

nonisolated enum DevelopmentArchive {
    // No optional study ratings, survey prompts, account secrets, or research eligibility files.
    static let files = ["session.json", "events.csv", "mouse_movement.csv", "breaks.csv",
                        "context_intervals.json", "reminders.jsonl"]
    static let maximumRawBytes = 100 * 1024 * 1024
    static let maximumZIPBytes = 25 * 1024 * 1024

    static func sources(id: String, root: URL) throws -> [URL] {
        guard UUID(uuidString: id) != nil else { throw RecordingContract.Invalid.contract }
        let folder = root.appendingPathComponent(id, isDirectory: true)
        try SessionFiles.validate(folder, in: root, active: nil)
        let saved = try SavedSession(folder: folder)
        guard saved.schemaVersion == RecordingContract.schemaVersion,
              saved.recordingContract?.finalized == true, saved.duration != nil else {
            throw RecordingContract.Invalid.contract
        }
        var total = 0
        return try files.map { name in
            let url = folder.appendingPathComponent(name)
            let info = try url.resourceValues(forKeys: [.isRegularFileKey, .isSymbolicLinkKey, .fileSizeKey])
            guard info.isRegularFile == true, info.isSymbolicLink != true,
                  let size = info.fileSize, size >= 0 else { throw RecordingContract.Invalid.contract }
            total += size
            guard total <= maximumRawBytes else { throw RecordingContract.Invalid.contract }
            return url
        }
    }

    static func prepare(id: String, root: URL, consent: DevelopmentConsent, destination: URL) throws -> Data {
        let sources = try sources(id: id, root: root)
        let manager = FileManager.default
        let stage = destination.deletingLastPathComponent().appendingPathComponent(UUID().uuidString, isDirectory: true)
        try manager.createDirectory(at: stage, withIntermediateDirectories: true,
                                    attributes: [.posixPermissions: 0o700])
        defer { try? manager.removeItem(at: stage) }
        let target = stage.appendingPathComponent(id, isDirectory: true)
        try manager.createDirectory(at: target, withIntermediateDirectories: false)
        for source in sources {
            try manager.copyItem(at: source, to: target.appendingPathComponent(source.lastPathComponent))
        }
        let manifest = ["purpose": "FocusFix product development", "format": "development-v1",
                        "consent_id": consent.id.uuidString.lowercased(),
                        "policy_version": consent.policyVersion]
        let manifestURL = target.appendingPathComponent("sharing_manifest.json")
        try JSONSerialization.data(withJSONObject: manifest, options: [.sortedKeys])
            .write(to: manifestURL, options: .atomic)
        let zip = stage.appendingPathComponent("recording.zip")
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/zip")
        process.currentDirectoryURL = stage
        process.arguments = ["-q", "-X", zip.path] + (files + ["sharing_manifest.json"]).map { "\(id)/\($0)" }
        process.standardOutput = FileHandle.nullDevice
        process.standardError = FileHandle.nullDevice
        try process.run()
        process.waitUntilExit()
        guard process.terminationStatus == 0,
              let size = try zip.resourceValues(forKeys: [.fileSizeKey]).fileSize,
              size > 0, size <= maximumZIPBytes else { throw RecordingContract.Invalid.contract }
        let data = try Data(contentsOf: zip)
        try data.write(to: destination, options: .atomic)
        try manager.setAttributes([.posixPermissions: 0o600], ofItemAtPath: destination.path)
        return data
    }
}
