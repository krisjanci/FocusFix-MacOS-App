import Foundation

@main struct ResearchArchiveContractTests {
    static func rejects(_ operation: () throws -> Void) {
        do { try operation(); preconditionFailure("Unsafe research archive accepted") } catch { }
    }
    static func main() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let scope = ResearchArchiveScope(version: "synthetic-scope-v2", archiveVersion: 2,
            automaticActivity: true, nonWorkActivity: true, contextAndRevisions: true, optionalStudyChecks: true,
            determinationReference: "SYNTHETIC ONLY", reviewedConsentText: "Synthetic test only, not real consent",
            retentionTerms: "Disposable generated fixtures", downloadedDataDeletionTerms: "Delete synthetic fixture tree",
            modelTrainingTerms: "Synthetic model tests only", futureTrainingAllowed: false)
        let identity = ResearchCaptureIdentity(owner: UUID(), origin: "https://synthetic.invalid", consentID: UUID(),
            studyVersion: "synthetic-study-v2", consentStartedAtUTC: Date(timeIntervalSince1970: 90), scope: scope)
        let writer = try RecordingWriter(root: root, id: UUID().uuidString, startedAt: Date(timeIntervalSince1970: 100),
            mode: .automatic, researchIdentity: identity)
        try writer.event(time: 1, type: "left_click_down")
        try writer.finish(startedAt: Date(timeIntervalSince1970: 100), duration: 30, reason: "fixture")
        let metadataURL = writer.folder.appendingPathComponent("session.json")
        var metadata = try JSONSerialization.jsonObject(with: Data(contentsOf: metadataURL)) as! [String: Any]
        metadata["synthetic_fixture"] = true
        try JSONSerialization.data(withJSONObject: metadata).write(to: metadataURL)
        let sources = try ResearchArchiveContract.validate(folder: writer.folder, current: identity, dailyUsedSeconds: 0)
        precondition(sources.map(\.lastPathComponent) == ResearchArchiveContract.files)
        precondition(!ResearchArchiveContract.eligibleForDelivery(folder: writer.folder, current: identity, dailyUsedSeconds: 0))
        let legacy = ResearchCaptureIdentity(owner: identity.owner, origin: identity.origin, consentID: identity.consentID,
            studyVersion: identity.studyVersion, consentStartedAtUTC: identity.consentStartedAtUTC, scope: nil)
        rejects { _ = try ResearchArchiveContract.validate(folder: writer.folder, current: legacy, dailyUsedSeconds: 0) }
        rejects { _ = try ResearchArchiveContract.validate(folder: writer.folder, current: nil, dailyUsedSeconds: 0) }
        let switched = ResearchCaptureIdentity(owner: UUID(), origin: identity.origin, consentID: identity.consentID,
            studyVersion: identity.studyVersion, consentStartedAtUTC: identity.consentStartedAtUTC, scope: scope)
        rejects { _ = try ResearchArchiveContract.validate(folder: writer.folder, current: switched, dailyUsedSeconds: 0) }
        let lateConsent = ResearchCaptureIdentity(owner: identity.owner, origin: identity.origin, consentID: identity.consentID,
            studyVersion: identity.studyVersion, consentStartedAtUTC: Date(timeIntervalSince1970: 101), scope: scope)
        rejects { _ = try ResearchArchiveContract.validate(folder: writer.folder, current: lateConsent, dailyUsedSeconds: 0) }
        rejects { _ = try ResearchArchiveContract.validate(folder: writer.folder, current: identity, dailyUsedSeconds: 10780) }
        try Data("never archive credentials".utf8).write(to: writer.folder.appendingPathComponent("credentials.json"))
        let destination = root.appendingPathComponent("synthetic.zip")
        let zip = try ResearchArchiveContract.prepareSynthetic(folder: writer.folder, current: identity, dailyUsedSeconds: 0, destination: destination)
        precondition(!zip.isEmpty)
        let pipe = Pipe(), process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/unzip")
        process.arguments = ["-Z1", destination.path]; process.standardOutput = pipe
        try process.run(); let names = String(decoding: pipe.fileHandleForReading.readDataToEndOfFile(), as: UTF8.self)
        process.waitUntilExit()
        precondition(process.terminationStatus == 0 && names.contains("context_intervals.json") && names.contains("archive_manifest.json"))
        precondition(!names.contains("credentials") && !names.contains("research_eligibility") && !names.contains("../"))
        let retry = try ResearchArchiveContract.prepareSynthetic(folder: writer.folder, current: identity, dailyUsedSeconds: 0, destination: root.appendingPathComponent("retry.zip"))
        precondition(retry.count > 0)
        let eventURL = writer.folder.appendingPathComponent("events.csv")
        try FileManager.default.removeItem(at: eventURL)
        try FileManager.default.createSymbolicLink(at: eventURL, withDestinationURL: metadataURL)
        rejects { _ = try ResearchArchiveContract.validate(folder: writer.folder, current: identity, dailyUsedSeconds: 0) }
        print("PASS: versioned synthetic archive, old scope/new schema rejection, consent/account/withdrawal boundaries, no backfill, daily cap, ZIP allowlist, retries, path safety and disabled real eligibility")
    }
}
