import Foundation

@main @MainActor
struct SessionTagsTests {
    static func checkTags(_ folder: URL, _ expected: [String]) throws {
        let session = try SavedSession(folder: folder)
        precondition(session.tags == expected)
    }
    static func fails(_ action: () throws -> Void) {
        do { try action(); preconditionFailure("Expected validation or storage failure") } catch { }
    }

    static func main() throws {
        let manager = FileManager.default
        let root = manager.temporaryDirectory.appendingPathComponent("tags-test-\(UUID())")
        try manager.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? manager.removeItem(at: root) }
        let file = root.appendingPathComponent("preferences/tags.json")
        let library = SessionTagLibrary(file: file)
        precondition(library.loaded && library.names == SessionTags.defaults)
        precondition(SessionTags.defaults.contains("Repetitive work") && SessionTags.defaults.contains("Creative work"))
        precondition(SessionTags.defaults.count == 3 && SessionTags.defaults.contains("Focused work"))
        let custom = try library.add("  Data analysis  ", color: "#123abc")
        precondition(custom == "Data analysis")
        precondition(library.color(for: custom) == "#123ABC")
        let duplicate = try library.add("data ANALYSIS")
        precondition(duplicate == custom && library.names.count == SessionTags.defaults.count + 1)
        let reopened = SessionTagLibrary(file: file)
        precondition(reopened.names == library.names)
        precondition(reopened.color(for: custom) == "#123ABC")
        try reopened.rename(custom, to: "Writing & review")
        precondition(SessionTagLibrary(file: file).names.last == "Writing & review")
        precondition(SessionTagLibrary(file: file).color(for: "Writing & review") == "#123ABC")
        try reopened.rename("Writing & review", to: "Writing & review", color: "#C64B66")
        precondition(SessionTagLibrary(file: file).color(for: "Writing & review") == "#C64B66")
        fails { try reopened.rename("Writing & review", to: "Writing & review", color: "red") }
        fails { try reopened.rename("Writing & review", to: "Focused work") }
        for invalid in ["", "   ", "two\nlines", String(repeating: "x", count: 41)] {
            fails { try reopened.add(invalid) }
        }
        try reopened.remove("Repetitive work")
        precondition(!SessionTagLibrary(file: file).names.contains("Repetitive work"))
        // Upgrade the old unmodified starter list, keeping custom labels and session snapshots.
        let legacyCatalog = root.appendingPathComponent("legacy-tags.json")
        try JSONEncoder().encode(SessionTags.legacyDefaults + ["My old custom tag"]).write(to: legacyCatalog)
        let migrated = SessionTagLibrary(file: legacyCatalog)
        precondition(migrated.names == SessionTags.defaults + ["My old custom tag"])
        _ = try migrated.add("New colored tag", color: "#367CC5")
        precondition(SessionTagLibrary(file: legacyCatalog).color(for: "New colored tag") == "#367CC5")
        let customCatalog = root.appendingPathComponent("customized-list.json")
        try JSONEncoder().encode(["Learning", "My chosen default"]).write(to: customCatalog)
        precondition(SessionTagLibrary(file: customCatalog).names == ["Learning", "My chosen default"])
        fails { _ = try SessionTags.color("#GGGGGG") }
        fails { _ = try SessionTags.color("#123") }
        let normalized = try SessionTags.validated([" Focused work ", "focused WORK", "Research, \"notes\" 🧠"])
        precondition(normalized == ["Focused work", "Research, \"notes\" 🧠"])
        fails { _ = try SessionTags.validated((0...20).map { "Tag \($0)" }) }

        // Failed persistence must not replace the remembered list in memory.
        let blocked = root.appendingPathComponent("blocked")
        let blockedLibrary = SessionTagLibrary(file: blocked.appendingPathComponent("tags.json"))
        try Data("not a directory".utf8).write(to: blocked)
        fails { try blockedLibrary.add("Cannot persist") }
        precondition(blockedLibrary.names == SessionTags.defaults)
        let brokenFile = root.appendingPathComponent("broken.json")
        let corrupt = Data("unreadable saved catalog".utf8)
        try corrupt.write(to: brokenFile)
        let broken = SessionTagLibrary(file: brokenFile)
        precondition(!broken.loaded && broken.notice != nil)
        fails { try broken.add("Do not overwrite") }
        let preserved = try Data(contentsOf: brokenFile)
        precondition(preserved == corrupt)

        let storage = root.appendingPathComponent("Sessions")
        let folder = storage.appendingPathComponent(UUID().uuidString)
        try manager.createDirectory(at: folder, withIntermediateDirectories: true)
        let metadataURL = folder.appendingPathComponent("session.json")
        let csv = Data("elapsed_seconds,event_type\n0,key_down\n".utf8)
        try csv.write(to: folder.appendingPathComponent("events.csv"))
        let original: [String: Any] = ["session_id": folder.lastPathComponent,
            "started_at_utc": "2026-10-31T12:00:00Z", "duration_seconds": 60,
            "status": "user_stop", "schema_version": 8, "participant_id": "historical-id",
            "unknown_future_field": ["keep": true]]
        try JSONSerialization.data(withJSONObject: original).write(to: metadataURL)
        let untagged = try SavedSession(folder: folder)
        precondition(untagged.tags.isEmpty)
        let selectedColors = [normalized[0]: "#168B80", normalized[1]: "#C64B66"]
        try SessionFiles.updateTags(normalized, colors: selectedColors, for: untagged, root: storage, active: nil)
        let edited = try SavedSession(folder: folder)
        precondition(edited.tags == normalized)
        precondition(edited.tagColors == selectedColors)
        let metadata = try JSONSerialization.jsonObject(with: Data(contentsOf: metadataURL)) as! [String: Any]
        precondition(metadata["participant_id"] as? String == "historical-id")
        precondition(metadata["duration_seconds"] as? Int == 60 && metadata["schema_version"] as? Int == 8)
        precondition((metadata["unknown_future_field"] as? [String: Bool])?["keep"] == true)
        let untouched = try Data(contentsOf: folder.appendingPathComponent("events.csv"))
        precondition(untouched == csv)
        fails { try SessionFiles.updateTags(["New"], for: edited, root: storage, active: folder) }
        fails { try SessionFiles.updateTags([""], for: edited, root: storage, active: nil) }

        let exports = root.appendingPathComponent("Exports")
        try manager.createDirectory(at: exports, withIntermediateDirectories: false)
        let single = try SessionFiles.export(edited, to: exports, root: storage, active: nil)
        try checkTags(single, normalized)
        let singleSession = try SavedSession(folder: single)
        precondition(singleSession.tagColors == selectedColors)
        let batch = try SessionFiles.exportAll(to: exports, root: storage, active: nil)
        let batchCopy = batch.folder.appendingPathComponent(edited.exportName())
        try checkTags(batchCopy, normalized)
        let batchSession = try SavedSession(folder: batchCopy)
        precondition(batchSession.tagColors == selectedColors)
        // Catalog edits never silently rewrite the historical labels of a session.
        try reopened.rename("Writing & review", to: "Deep writing")
        try checkTags(folder, normalized)
        try SessionFiles.updateTags(["Deep writing"], for: edited, root: storage, active: nil)
        try checkTags(folder, ["Deep writing"])
        try SessionFiles.updateTags([], for: edited, root: storage, active: nil)
        try checkTags(folder, [])

        // Missing legacy metadata can be labeled; corrupt metadata must be preserved.
        let legacyFolder = storage.appendingPathComponent("unfinished")
        try manager.createDirectory(at: legacyFolder, withIntermediateDirectories: false)
        let legacy = try SavedSession(folder: legacyFolder)
        try SessionFiles.updateTags(["Learning"], for: legacy, root: storage, active: nil)
        try checkTags(legacyFolder, ["Learning"])
        try corrupt.write(to: metadataURL)
        fails { try SessionFiles.updateTags(["Learning"], for: edited, root: storage, active: nil) }
        let corruptMetadata = try Data(contentsOf: metadataURL)
        precondition(corruptMetadata == corrupt)
        try manager.removeItem(at: metadataURL)
        try manager.createSymbolicLink(at: metadataURL, withDestinationURL: single.appendingPathComponent("session.json"))
        fails { try SessionFiles.updateTags(["Learning"], for: edited, root: storage, active: nil) }
        print("Session tags: defaults, validation, remembered custom/renamed/deleted labels, failure preservation, legacy edits, unchanged data, and single/batch exports passed")
    }
}
