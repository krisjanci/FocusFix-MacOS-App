import Foundation

@main struct DailyExportSizeTests {
    static func main() throws {
        let fm = FileManager.default
        let temporary = fm.temporaryDirectory.appendingPathComponent("daily-export-size-\(UUID())")
        defer { try? fm.removeItem(at: temporary) }
        let root = temporary.appendingPathComponent("sessions"), exports = temporary.appendingPathComponent("exports")
        try fm.createDirectory(at: exports, withIntermediateDirectories: true)
        let start = Date(timeIntervalSince1970: 1_795_608_000)
        let writer = try RecordingWriter(root: root, id: "size-session", startedAt: start)
        for index in 0..<10000 {
            try writer.event(time: Double(index) / 100, type: index % 2 == 0 ? "key_down" : "key_up",
                             repeated: index % 2 == 0 ? false : nil, hold: index % 2 == 0 ? nil : 0.005)
        }
        writer.append((0..<100).map { MouseSummary(start: Double($0), end: Double($0 + 1), distance: 12.125, events: 3, secondsSinceMovement: 0.125) })
        try writer.finish(startedAt: start, duration: 100, reason: "size_test")
        let before = Date()
        let result = try SessionFiles.exportSelected([SavedSession(folder: writer.folder)], to: exports, root: root, active: nil,
                                                    timeZone: TimeZone(secondsFromGMT: 0)!)
        let files = fm.enumerator(at: result.folder, includingPropertiesForKeys: [.isRegularFileKey, .fileSizeKey])!
        var bytes = 0, count = 0
        for case let file as URL in files {
            let info = try file.resourceValues(forKeys: [.isRegularFileKey, .fileSizeKey])
            if info.isRegularFile == true { bytes += info.fileSize ?? 0; count += 1 }
        }
        // Measured with this same fixture using v1 at source f99fe15, before replacement.
        // UUID contents vary, but their serialized lengths and fixture measurements do not.
        let wideBytes = 7_108_139
        precondition(DailyTimeline.version == "focusfix.daily_tables.v2")
        precondition(bytes < wideBytes / 4, "All narrow CSVs plus both lookup files must beat the wide export by at least 75%")
        precondition(count == 5, "Inputs, movement, changes and the two shared files; no empty break/check-in tables")
        let day = result.folder.appendingPathComponent("2026-11-25")
        func header(_ name: String) throws -> [String] {
            let reader = try TimelineRecords(day.appendingPathComponent(name))
            return try TimelineRecords.cells(reader.next(csv: true)!)
        }
        let inputHeader = try header("inputs.csv"), movementHeader = try header("movement.csv"), changeHeader = try header("changes.csv")
        precondition(inputHeader.count == 10 && movementHeader.count == 8)
        precondition(changeHeader.count == 7 && !changeHeader.contains("recorded_session") && !changeHeader.contains("due_s"),
                     "Empty prompt source headers must not create empty columns in the changes table")
        print(String(format: "SIZE total uncompressed export: %d -> %d bytes (%.2f%% smaller)", wideBytes, bytes, 100 * (1 - Double(bytes) / Double(wideBytes))))
        print("SIZE \(DailyTimeline.version): \(bytes) bytes across \(count) files; \(Date().timeIntervalSince(before)) seconds")
    }
}
