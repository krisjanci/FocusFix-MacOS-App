import Foundation

@main @MainActor
struct SessionConditionsTests {
    static func fails(_ action: () throws -> Void) {
        do { try action(); preconditionFailure("Expected validation or storage failure") } catch { }
    }
    static func main() throws {
        let fm = FileManager.default
        let root = fm.temporaryDirectory.appendingPathComponent("conditions-test-\(UUID())")
        try fm.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? fm.removeItem(at: root) }
        let file = root.appendingPathComponent("catalog/conditions.json")
        let library = SessionConditionLibrary(file: file)
        precondition(library.loaded && library.categories.map(\.name) == ["Location", "Music", "Work setting"])
        let location = library.categories[0], label = library.categories[0].labels[0]
        let music = library.categories[1]
        let snapshot = SessionCondition(categoryID: location.id, labelID: label.id, category: location.name, label: label.name)
        let second = SessionCondition(categoryID: music.id, labelID: music.labels[0].id, category: music.name, label: music.labels[0].name)
        precondition(SessionConditionLibrary(file: file).categories == library.categories)
        fails { _ = try SessionConditions.validated([snapshot, snapshot]) }
        let otherLabel = SessionCondition(categoryID: location.id, labelID: UUID(), category: location.name, label: "Elsewhere")
        fails { _ = try SessionConditions.validated([snapshot, otherLabel]) }
        let selected = try SessionConditions.validated([snapshot, second])
        precondition(selected.count == 2)
        for invalid in ["", "  ", "a\nb", String(repeating: "x", count: 41)] {
            fails { try library.saveCategory(id: nil, name: invalid) }
            fails { try library.saveLabel(categoryID: location.id, id: nil, name: invalid) }
        }
        fails { try library.saveCategory(id: nil, name: "location") }
        fails { try library.saveLabel(categoryID: location.id, id: nil, name: "HOME") }
        // The same label name is allowed in different categories.
        try library.saveCategory(id: nil, name: "Lighting")
        let custom = library.categories.last!
        try library.saveLabel(categoryID: custom.id, id: nil, name: "Home")
        try library.saveLabel(categoryID: custom.id, id: library.categories.last!.labels[0].id, name: "Natural light")
        precondition(SessionConditionLibrary(file: file).categories.last!.labels[0].name == "Natural light")

        let storage = root.appendingPathComponent("recordings")
        let started = Date()
        let writer = try RecordingWriter(root: storage, id: UUID().uuidString, startedAt: started,
                                         tags: ["Focused work"], conditions: selected)
        let assertion1 = try SavedSession(folder: writer.folder).conditions == selected
        precondition(assertion1)
        try writer.updateTags(["Creative work"], colors: [:])
        let assertion2 = try SavedSession(folder: writer.folder).conditions == selected
        precondition(assertion2)
        try writer.updateConditions([snapshot])
        let assertion3 = try SavedSession(folder: writer.folder).tags == ["Creative work"]
        precondition(assertion3)
        fails { try writer.updateConditions([snapshot, otherLabel]) }
        // Metadata write failure rolls back in-memory conditions too.
        let metadataURL = writer.folder.appendingPathComponent("session.json")
        let previous = try Data(contentsOf: metadataURL)
        try fm.removeItem(at: metadataURL)
        try fm.createDirectory(at: metadataURL, withIntermediateDirectories: false)
        fails { try writer.updateConditions([second]) }
        try fm.removeItem(at: metadataURL)
        try previous.write(to: metadataURL)
        try writer.updateTags(["Creative work"], colors: [:])
        let assertion4 = try SavedSession(folder: writer.folder).conditions == [snapshot]
        precondition(assertion4)
        try writer.finish(startedAt: started, duration: 60, reason: "user_stop")
        let saved = try SavedSession(folder: writer.folder)
        precondition(saved.conditions == [snapshot] && saved.duration == 60)
        // Renaming and removing catalog entries never modifies historical snapshots.
        try library.saveCategory(id: location.id, name: "Place")
        try library.saveLabel(categoryID: location.id, id: label.id, name: "Apartment")
        precondition(library.categories[0].id == location.id && library.categories[0].labels[0].id == label.id)
        try library.removeLabel(label.id, categoryID: location.id)
        try library.removeCategory(location.id)
        let assertion5 = try SavedSession(folder: writer.folder).conditions == [snapshot]
        precondition(assertion5)
        fails { try SessionFiles.updateConditions([], for: saved, root: storage, active: writer.folder) }
        try SessionFiles.updateConditions(selected, for: saved, root: storage, active: nil)
        let edited = try SavedSession(folder: writer.folder)
        precondition(edited.conditions == selected && edited.tags == saved.tags && edited.duration == saved.duration)
        let exports = root.appendingPathComponent("exports")
        try fm.createDirectory(at: exports, withIntermediateDirectories: false)
        let exported = try SessionFiles.exportOriginal(edited, to: exports, root: storage, active: nil)
        let assertion6 = try SavedSession(folder: exported).conditions == selected
        precondition(assertion6)
        let batch = try SessionFiles.exportAllOriginal(to: exports, root: storage, active: nil)
        let assertion7 = try SavedSession(folder: batch.folder.appendingPathComponent(edited.exportName())).conditions == selected
        precondition(assertion7)
        // Rotation explicitly supplies the old selection; new recordings default empty.
        let continuation = try RecordingWriter(root: storage, id: UUID().uuidString, startedAt: started, conditions: selected)
        let assertion8 = try SavedSession(folder: continuation.folder).conditions == selected
        precondition(assertion8)
        let fresh = try RecordingWriter(root: storage, id: UUID().uuidString, startedAt: started)
        let assertion9 = try SavedSession(folder: fresh.folder).conditions.isEmpty
        precondition(assertion9)

        let legacyFolder = storage.appendingPathComponent("legacy")
        try fm.createDirectory(at: legacyFolder, withIntermediateDirectories: false)
        let legacy = try SavedSession(folder: legacyFolder)
        precondition(legacy.conditions.isEmpty)
        try SessionFiles.updateConditions([snapshot], for: legacy, root: storage, active: nil)
        let assertion10 = try SavedSession(folder: legacyFolder).conditions == [snapshot]
        precondition(assertion10)
        let legacyURL = legacyFolder.appendingPathComponent("session.json")
        var metadata = try JSONSerialization.jsonObject(with: Data(contentsOf: legacyURL)) as! [String: Any]
        metadata["future_field"] = ["keep": true]
        metadata["tags"] = ["Old tag"]
        try JSONSerialization.data(withJSONObject: metadata).write(to: legacyURL)
        try SessionFiles.updateConditions([], for: legacy, root: storage, active: nil)
        let preserved = try JSONSerialization.jsonObject(with: Data(contentsOf: legacyURL)) as! [String: Any]
        precondition((preserved["future_field"] as? [String: Bool])?["keep"] == true)
        let assertion11 = try SavedSession(folder: legacyFolder).tags == ["Old tag"]
        precondition(assertion11)
        let corrupt = Data("broken".utf8)
        try corrupt.write(to: legacyURL)
        fails { try SessionFiles.updateConditions([], for: legacy, root: storage, active: nil) }
        let assertion12 = try Data(contentsOf: legacyURL) == corrupt
        precondition(assertion12)
        try fm.removeItem(at: legacyURL)
        try fm.createSymbolicLink(at: legacyURL, withDestinationURL: exported.appendingPathComponent("session.json"))
        fails { try SessionFiles.updateConditions([], for: legacy, root: storage, active: nil) }

        let remembered = library.categories
        try fm.removeItem(at: file.deletingLastPathComponent())
        try Data().write(to: file.deletingLastPathComponent())
        fails { try library.saveCategory(id: nil, name: "Blocked") }
        precondition(library.categories == remembered)
        let badFile = root.appendingPathComponent("corrupt.json")
        try corrupt.write(to: badFile)
        let badLibrary = SessionConditionLibrary(file: badFile)
        precondition(!badLibrary.loaded && badLibrary.notice != nil)
        fails { try badLibrary.saveCategory(id: nil, name: "Keep original") }
        let assertion13 = try Data(contentsOf: badFile) == corrupt
        precondition(assertion13)
        print("Session conditions: catalog persistence, category isolation, validation, snapshots, live updates, rollback, history, legacy compatibility, exports, and failure preservation passed")
    }
}
