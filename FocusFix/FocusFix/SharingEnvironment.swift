// MARK: - FF: SHARING
// Supplies real identity, storage and networking services; tests replace these with safe fakes.

import Foundation

// Injectable boundaries let queue tests use temporary files and fake networking,
// without reading a real Keychain identity or participant recordings.
@MainActor struct SharingEnvironment {
    var researchUploadsAllowed = true
    var serviceURL: String
    var identity: () throws -> String
    var readCredential: () throws -> String?
    var saveCredential: (String) throws -> Void
    var sharingRoot: () throws -> URL
    var sessionRoot: () throws -> URL
    var prepare: (URL, URL) async throws -> PreparedUpload
    var send: (PreparedUpload, UploadItem, URL, String) async throws -> (Data, HTTPURLResponse)

    // Wire up Keychain, local folders, background ZIP preparation and the real HTTPS sender.
    static var live: SharingEnvironment {
        // The retired legacy path is never enabled by the live app. Existing development state is left untouched.
        return SharingEnvironment(researchUploadsAllowed: false,
            serviceURL: "",
            identity: { try SharingIdentity.participantID() },
            readCredential: { try SharingIdentity.read("upload-credential") },
            saveCredential: { try SharingIdentity.save($0, account: "upload-credential") },
            sharingRoot: {
                try FileManager.default.url(for: .applicationSupportDirectory,
                    in: .userDomainMask, appropriateFor: nil, create: true)
                    .appendingPathComponent("FocusFix/Sharing", isDirectory: true)
            }, sessionRoot: { try SessionFiles.root() },
            prepare: { source, destination in
                try await Task.detached(priority: .utility) {
                    try UploadArchive.prepare(sessionFolder: source, destination: destination)
                }.value
            }, send: { archive, item, endpoint, token in
                try await UploadTransport.send(archive, item: item, endpoint: endpoint, token: token)
            })
    }
}
