import Foundation

@main struct UploadPolicyTests {
    static func main() throws {
        precondition(UploadPolicy.seconds(0) == nil)
        precondition(UploadPolicy.seconds(.nan) == nil)
        precondition(UploadPolicy.seconds(.infinity) == nil)
        precondition(UploadPolicy.seconds(-1) == nil)
        precondition(UploadPolicy.seconds(0.1) == 1)
        precondition(UploadPolicy.seconds(10800) == 10800)
        precondition(UploadPolicy.seconds(10800.1) == nil)
        precondition(UploadPolicy.endpoint("https://example.workers.dev") != nil)
        for value in ["", "http://example.com", "https://user:secret@example.com", "https://example.com/path", "https://example.com?token=x"] {
            precondition(UploadPolicy.endpoint(value) == nil)
        }
        let id = UUID().uuidString
        var metadata: [String: Any] = ["participant_id": "person-a", "sharing_consent_id": "consent-a",
            "session_id": id, "status": "user_stop", "duration_seconds": 3600.0]
        precondition(UploadPolicy.eligible(metadata: metadata, participant: "person-a", consent: "consent-a"))
        precondition(!UploadPolicy.eligible(metadata: metadata, participant: "person-a", consent: nil))
        precondition(!UploadPolicy.eligible(metadata: metadata, participant: "person-a", consent: "new-consent"))
        precondition(!UploadPolicy.eligible(metadata: metadata, participant: "person-b", consent: "consent-a"))
        metadata.removeValue(forKey: "sharing_consent_id")
        precondition(!UploadPolicy.eligible(metadata: metadata, participant: "person-a", consent: "consent-a"))
        metadata["sharing_consent_id"] = "consent-a"
        metadata["status"] = "recording"
        precondition(!UploadPolicy.eligible(metadata: metadata, participant: "person-a", consent: "consent-a"))
        metadata["status"] = "recording_error"
        precondition(!UploadPolicy.eligible(metadata: metadata, participant: "person-a", consent: "consent-a"))

        // Temporary synthetic recordings only; never touches Keychain or the network.
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("focusfix-upload-tests-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: false)
        defer { try? FileManager.default.removeItem(at: root) }
        let source = root.appendingPathComponent("session")
        try FileManager.default.createDirectory(at: source, withIntermediateDirectories: false)
        for file in UploadPolicy.files { try Data("synthetic,only\n1,2\n".utf8).write(to: source.appendingPathComponent(file)) }
        try Data("not for upload".utf8).write(to: source.appendingPathComponent("private.txt"))
        let destination = root.appendingPathComponent("session.zip")
        let archive = try UploadArchive.prepare(sessionFolder: source, destination: destination)
        precondition(archive.bytes > 0 && archive.sha256.count == 64)
        let again = try UploadArchive.prepare(sessionFolder: source, destination: destination)
        precondition(archive.sha256 == again.sha256) // A retry sends identical bytes.
        let process = Process()
        let pipe = Pipe()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/unzip")
        process.arguments = ["-Z1", destination.path]
        process.standardOutput = pipe
        try process.run()
        let output = String(data: pipe.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8)!
        process.waitUntilExit()
        precondition(Set(output.split(separator: "\n").map(String.init)) == Set(UploadPolicy.files))
        let unsafe = source.appendingPathComponent("events.csv")
        try FileManager.default.removeItem(at: unsafe)
        try FileManager.default.createSymbolicLink(at: unsafe, withDestinationURL: source.appendingPathComponent("private.txt"))
        do {
            _ = try UploadArchive.prepare(sessionFolder: source, destination: root.appendingPathComponent("unsafe.zip"))
            preconditionFailure("Symlinks must not be packaged")
        } catch { }
        let item = UploadItem(id: id, participantID: "person-a", consentID: "consent-a", durationSeconds: 3600)
        let restored = try JSONDecoder().decode(UploadItem.self, from: JSONEncoder().encode(item))
        precondition(restored.id == id && restored.state == "waiting" && restored.uploadedAt == nil)
        print("Upload policy and archive tests passed")
    }
}
