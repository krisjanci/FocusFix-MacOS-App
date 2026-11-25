import Foundation
import CoreFoundation

// Bounded-memory CSV reader. Quoted newlines and escaped quotes survive chunk boundaries.
nonisolated final class TimelineRecords {
    private let handle: FileHandle
    private var chunk = Data(), position = 0
    init(_ file: URL) throws { handle = try FileHandle(forReadingFrom: file) }
    deinit { try? handle.close() }
    func next(csv: Bool = false) throws -> String? {
        var record = Data(), quoted = false
        while true {
            if position == chunk.count {
                chunk = try handle.read(upToCount: 64 * 1024) ?? Data(); position = 0
                if chunk.isEmpty {
                    guard !quoted else { throw CocoaError(.fileReadCorruptFile) }
                    if record.isEmpty { return nil }
                    break
                }
            }
            let byte = chunk[position]; position += 1
            if csv && byte == 34 { quoted.toggle() }
            if byte == 10 && !quoted { break }
            record.append(byte)
            guard record.count <= 16 * 1024 * 1024 else { throw CocoaError(.fileReadTooLarge) }
        }
        if record.last == 13 { record.removeLast() }
        guard let text = String(data: record, encoding: .utf8) else { throw CocoaError(.fileReadInapplicableStringEncoding) }
        return text
    }
    static func cells(_ text: String) throws -> [String] {
        let bytes = Array(text.utf8)
        var cells: [String] = [], field = Data(), quoted = false, closed = false, index = 0
        func value() throws -> String {
            guard let result = String(data: field, encoding: .utf8) else { throw CocoaError(.fileReadCorruptFile) }
            return result
        }
        while index < bytes.count {
            let byte = bytes[index]
            if quoted {
                if byte == 34 {
                    if index + 1 < bytes.count, bytes[index + 1] == 34 { field.append(34); index += 1 }
                    else { quoted = false; closed = true }
                } else { field.append(byte) }
            } else if byte == 44 {
                cells.append(try value()); field = Data(); closed = false
            } else if byte == 34 && field.isEmpty && !closed { quoted = true }
            else {
                guard !closed && byte != 34 else { throw CocoaError(.fileReadCorruptFile) }
                field.append(byte)
            }
            index += 1
        }
        guard !quoted else { throw CocoaError(.fileReadCorruptFile) }
        cells.append(try value())
        return cells
    }
}

nonisolated enum DailyTimeline {
    static let version = "focusfix.daily_timeline.v1"
    static let commonColumns = ["row_id", "row_type", "session_id", "recording_id", "segment_id",
        "source_file", "source_row", "elapsed_seconds", "end_elapsed_seconds", "time_utc", "time_local", "time_zone",
        "activity_context", "original_activity_context", "intervention_phase", "coverage_eligible",
        "project_id", "project_name", "project_color", "task_id", "task_title", "check_in_id", "break_id", "action",
        "is_continuation", "continues_row_id", "source_record_json"]
    private static let csvNames = ["events.csv", "mouse_movement.csv", "breaks.csv", "surveys.csv", "survey_prompts.csv"]
    private static let logNames = ["reminders.jsonl", "study_check_ins.jsonl"]
    private static let kinds = ["events.csv": "input_event", "mouse_movement.csv": "mouse_interval",
        "breaks.csv": "break_action", "surveys.csv": "check_in_response", "survey_prompts.csv": "check_in_action",
        "reminders.jsonl": "reminder_action", "study_check_ins.jsonl": "study_check_in_action"]

    // Preserve original text in source_record_json. Prefix spreadsheet formula-like text only in display cells.
    static func cell(_ value: String) -> String {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        let safe = trimmed.first.map { "=+-@".contains($0) } == true && Double(value) == nil ? "'" + value : value
        return "\"" + safe.replacingOccurrences(of: "\"", with: "\"\"") + "\""
    }
    private static func json(_ value: Any) throws -> String {
        String(decoding: try JSONSerialization.data(withJSONObject: value, options: [.sortedKeys, .fragmentsAllowed]), as: UTF8.self)
    }
    private static func number(_ value: Any?) -> Double? {
        if let text = value as? String { return Double(text).flatMap { $0.isFinite ? $0 : nil } }
        if let number = value as? NSNumber, CFGetTypeID(number) != CFBooleanGetTypeID(), number.doubleValue.isFinite { return number.doubleValue }
        return nil
    }
    private static func text(_ value: Any?) -> String {
        guard let value, !(value is NSNull) else { return "" }
        return value as? String ?? (value as? NSNumber)?.stringValue ?? ""
    }
    static func export(_ sessions: [SavedSession], to folder: URL, timeZone: TimeZone = .current) throws {
        let manager = FileManager.default
        let stage = manager.temporaryDirectory.appendingPathComponent("FocusFix-timeline-\(UUID())")
        try manager.createDirectory(at: stage, withIntermediateDirectories: false, attributes: [.posixPermissions: 0o700])
        defer { try? manager.removeItem(at: stage) }
        let spoolURL = stage.appendingPathComponent("rows.txt")
        guard manager.createFile(atPath: spoolURL.path, contents: nil) else { throw CocoaError(.fileWriteUnknown) }
        let spool = try FileHandle(forWritingTo: spoolURL)
        defer { try? spool.close() }
        var columns = Set<String>(), sessionMetadata: [[String: Any]] = []
        var calendar = Calendar(identifier: .gregorian); calendar.timeZone = timeZone
        let utc = ISO8601DateFormatter(); utc.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        let local = ISO8601DateFormatter(); local.formatOptions = [.withInternetDateTime, .withFractionalSeconds]; local.timeZone = timeZone
        let day = DateFormatter(); day.locale = Locale(identifier: "en_US_POSIX"); day.calendar = calendar
        day.timeZone = timeZone; day.dateFormat = "yyyy-MM-dd"
        for session in sessions.sorted(by: { $0.id < $1.id }) {
            try Task.checkCancellation()
            try SessionStorage.withFolder(session.folder) { readable in
                let saved = try SavedSession(folder: readable)
                let contract = saved.recordingContract
                let origin = contract?.elapsedOrigin ?? 0, through = contract?.observedThrough ?? saved.duration ?? 0
                let names = try SessionStorage.names(in: readable)
                let assignments = names.contains(WorkAssignmentJournal.filename) ? try WorkAssignmentJournal.load(from: readable) : WorkAssignmentJournal()
                var metadata: [String: Any] = ["session_id": session.id, "schema_version": saved.schemaVersion,
                    "elapsed_origin": origin, "observed_through": through, "files": [String: String]()]
                var originals: [String: String] = [:]
                // Keep metadata/provenance byte-exact as UTF-8 text; logs become timeline rows below.
                for name in names where !csvNames.contains(name) && !logNames.contains(name) {
                    let data = try SessionStorage.data(name, in: readable)
                    guard let original = String(data: data, encoding: .utf8) else { throw CocoaError(.fileReadCorruptFile) }
                    originals[name] = original
                }
                metadata["files"] = originals; sessionMetadata.append(metadata)
                var order = 0
                func emit(file: String, index: Int, kind: String, at elapsed: Double, end: Double? = nil,
                          fields: [String: String] = [:], original: String, phase: String = "") throws {
                    guard elapsed.isFinite, elapsed >= 0, end.map({ $0.isFinite && $0 >= elapsed }) ?? true else {
                        throw RecordingContract.Invalid.bounds
                    }
                    let date = saved.startedAt.addingTimeInterval(elapsed - origin)
                    guard date.timeIntervalSince1970.isFinite else { throw RecordingContract.Invalid.bounds }
                    let context = contract?.intervals.last(where: { $0.start <= elapsed && elapsed < ($0.end ?? through) })?.context.rawValue ?? "unknown"
                    let assignment = assignments.changes.last(where: { $0.elapsed <= elapsed })?.assignment ?? .none
                    let withinEnd = end.map { $0 <= through } ??
                        (kind == "input_event" && fields["event_type"] != "session_stop" ? elapsed < through : elapsed <= through)
                    let eligible = elapsed >= origin && withinEnd
                    let id = "\(session.id)/\(file)/\(index)"
                    var row: [String: String] = ["row_id": id, "row_type": kind, "session_id": session.id,
                        "recording_id": contract?.recordingID.uuidString ?? "", "segment_id": contract?.segmentID.uuidString ?? "",
                        "source_file": file, "source_row": String(index), "elapsed_seconds": String(elapsed),
                        "end_elapsed_seconds": end.map(String.init(describing:)) ?? "", "time_utc": utc.string(from: date),
                        "time_local": local.string(from: date), "time_zone": timeZone.identifier,
                        "activity_context": context == "non_work" ? "unknown" : context, "original_activity_context": context,
                        "intervention_phase": phase == "work" ? "normal" : phase, "coverage_eligible": eligible ? "true" : "false",
                        "project_id": assignment.projectID?.uuidString ?? "", "project_name": assignment.projectName ?? "",
                        "project_color": assignment.projectColor ?? "", "task_id": assignment.taskID?.uuidString ?? "",
                        "task_title": assignment.taskTitle ?? "", "check_in_id": fields["check_in_id"] ?? "",
                        "break_id": fields["break_id"] ?? "", "action": fields["action"] ?? fields["event_type"] ?? "",
                        "is_continuation": "false", "continues_row_id": "", "source_record_json": original]
                    for (key, value) in fields { row["source_" + key] = value; columns.insert("source_" + key) }
                    func write(_ row: [String: String], at stamp: Date) throws {
                        order += 1
                        let encoded = String(decoding: try JSONEncoder().encode(row), as: UTF8.self)
                        let sortTime = String(format: "%.9f", locale: Locale(identifier: "en_US_POSIX"), stamp.timeIntervalSince1970)
                        try spool.write(contentsOf: Data("\(sortTime)\t\(session.id)\t\(order)\t\(encoded)\n".utf8))
                    }
                    try write(row, at: date)
                    if let end, end > elapsed {
                        let endDate = saved.startedAt.addingTimeInterval(end - origin)
                        var boundary = calendar.date(byAdding: .day, value: 1, to: calendar.startOfDay(for: date))!
                        var continuations = 0
                        while boundary < endDate {
                            // Only a reference, never repeated measurement totals.
                            row = Dictionary(uniqueKeysWithValues: commonColumns.map { ($0, "") })
                            row["row_id"] = id + "/" + day.string(from: boundary)
                            row["row_type"] = "interval_continuation"; row["session_id"] = session.id
                            row["recording_id"] = contract?.recordingID.uuidString ?? ""; row["segment_id"] = contract?.segmentID.uuidString ?? ""
                            row["source_file"] = file; row["source_row"] = String(index)
                            row["time_utc"] = utc.string(from: boundary); row["time_local"] = local.string(from: boundary)
                            row["time_zone"] = timeZone.identifier; row["is_continuation"] = "true"; row["continues_row_id"] = id
                            try write(row, at: boundary)
                            continuations += 1
                            guard continuations < 36600 else { throw RecordingContract.Invalid.bounds }
                            boundary = calendar.date(byAdding: .day, value: 1, to: boundary)!
                        }
                    }
                }
                try emit(file: "session.json", index: 0, kind: "segment_start", at: origin, original: "{}")
                for name in csvNames where names.contains(name) {
                    let reader = try TimelineRecords(readable.appendingPathComponent(name))
                    guard let first = try reader.next(csv: true) else { throw RecordingContract.Invalid.contract }
                    let header = try TimelineRecords.cells(first)
                    guard Set(header).count == header.count else { throw RecordingContract.Invalid.contract }
                    for key in header { columns.insert("source_" + key) }
                    var index = 0
                    while let line = try reader.next(csv: true) {
                        try Task.checkCancellation()
                        if line.isEmpty { continue }
                        index += 1
                        let values = try TimelineRecords.cells(line)
                        guard values.count == header.count else { throw RecordingContract.Invalid.contract }
                        let fields = Dictionary(uniqueKeysWithValues: zip(header, values))
                        let time = number(fields["elapsed_seconds"]) ?? number(fields["answered_elapsed_seconds"]) ?? number(fields["start_seconds"])
                        guard let time else { throw RecordingContract.Invalid.bounds }
                        let end = name == "mouse_movement.csv" ? number(fields["end_seconds"]) : nil
                        try emit(file: name, index: index, kind: kinds[name]!, at: time, end: end, fields: fields,
                                 original: json(fields), phase: fields["activity_phase"] ?? "")
                    }
                }
                for name in logNames where names.contains(name) {
                    let reader = try TimelineRecords(readable.appendingPathComponent(name)); var index = 0
                    while let line = try reader.next() {
                        try Task.checkCancellation()
                        if line.trimmingCharacters(in: .whitespaces).isEmpty { continue }
                        index += 1
                        guard let object = try JSONSerialization.jsonObject(with: Data(line.utf8)) as? [String: Any],
                              let elapsed = number(object["effectiveElapsed"]) ?? number(object["elapsed"]) else { throw RecordingContract.Invalid.contract }
                        let prompt = object["prompt"] as? [String: Any] ?? object["request"] as? [String: Any] ?? [:]
                        var fields = ["action": text(object["action"])]
                        fields["check_in_id"] = text(prompt["id"])
                        for (key, value) in object where value is String || value is NSNumber { fields[key] = text(value) }
                        try emit(file: name, index: index, kind: kinds[name]!, at: elapsed, fields: fields, original: line)
                    }
                }
                let encoder = JSONEncoder(); encoder.dateEncodingStrategy = .secondsSince1970; encoder.outputFormatting = [.sortedKeys]
                if let contract {
                    for (index, interval) in contract.intervals.enumerated() {
                        let original = String(decoding: try encoder.encode(interval), as: UTF8.self)
                        try emit(file: "context_intervals.json", index: index + 1, kind: "context_interval", at: interval.start,
                                 end: interval.end ?? through, original: original)
                    }
                }
                for (index, change) in assignments.changes.enumerated() {
                    try emit(file: WorkAssignmentJournal.filename, index: index + 1, kind: "assignment_change", at: change.elapsed,
                             original: String(decoding: try encoder.encode(change), as: UTF8.self))
                }
                // Break lifecycle snapshots retain the original action time; explicit intervals supply midnight continuations.
                for (index, item) in assignments.breaks.enumerated() {
                    try emit(file: WorkAssignmentJournal.filename, index: assignments.changes.count + index + 1,
                             kind: "break_interval", at: item.start, end: item.end ?? through,
                             fields: ["break_id": item.id], original: String(decoding: try encoder.encode(item), as: UTF8.self), phase: "explicit_break")
                }
                try emit(file: "session.json", index: 1, kind: "segment_end", at: through, original: "{}")
            }
        }
        try spool.close()
        let sorted = stage.appendingPathComponent("sorted.txt")
        let process = Process(); process.executableURL = URL(fileURLWithPath: "/usr/bin/sort")
        process.arguments = ["-t", "\t", "-k1,1n", "-k2,2", "-k3,3n", "-T", stage.path, "-o", sorted.path, spoolURL.path]
        process.environment = ProcessInfo.processInfo.environment.merging(["LC_ALL": "C"]) { _, new in new }
        process.standardOutput = FileHandle.nullDevice; process.standardError = FileHandle.nullDevice
        try process.run(); process.waitUntilExit()
        guard process.terminationStatus == 0 else { throw CocoaError(.fileWriteUnknown) }
        let header = commonColumns + columns.sorted()
        let reader = try TimelineRecords(sorted)
        var currentDay = "", output: FileHandle?, outputFiles: [String] = []
        defer { try? output?.close() }
        while let line = try reader.next() {
            try Task.checkCancellation()
            let parts = line.split(separator: "\t", maxSplits: 3, omittingEmptySubsequences: false)
            guard parts.count == 4, let stamp = Double(parts[0]) else { throw RecordingContract.Invalid.contract }
            let row = try JSONDecoder().decode([String: String].self, from: Data(parts[3].utf8))
            let key = day.string(from: Date(timeIntervalSince1970: stamp))
            if key != currentDay {
                try output?.close(); currentDay = key
                let name = "activity-\(key).csv", url = folder.appendingPathComponent(name)
                guard !manager.fileExists(atPath: url.path), manager.createFile(atPath: url.path, contents: nil, attributes: [.posixPermissions: 0o600]) else { throw CocoaError(.fileWriteFileExists) }
                output = try FileHandle(forWritingTo: url); outputFiles.append(name)
                try output!.write(contentsOf: Data((header.map(cell).joined(separator: ",") + "\n").utf8))
            }
            try output!.write(contentsOf: Data((header.map { cell(row[$0] ?? "") }.joined(separator: ",") + "\n").utf8))
        }
        try output?.close()
        let metadata: [String: Any] = ["export_schema": version, "time_zone": timeZone.identifier, "csv_files": outputFiles,
            "columns": header, "sessions": sessionMetadata,
            "notes": ["UTC/local row times are derived segment-start plus logical elapsed anchors, not sampled wall-clock observations.",
                "source_* columns and source_record_json preserve original values; metadata files preserve original UTF-8 text.",
                "Historical non_work normalizes to unknown only in activity_context; original context and source payloads remain intact.",
                "coverage_eligible marks durable bounds only; it does not imply observed work. Normal phase is separate from Work intent.",
                "Interval continuation rows reference the original row and contain no repeated measurements. Intervals use [start,end).",
                "Missing answers are blank. Requested prompts do not prove delivery. No activity is inferred through gaps.",
                "Project/task names are private historical snapshots. Display cells may have a spreadsheet-protection apostrophe; source_record_json retains original text."]]
        try JSONSerialization.data(withJSONObject: metadata, options: [.sortedKeys, .prettyPrinted]).write(to: folder.appendingPathComponent("metadata.json"), options: .atomic)
    }
}
