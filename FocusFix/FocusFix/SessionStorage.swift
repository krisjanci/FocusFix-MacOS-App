import Foundation
import CryptoKit

// Storage is independent of the recording schema and of hosted archive formats.
// A marker is the commit point: until it exists, the original files are authoritative.
nonisolated enum SessionStorage {
    static let marker = "storage.json"
    static let pendingMarker = ".compact-on-save"
    private static let lock = NSRecursiveLock()
    private static let manager = FileManager.default
    private static let inlineNames: Set<String> = ["session.json", "context_intervals.json", "research_eligibility.json"]
    struct Entry: Codable {
        let size: Int
        let sha256: String
        let inline: Data?
    }
    struct Manifest: Codable {
        let version: Int
        let archive: String
        let entries: [String: Entry]
    }
    static func synchronized<T>(_ body: () throws -> T) rethrows -> T {
        lock.lock(); defer { lock.unlock() }
        return try body()
    }
    private static func safeName(_ name: String) -> Bool {
        !name.isEmpty && !name.hasPrefix(".") && !name.hasPrefix("-") &&
        !name.contains("/") && !name.contains("\\") && !name.contains("\n") && !name.contains("\r") &&
        !name.contains("*") && !name.contains("?") && !name.contains("[")
    }
    private static func regular(_ url: URL, limit: Int) throws -> Int {
        let info = try url.resourceValues(forKeys: [.isRegularFileKey, .isSymbolicLinkKey, .fileSizeKey])
        guard info.isRegularFile == true, info.isSymbolicLink != true,
              let size = info.fileSize, size >= 0, size <= limit else { throw CocoaError(.fileReadCorruptFile) }
        return size
    }
    private static func digest(_ data: Data) -> String {
        SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
    }
    private static func manifest(_ folder: URL) throws -> Manifest? {
        let url = folder.appendingPathComponent(marker)
        guard manager.fileExists(atPath: url.path) else { return nil }
        _ = try regular(url, limit: 48 * 1024 * 1024)
        let value = try JSONDecoder().decode(Manifest.self, from: Data(contentsOf: url))
        guard value.version == 1, value.archive.hasPrefix("recording-"), value.archive.hasSuffix(".zip"),
              safeName(value.archive), !value.entries.isEmpty, value.entries.count <= 128,
              value.entries.keys.allSatisfy({ safeName($0) && $0 != marker && !$0.hasPrefix("recording-") }),
              value.entries.values.allSatisfy({ $0.size >= 0 && $0.size <= 512 * 1024 * 1024 }) else {
            throw CocoaError(.fileReadCorruptFile)
        }
        _ = try regular(folder.appendingPathComponent(value.archive), limit: 1024 * 1024 * 1024)
        return value
    }
    static func isArchived(_ folder: URL) -> Bool { manager.fileExists(atPath: folder.appendingPathComponent(marker).path) }
    static func names(in folder: URL) throws -> [String] {
        try synchronized {
            if let value = try manifest(folder) { return value.entries.keys.sorted() }
            return try manager.contentsOfDirectory(atPath: folder.path).filter { !$0.hasPrefix(".") }.sorted()
        }
    }
    static func contains(_ name: String, in folder: URL) throws -> Bool {
        try synchronized {
            if let value = try manifest(folder) { return value.entries[name] != nil }
            return manager.fileExists(atPath: folder.appendingPathComponent(name).path)
        }
    }
    // Decompress only named entries; never extract archive paths, links, or directories.
    private static func extract(_ name: String, manifest value: Manifest, folder: URL, to output: URL) throws {
        guard let entry = value.entries[name], safeName(name) else { throw CocoaError(.fileNoSuchFile) }
        guard manager.createFile(atPath: output.path, contents: nil, attributes: [.posixPermissions: 0o600]) else {
            throw CocoaError(.fileWriteUnknown)
        }
        let file = try FileHandle(forWritingTo: output)
        defer { try? file.close() }
        if let data = entry.inline {
            guard data.count == entry.size, digest(data) == entry.sha256 else { throw CocoaError(.fileReadCorruptFile) }
            try file.write(contentsOf: data)
            return
        }
        let process = Process(), pipe = Pipe()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/unzip")
        process.arguments = ["-p", folder.appendingPathComponent(value.archive).path, name]
        process.standardOutput = pipe; process.standardError = FileHandle.nullDevice
        try process.run()
        var hash = SHA256(), count = 0
        do {
            while let chunk = try pipe.fileHandleForReading.read(upToCount: 64 * 1024), !chunk.isEmpty {
                try Task.checkCancellation()
                count += chunk.count
                guard count <= entry.size else { throw CocoaError(.fileReadCorruptFile) }
                hash.update(data: chunk); try file.write(contentsOf: chunk)
            }
        } catch {
            process.terminate(); try? pipe.fileHandleForReading.close(); process.waitUntilExit(); throw error
        }
        process.waitUntilExit()
        guard process.terminationStatus == 0, count == entry.size,
              hash.finalize().map({ String(format: "%02x", $0) }).joined() == entry.sha256 else {
            throw CocoaError(.fileReadCorruptFile)
        }
    }
    static func data(_ name: String, in folder: URL, limit: Int = 16 * 1024 * 1024) throws -> Data {
        try synchronized {
            if let value = try manifest(folder) {
                guard let entry = value.entries[name], entry.size <= limit else { throw CocoaError(.fileReadCorruptFile) }
                if let data = entry.inline {
                    guard data.count == entry.size, digest(data) == entry.sha256 else { throw CocoaError(.fileReadCorruptFile) }
                    return data
                }
                return try withFile(name, in: folder) { try Data(contentsOf: $0) }
            }
            let url = folder.appendingPathComponent(name)
            _ = try regular(url, limit: limit)
            return try Data(contentsOf: url)
        }
    }
    static func withFile<T>(_ name: String, in folder: URL, _ body: (URL) throws -> T) throws -> T {
        try synchronized {
            guard safeName(name) else { throw CocoaError(.fileReadCorruptFile) }
            guard let value = try manifest(folder) else {
                let file = folder.appendingPathComponent(name)
                _ = try regular(file, limit: 512 * 1024 * 1024)
                return try body(file)
            }
            let stage = try temporaryFolder()
            defer { try? manager.removeItem(at: stage) }
            let file = stage.appendingPathComponent(name)
            try extract(name, manifest: value, folder: folder, to: file)
            return try body(file)
        }
    }
    static func withFolder<T>(_ folder: URL, _ body: (URL) throws -> T) throws -> T {
        try synchronized {
            guard let value = try manifest(folder) else { return try body(folder) }
            let stage = try temporaryFolder()
            defer { try? manager.removeItem(at: stage) }
            let copy = stage.appendingPathComponent(folder.lastPathComponent)
            try manager.createDirectory(at: copy, withIntermediateDirectories: false, attributes: [.posixPermissions: 0o700])
            for name in value.entries.keys.sorted() {
                try extract(name, manifest: value, folder: folder, to: copy.appendingPathComponent(name))
            }
            return try body(copy)
        }
    }
    private static func temporaryFolder() throws -> URL {
        let stage = manager.temporaryDirectory.appendingPathComponent("FocusFix-storage-\(UUID().uuidString)")
        try manager.createDirectory(at: stage, withIntermediateDirectories: false, attributes: [.posixPermissions: 0o700])
        return stage
    }
    // Called only for sessions made by this writer, never as a migration of old recordings.
    @discardableResult static func compact(_ folder: URL, force: Bool = false) throws -> Bool {
        try synchronized {
            guard !isArchived(folder) else { return true }
            let metadata = try JSONSerialization.jsonObject(with: data("session.json", in: folder)) as? [String: Any]
            guard metadata?["status"] as? String != "recording", try RecordingContract.load(from: folder).finalized else { return false }
            let names = try self.names(in: folder)
            guard names.count <= 128, names.allSatisfy(safeName) else { throw CocoaError(.fileReadCorruptFile) }
            var entries: [String: Entry] = [:], rawSize = 0
            for name in names {
                let url = folder.appendingPathComponent(name)
                let size = try regular(url, limit: 512 * 1024 * 1024)
                let file = try FileHandle(forReadingFrom: url)
                defer { try? file.close() }
                var hash = SHA256()
                while let chunk = try file.read(upToCount: 64 * 1024), !chunk.isEmpty { try Task.checkCancellation(); hash.update(data: chunk) }
                let inline = inlineNames.contains(name) ? try Data(contentsOf: url) : nil
                entries[name] = Entry(size: size, sha256: hash.finalize().map { String(format: "%02x", $0) }.joined(), inline: inline)
                rawSize += size
            }
            let archiveName = "recording-\(UUID().uuidString).zip"
            let archive = folder.appendingPathComponent(archiveName)
            var committed = false
            defer { if !committed { try? manager.removeItem(at: archive) } }
            let process = Process(); process.executableURL = URL(fileURLWithPath: "/usr/bin/zip")
            process.currentDirectoryURL = folder
            process.arguments = ["-q", "-6", "-X", archive.path] + names
            process.standardOutput = FileHandle.nullDevice; process.standardError = FileHandle.nullDevice
            try process.run(); process.waitUntilExit()
            guard process.terminationStatus == 0 else { throw CocoaError(.fileWriteUnknown) }
            try manager.setAttributes([.posixPermissions: 0o600], ofItemAtPath: archive.path)
            let value = Manifest(version: 1, archive: archiveName, entries: entries)
            let encoded = try JSONEncoder().encode(value)
            let zipSize = try regular(archive, limit: 1024 * 1024 * 1024)
            guard force || zipSize + encoded.count < rawSize else { return false }
            // Verify the actual ZIP bytes, including entries also cached inline for listings.
            let verification = Manifest(version: 1, archive: archiveName, entries: entries.mapValues { Entry(size: $0.size, sha256: $0.sha256, inline: nil) })
            let stage = try temporaryFolder(); defer { try? manager.removeItem(at: stage) }
            for name in names { try extract(name, manifest: verification, folder: folder, to: stage.appendingPathComponent(name)) }
            let handle = try FileHandle(forWritingTo: archive); try handle.synchronize(); try handle.close()
            try encoded.write(to: folder.appendingPathComponent(marker), options: .atomic)
            committed = true
            // A crash during cleanup leaves duplicate bytes, never an incomplete recording.
            for name in names { try? manager.removeItem(at: folder.appendingPathComponent(name)) }
            try? manager.removeItem(at: folder.appendingPathComponent(pendingMarker))
            return true
        }
    }
    static func edit(_ folder: URL, _ body: (URL) throws -> Void) throws {
        try synchronized {
            guard let old = try manifest(folder) else { try body(folder); return }
            try withFolder(folder) { stage in
                try body(stage)
                _ = try compact(stage, force: true)
                let updated = try manifest(stage)!
                let archive = folder.appendingPathComponent(updated.archive)
                try manager.copyItem(at: stage.appendingPathComponent(updated.archive), to: archive)
                do { try Data(contentsOf: stage.appendingPathComponent(marker)).write(to: folder.appendingPathComponent(marker), options: .atomic) }
                catch { try? manager.removeItem(at: archive); throw error }
                try? manager.removeItem(at: folder.appendingPathComponent(old.archive))
            }
        }
    }
    static func compactNewSession(_ folder: URL) {
        guard manager.fileExists(atPath: folder.appendingPathComponent(pendingMarker).path) else { return }
        Task.detached(priority: .utility) {
            do { _ = try compact(folder) }
            catch { NSLog("Session kept uncompressed: %@", error.localizedDescription) }
        }
    }
}
