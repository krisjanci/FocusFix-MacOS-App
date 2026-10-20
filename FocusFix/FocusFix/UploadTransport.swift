// MARK: - FF: UPLOADS
// Packages approved session files and sends them to the receiver. No Cloudflare administrator credentials belong in the app.

import Foundation
import CryptoKit

// MARK: - FF: UPLOAD_CONFIG
enum UploadConfiguration {
    // FF: RELEASE — public Release builds stay local-only until the study release is reviewed.
    // Debug keeps the explicitly enrolled development test. Never ship a Debug app as a release.
    #if DEBUG
    static let researchUploadsAllowed = true
    static let serviceURL = "https://focusfix-uploads.focusfix-research.workers.dev"
    #else
    static let researchUploadsAllowed = false
    static let serviceURL = ""
    #endif
}

nonisolated struct PreparedUpload: Sendable {
    let file: URL
    let sha256: String
    let bytes: Int
}

nonisolated enum UploadArchive {
    // Build or reuse a bounded ZIP containing only the allowed files, then calculate its SHA-256 fingerprint.
    static func prepare(sessionFolder: URL, destination: URL) throws -> PreparedUpload {
        let manager = FileManager.default
        if !manager.fileExists(atPath: destination.path) {
            let staging = destination.deletingLastPathComponent().appendingPathComponent(UUID().uuidString)
            try manager.createDirectory(at: staging, withIntermediateDirectories: false,
                                        attributes: [.posixPermissions: 0o700])
            defer { try? manager.removeItem(at: staging) }
            var total = 0
            // Explicit allowlist: never package other files, credentials or queue state.
            for name in UploadPolicy.files {
                let source = sessionFolder.appendingPathComponent(name)
                let info = try source.resourceValues(forKeys: [.isRegularFileKey, .isSymbolicLinkKey, .fileSizeKey])
                guard info.isRegularFile == true, info.isSymbolicLink != true else {
                    throw SharingError.message("A session file is missing or unsafe to upload.")
                }
                total += info.fileSize ?? UploadPolicy.maximumRawBytes + 1
                guard total <= UploadPolicy.maximumRawBytes else {
                    throw SharingError.message("Session exceeds the 100 MiB uncompressed limit. Kept locally.")
                }
                try manager.copyItem(at: source, to: staging.appendingPathComponent(name))
            }
            let temporaryZIP = staging.appendingPathComponent("archive.zip")
            // zip receives an explicit list, so no parent directory, resource forks or
            // unrelated files are included. Process arguments are not shell commands.
            let process = Process()
            process.executableURL = URL(fileURLWithPath: "/usr/bin/zip")
            process.currentDirectoryURL = staging
            process.arguments = ["-q", "-X", temporaryZIP.path] + UploadPolicy.files
            process.standardOutput = FileHandle.nullDevice
            process.standardError = FileHandle.nullDevice
            try process.run()
            process.waitUntilExit()
            guard process.terminationStatus == 0 else { throw SharingError.message("Couldn't compress the session.") }
            let size = try temporaryZIP.resourceValues(forKeys: [.fileSizeKey]).fileSize ?? 0
            guard size > 0, size <= UploadPolicy.maximumZIPBytes else {
                throw SharingError.message("Session exceeds the 25 MiB ZIP limit. Kept locally.")
            }
            try manager.moveItem(at: temporaryZIP, to: destination)
            try manager.setAttributes([.posixPermissions: 0o600], ofItemAtPath: destination.path)
        }
        let info = try destination.resourceValues(forKeys: [.isRegularFileKey, .isSymbolicLinkKey, .fileSizeKey])
        guard info.isRegularFile == true, info.isSymbolicLink != true,
              let bytes = info.fileSize, bytes > 0, bytes <= UploadPolicy.maximumZIPBytes else {
            throw SharingError.message("Invalid upload archive. The original session is still local.")
        }
        let data = try Data(contentsOf: destination, options: .mappedIfSafe)
        let hash = SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
        return PreparedUpload(file: destination, sha256: hash, bytes: bytes)
    }
}

// Never forward research recordings or authorization to a redirect destination.
final class NoUploadRedirects: NSObject, URLSessionTaskDelegate, @unchecked Sendable {
    // Refuse redirects so the participant credential and recording cannot be forwarded to a different host.
    func urlSession(_ session: URLSession, task: URLSessionTask,
                    willPerformHTTPRedirection response: HTTPURLResponse,
                    newRequest request: URLRequest,
                    completionHandler: @escaping (URLRequest?) -> Void) {
        completionHandler(nil)
    }
}

enum UploadTransport {
    // Send one ZIP with its credential, timing and checksum, then return the server's reply.
    static func send(_ archive: PreparedUpload, item: UploadItem, endpoint: URL,
                     token: String) async throws -> (Data, HTTPURLResponse) {
        let config = URLSessionConfiguration.ephemeral
        config.timeoutIntervalForRequest = 60
        config.timeoutIntervalForResource = 180
        config.httpShouldSetCookies = false
        let session = URLSession(configuration: config, delegate: NoUploadRedirects(), delegateQueue: nil)
        defer { session.invalidateAndCancel() }
        var request = URLRequest(url: endpoint.appendingPathComponent("v1/sessions/\(item.id)"))
        request.httpMethod = "PUT"
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        request.setValue(item.participantID, forHTTPHeaderField: "X-Participant-ID")
        request.setValue(String(item.durationSeconds), forHTTPHeaderField: "X-Duration-Seconds")
        request.setValue(archive.sha256, forHTTPHeaderField: "X-Content-SHA256")
        request.setValue("application/zip", forHTTPHeaderField: "Content-Type")
        request.setValue(String(archive.bytes), forHTTPHeaderField: "Content-Length")
        let (data, response) = try await session.upload(for: request, fromFile: archive.file)
        guard let response = response as? HTTPURLResponse else {
            throw SharingError.message("No upload confirmation was received.")
        }
        return (data, response)
    }
}
