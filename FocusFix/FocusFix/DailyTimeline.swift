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

// JSON numbers remain lexical tokens: Foundation JSONSerialization can round
// fractional timestamps and large integers while decoding/re-encoding a document.
nonisolated indirect enum DailyExportJSON {
    case object([String: DailyExportJSON]), array([DailyExportJSON]), string(String), number(String), literal(String)
    static func parse(_ text: String) throws -> Self {
        let bytes = Array(text.utf8); var index = 0
        func whitespace() { while index < bytes.count && [9, 10, 13, 32].contains(bytes[index]) { index += 1 } }
        func string() throws -> String {
            let start = index; index += 1
            while index < bytes.count {
                if bytes[index] == 92 { index += 2; continue }
                if bytes[index] == 34 {
                    index += 1
                    return try JSONDecoder().decode(String.self, from: Data(bytes[start..<index]))
                }
                index += 1
            }
            throw RecordingContract.Invalid.contract
        }
        func value(depth: Int = 0) throws -> Self {
            whitespace()
            guard index < bytes.count, depth < 128 else { throw RecordingContract.Invalid.contract }
            let first = bytes[index]
            if first == 34 { return .string(try string()) }
            if first == 123 || first == 91 {
                index += 1; whitespace()
                var object: [String: Self] = [:], array: [Self] = []
                let end: UInt8 = first == 123 ? 125 : 93
                if index < bytes.count, bytes[index] == end { index += 1; return first == 123 ? .object(object) : .array(array) }
                while true {
                    whitespace()
                    if first == 123 {
                        guard index < bytes.count, bytes[index] == 34 else { throw RecordingContract.Invalid.contract }
                        let key = try string(); whitespace()
                        guard object[key] == nil, index < bytes.count, bytes[index] == 58 else { throw RecordingContract.Invalid.contract }
                        index += 1; object[key] = try value(depth: depth + 1)
                    } else { array.append(try value(depth: depth + 1)) }
                    whitespace()
                    guard index < bytes.count else { throw RecordingContract.Invalid.contract }
                    if bytes[index] == end { index += 1; break }
                    guard bytes[index] == 44 else { throw RecordingContract.Invalid.contract }
                    index += 1
                }
                return first == 123 ? .object(object) : .array(array)
            }
            let start = index
            while index < bytes.count && ![9, 10, 13, 32, 44, 93, 125].contains(bytes[index]) { index += 1 }
            let token = String(decoding: bytes[start..<index], as: UTF8.self)
            if ["true", "false", "null"].contains(token) { return .literal(token) }
            guard token.range(of: #"^-?(0|[1-9][0-9]*)(\.[0-9]+)?([eE][+-]?[0-9]+)?$"#, options: .regularExpression) != nil else {
                throw RecordingContract.Invalid.contract
            }
            return .number(token)
        }
        let result = try value(); whitespace()
        guard index == bytes.count else { throw RecordingContract.Invalid.contract }
        return result
    }
    static func quoted(_ text: String) -> String {
        let encoder = JSONEncoder(); encoder.outputFormatting = [.withoutEscapingSlashes]
        return String(decoding: try! encoder.encode(text), as: UTF8.self)
    }
    func encoded() -> String {
        switch self {
        case .object(let fields): return "{" + fields.keys.sorted().map { Self.quoted($0) + ":" + fields[$0]!.encoded() }.joined(separator: ",") + "}"
        case .array(let values): return "[" + values.map { $0.encoded() }.joined(separator: ",") + "]"
        case .string(let value): return Self.quoted(value)
        case .number(let value), .literal(let value): return value
        }
    }
    func at(_ path: [String]) -> Self? {
        guard let first = path.first else { return self }
        guard case .object(let values) = self else { return nil }
        return values[first]?.at(Array(path.dropFirst()))
    }
    mutating func remove(_ path: [String]) {
        guard let first = path.first, case .object(var values) = self else { return }
        if path.count == 1 { values.removeValue(forKey: first) }
        else { values[first]?.remove(Array(path.dropFirst())) }
        self = .object(values)
    }
    mutating func set(_ path: [String], to value: Self) {
        guard let first = path.first else { self = value; return }
        var values: [String: Self]
        if case .object(let existing) = self { values = existing } else { values = [:] }
        var child = values[first] ?? .object([:]); child.set(Array(path.dropFirst()), to: value)
        values[first] = child; self = .object(values)
    }
    var scalar: (text: String, type: String)? {
        switch self {
        case .number(let value): return (DailyTimeline.compactNumber(value), "number")
        case .string(let value): return (value, "string")
        default: return nil // Missing, null, booleans and containers remain in metadata.
        }
    }
}

nonisolated enum DailyTimeline {
    static let version = "focusfix.daily_tables.v3"
    static let sessionColumns = ["session", "session_id", "recording_id", "segment_id", "start_utc", "end_utc",
        "anchor_unix_s", "mode", "elapsed_origin_s", "observed_through_s", "duration_s", "status", "schema_version"]
    static let csvTables = ["events.csv": "inputs.csv", "mouse_movement.csv": "movement.csv", "breaks.csv": "breaks.csv",
                            "surveys.csv": "checkins.csv", "survey_prompts.csv": "changes.csv"]
    private static let sourceNames = ["events.csv", "mouse_movement.csv", "breaks.csv", "surveys.csv", "survey_prompts.csv"]
    private static let aliases = ["elapsed_seconds": "elapsed_s", "event_type": "event", "is_repeat": "repeat",
        "key_hold_seconds": "hold_s", "scroll_delta_x": "scroll_x", "scroll_delta_y": "scroll_y", "scroll_precise": "precise",
        "activity_phase": "phase", "seconds_since_last_break": "since_break_s", "start_seconds": "start_s", "end_seconds": "end_s",
        "distance_screen_points": "distance_points", "seconds_since_last_movement": "since_movement_s",
        "planned_seconds": "planned_s", "actual_seconds": "actual_s", "extra_idle_seconds": "extra_idle_s",
        "next_eligible_seconds": "next_eligible_s", "break_id": "break", "prompt_id": "prompt", "session_id": "recorded_session",
        "shown_elapsed_seconds": "shown_s", "answered_elapsed_seconds": "answered_s", "due_elapsed_seconds": "due_s",
        "notification_requested_elapsed_seconds": "requested_s", "opened_elapsed_seconds": "opened_s", "reference_break_id": "break"]
    private static let numericFields: Set<String> = ["elapsed_seconds", "is_repeat", "key_hold_seconds", "scroll_delta_x", "scroll_delta_y",
        "scroll_precise", "seconds_since_last_break", "start_seconds", "end_seconds", "distance_screen_points", "movement_events",
        "seconds_since_last_movement", "planned_seconds", "actual_seconds", "extra_idle_seconds", "next_eligible_seconds",
        "shown_elapsed_seconds", "answered_elapsed_seconds", "due_elapsed_seconds", "notification_requested_elapsed_seconds",
        "opened_elapsed_seconds", "fatigue_0_10", "productivity_0_10", "workload_0_10"]
    private struct Spool: Codable {
        let table: String
        let source: Int
        let index: Int
        let values: [String: String]
    }
    // Round decimal text directly: do not introduce binary floating-point tie errors.
    static func roundedNumber(_ value: String, places: Int) -> String {
        guard !value.isEmpty else { return value }
        let negative = value.first == "-"
        let unsigned = negative ? String(value.dropFirst()) : value
        let parts = unsigned.split(separator: ".", omittingEmptySubsequences: false)
        guard parts.count <= 2, !parts[0].isEmpty,
              parts.allSatisfy({ $0.allSatisfy { $0.isASCII && $0.isNumber } }) else { return value }
        let fraction = parts.count == 2 ? String(parts[1]) : ""
        let kept = String(fraction.prefix(places)) + String(repeating: "0", count: max(0, places - fraction.count))
        var digits = Array((String(parts[0]) + kept).utf8)
        if fraction.count > places, fraction[fraction.index(fraction.startIndex, offsetBy: places)] >= "5" {
            var index = digits.count - 1
            while digits[index] == 57 { digits[index] = 48; index -= 1; if index < 0 { break } }
            if index < 0 { digits.insert(49, at: 0) } else { digits[index] += 1 }
        }
        var text = String(decoding: digits, as: UTF8.self)
        if places > 0 { text.insert(".", at: text.index(text.endIndex, offsetBy: -places)) }
        text = compactNumber(text)
        while text.count > 1 && text.first == "0" && text.dropFirst().first != "." { text.removeFirst() }
        return negative && text.contains(where: { $0 >= "1" && $0 <= "9" }) ? "-" + text : text
    }
    private static func discarded(_ field: String, table: String) -> Bool {
        ["inputs.csv", "movement.csv"].contains(table) && ["activity_phase", "seconds_since_last_break"].contains(field)
    }
    private static func reducedValue(_ value: String, field: String, table: String) -> String {
        if table == "movement.csv" {
            if ["start_seconds", "end_seconds"].contains(field) { return roundedNumber(value, places: 0) }
            if field == "seconds_since_last_movement" { return roundedNumber(value, places: 2) }
        }
        return numericFields.contains(field) ? compactNumber(value) : value
    }
    // Lexical trimming retains arbitrarily precise decimals, signed zero and exponents.
    static func compactNumber(_ value: String) -> String {
        guard value.range(of: #"^-?[0-9]+\.[0-9]+$"#, options: .regularExpression) != nil else { return value }
        var result = value
        while result.last == "0" { result.removeLast() }
        if result.last == "." { result.removeLast() }
        return result
    }
    static func needsProtection(_ value: String) -> Bool {
        value.trimmingCharacters(in: .whitespacesAndNewlines).first.map { "=+-@".contains($0) } == true && Double(value) == nil
    }
    static func cell(_ value: String) -> String {
        let safe = needsProtection(value) ? "'" + value : value
        // CSV delimiters are bytes. Swift treats CRLF (and some combining
        // sequences) as a single Character, so Character.contains misses them.
        guard safe.utf8.contains(where: { [10, 13, 34, 44].contains($0) }) else { return safe }
        var encoded = Data([34])
        for byte in safe.utf8 { encoded.append(byte); if byte == 34 { encoded.append(34) } }
        encoded.append(34)
        return String(decoding: encoded, as: UTF8.self)
    }
    private static func finite(_ value: String?) throws -> Double {
        guard let value, let result = Double(value), result.isFinite else { throw RecordingContract.Invalid.bounds }
        return result
    }
    static func export(_ sessions: [SavedSession], to folder: URL, timeZone: TimeZone = .current) throws {
        let fm = FileManager.default
        let stage = fm.temporaryDirectory.appendingPathComponent("FocusFix-daily-tables-\(UUID())")
        try fm.createDirectory(at: stage, withIntermediateDirectories: false, attributes: [.posixPermissions: 0o700])
        defer { try? fm.removeItem(at: stage) }
        let spoolURL = stage.appendingPathComponent("rows.txt")
        guard fm.createFile(atPath: spoolURL.path, contents: nil) else { throw CocoaError(.fileWriteUnknown) }
        let spool = try FileHandle(forWritingTo: spoolURL); defer { try? spool.close() }
        let encoder = JSONEncoder(); encoder.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]
        var calendar = Calendar(identifier: .gregorian); calendar.timeZone = timeZone
        let day = DateFormatter(); day.locale = Locale(identifier: "en_US_POSIX"); day.calendar = calendar
        day.timeZone = timeZone; day.dateFormat = "yyyy-MM-dd"
        var columns: [String: [String]] = [:], fieldMaps: [String: [String: String]] = [:]
        var csvSources: [[String: Any]] = [], documents: [[String: Any]] = [], logs: [[String: Any]] = []
        var records: [[String: Any]] = [], crossDay: [[String: Any]] = [], lookups: [String: [String: String]] = [:]
        var reverseLookups: [String: [String: String]] = [:], sessionRows: [[String: String]] = []
        var folderNames: [String: String] = [:], order = 0
        func addColumn(_ name: String, table: String) {
            if !columns[table, default: []].contains(name) { columns[table, default: []].append(name) }
        }
        func identity(_ value: String, _ domain: String) -> String {
            guard !value.isEmpty else { return "" }
            if let existing = reverseLookups[domain]?[value] { return existing }
            let prefix = ["break": "b", "check_in": "c", "prompt": "p", "protocol": "q", "session_id": "s"][domain]!
            let reference = prefix + String(lookups[domain, default: [:]].count + 1)
            lookups[domain, default: [:]][reference] = value
            reverseLookups[domain, default: [:]][value] = reference
            return reference
        }
        func domain(_ field: String) -> String? {
            switch field {
            case "break_id", "reference_break_id": return "break"
            case "check_in_id": return "check_in"
            case "prompt_id": return "prompt"
            case "question_version": return "protocol"
            case "session_id": return "session_id"
            default: return nil
            }
        }
        func fieldColumn(_ field: String, table: String) -> String {
            if let existing = fieldMaps[table]?[field] { return existing }
            var result = field == "check_in_id" ? (table == "changes.csv" ? "reference" : "check_in") : aliases[field] ?? field
            if result.range(of: #"^[A-Za-z_][A-Za-z_0-9]*$"#, options: .regularExpression) == nil { result = "field_" + String(fieldMaps[table, default: [:]].count + 1) }
            let reserved = table == "changes.csv" ? ["session", "kind", "detail"] : ["session"]
            let knownAlias = aliases[field] != nil || field == "check_in_id"
            if reserved.contains(result) || (!knownAlias && aliases.values.contains(result)) || fieldMaps[table, default: [:]].values.contains(result) {
                result = "field_" + result
                while fieldMaps[table, default: [:]].values.contains(result) { result = "field_" + result }
            }
            fieldMaps[table, default: [:]][field] = result
            return result
        }
        for (sessionIndex, input) in sessions.sorted(by: { $0.id < $1.id }).enumerated() {
            try Task.checkCancellation()
            // Legacy recordings without timestamps use the original folder's creation date,
            // never the creation date of a temporary archive-extraction directory.
            let anchoredStart = try SavedSession(folder: input.folder).startedAt
            try SessionStorage.withFolder(input.folder) { readable in
                let saved = try SavedSession(folder: readable), reference = String(sessionIndex + 1)
                let origin = saved.recordingContract?.elapsedOrigin ?? 0
                let through = saved.recordingContract?.observedThrough ?? saved.duration ?? origin
                let names = try SessionStorage.names(in: readable)
                if names.contains(WorkAssignmentJournal.filename) { _ = try WorkAssignmentJournal.load(from: readable) }
                var sessionRow = ["session": reference, "anchor_unix_s": compactNumber(String(anchoredStart.timeIntervalSince1970))]
                func emit(table: String, source: Int, index: Int, values: [String: String], at elapsed: Double,
                          span: (Double, Double)? = nil) throws {
                    let date = anchoredStart.addingTimeInterval(elapsed - origin)
                    guard date.timeIntervalSince1970.isFinite else { throw RecordingContract.Invalid.bounds }
                    var row = values; row["session"] = reference
                    for key in row.keys { addColumn(key, table: table) }
                    order += 1
                    let record = Spool(table: table, source: source, index: index, values: row)
                    let payload = String(decoding: try encoder.encode(record), as: UTF8.self)
                    let stamp = String(format: "%.9f", locale: Locale(identifier: "en_US_POSIX"), date.timeIntervalSince1970)
                    let logical = String(format: "%.17f", locale: Locale(identifier: "en_US_POSIX"), elapsed)
                    try spool.write(contentsOf: Data("\(stamp)\t\(sessionIndex)\t\(logical)\t\(order)\t\(payload)\n".utf8))
                    if let (start, end) = span {
                        guard start.isFinite, end.isFinite, end >= start else { throw RecordingContract.Invalid.bounds }
                        let begin = anchoredStart.addingTimeInterval(start - origin), finish = anchoredStart.addingTimeInterval(end - origin)
                        var cursor = calendar.startOfDay(for: begin), days: [String] = []
                        while cursor < finish {
                            let label = day.string(from: cursor)
                            if label != day.string(from: date) { days.append(label) }
                            guard days.count < 36600, let next = calendar.date(byAdding: .day, value: 1, to: cursor), next > cursor else { throw RecordingContract.Invalid.bounds }
                            cursor = next
                        }
                        if !days.isEmpty {
                            var item: [String: Any] = ["source_day": day.string(from: date), "days": days]
                            if source >= 0 { item["csv_source"] = source + 1; item["record"] = index }
                            else { item["detail"] = index }
                            crossDay.append(item)
                        }
                    }
                }
                // Session fields have one owner; other JSON documents refer to this lookup.
                let sessionMoves = ["session.json": ["session_id": "session_id", "recording_id": "recording_id", "segment_id": "segment_id",
                    "started_at_utc": "start_utc", "ended_at_utc": "end_utc", "recording_mode": "mode", "duration_seconds": "duration_s",
                    "status": "status", "schema_version": "schema_version", "elapsed_origin_seconds": "elapsed_origin_s"],
                    "context_intervals.json": ["recordingID": "recording_id", "segmentID": "segment_id", "mode": "mode",
                        "elapsedOrigin": "elapsed_origin_s", "observedThrough": "observed_through_s"],
                    "research_eligibility.json": ["recordingID": "recording_id", "segmentID": "segment_id", "capturedAtUTC": "anchor_unix_s"]]
                var parsedDocuments: [(String, DailyExportJSON, [[String: Any]])] = []
                let logNames = ["reminders.jsonl", "study_check_ins.jsonl"]
                let documentNames = names.filter { !sourceNames.contains($0) && !logNames.contains($0) }
                for name in documentNames.sorted(by: { ($0 == "session.json" ? "" : $0) < ($1 == "session.json" ? "" : $1) }) {
                    let data = try SessionStorage.data(name, in: readable)
                    guard let text = String(data: data, encoding: .utf8) else { throw RecordingContract.Invalid.contract }
                    guard name.hasSuffix(".json") else {
                        documents.append(["session": reference, "file": name, "text": text]); continue
                    }
                    var node = try DailyExportJSON.parse(text), moves: [[String: Any]] = []
                    for (field, column) in (sessionMoves[name] ?? [:]).sorted(by: { $0.key < $1.key }) {
                        guard let scalar = node.at([field])?.scalar,
                              sessionRow[column] == nil || compactNumber(sessionRow[column]!) == scalar.text else { continue }
                        sessionRow[column] = scalar.text
                        moves.append(["path": [field], "column": column, "type": scalar.type])
                        node.remove([field])
                    }
                    parsedDocuments.append((name, node, moves))
                }
                if sessionRow["session_id"] == nil { sessionRow["session_id"] = input.id }
                if sessionRow["session_id"] != input.id { folderNames[reference] = input.id }
                if sessionRow["elapsed_origin_s"] == nil { sessionRow["elapsed_origin_s"] = compactNumber(String(origin)) }
                sessionRows.append(sessionRow)
                // CSV fields retain their own narrow schema. Only constant session/protocol fields move out.
                for name in sourceNames where names.contains(name) {
                    let table = csvTables[name]!, url = readable.appendingPathComponent(name)
                    let scan = try TimelineRecords(url)
                    guard let line = try scan.next(csv: true) else { throw RecordingContract.Invalid.contract }
                    let header = try TimelineRecords.cells(line)
                    guard !header.isEmpty, Set(header).count == header.count else { throw RecordingContract.Invalid.contract }
                    var constants: [String: String] = [:], count = 0
                    while let row = try scan.next(csv: true) {
                        try Task.checkCancellation()
                        if row.isEmpty { continue }
                        let cells = try TimelineRecords.cells(row)
                        guard cells.count == header.count else { throw RecordingContract.Invalid.contract }
                        count += 1
                        for field in ["session_id", "question_version"] {
                            guard let column = header.firstIndex(of: field) else { continue }
                            if count == 1 { constants[field] = cells[column] }
                            else if constants[field] != cells[column] { constants.removeValue(forKey: field) }
                        }
                    }
                    var constantMetadata: [String: Any] = [:], mapping: [String: String] = [:]
                    for field in header where !discarded(field, table: table) {
                        if let value = constants[field] {
                            if field == "session_id", value == sessionRow["session_id"] { constantMetadata[field] = ["session_column": "session_id"] }
                            else { constantMetadata[field] = ["lookup": domain(field)!, "reference": identity(value, domain(field)!)] }
                        } else {
                            mapping[field] = fieldColumn(field, table: table)
                        }
                    }
                    let source = csvSources.count
                    csvSources.append(["session": reference, "file": name, "table": table, "header": header.filter { !discarded($0, table: table) }, "columns": mapping,
                                       "constants": constantMetadata, "records": count])
                    let reader = try TimelineRecords(url); _ = try reader.next(csv: true); var index = 0
                    while let line = try reader.next(csv: true) {
                        try Task.checkCancellation()
                        if line.isEmpty { continue }
                        index += 1
                        let cells = try TimelineRecords.cells(line)
                        guard cells.count == header.count else { throw RecordingContract.Invalid.contract }
                        let fields = Dictionary(uniqueKeysWithValues: zip(header, cells))
                        var row: [String: String] = [:]
                        if table == "changes.csv" { row["kind"] = "check_in_action" }
                        for field in header where mapping[field] != nil {
                            let value = fields[field]!
                            row[mapping[field]!] = domain(field).map { identity(value, $0) } ?? reducedValue(value, field: field, table: table)
                        }
                        let at = try finite(fields["elapsed_seconds"] ?? fields["answered_elapsed_seconds"] ?? fields["start_seconds"])
                        let start = fields["start_seconds"].flatMap(Double.init), end = fields["end_seconds"].flatMap(Double.init)
                        try emit(table: table, source: source, index: index, values: row, at: at,
                                 span: start.flatMap { a in end.map { (a, $0) } })
                    }
                }
                // Low-volume JSON records keep only unmapped fields in metadata, with exact numeric lexemes.
                func jsonRecord(_ original: DailyExportJSON, kind: String, definitions: [(String, [String], String?)], at path: [String], end: [String]? = nil) throws -> Int {
                    var node = original, moves: [[String: Any]] = [], row = ["kind": kind]
                    let elapsed = try finite(node.at(path)?.scalar?.text)
                    for (column, path, lookup) in definitions {
                        guard let scalar = node.at(path)?.scalar else { continue }
                        row[column] = lookup.map { identity(scalar.text, $0) } ?? scalar.text
                        var move: [String: Any] = ["path": path, "column": column, "type": scalar.type]
                        if let lookup { move["lookup"] = lookup }
                        moves.append(move); node.remove(path)
                    }
                    let detail = records.count + 1
                    records.append(["remaining_json": node.encoded(), "moves": moves])
                    row["detail"] = String(detail)
                    let finish = end.flatMap { original.at($0)?.scalar?.text }.flatMap(Double.init) ?? (end == nil ? nil : through)
                    try emit(table: "changes.csv", source: -1, index: detail, values: row, at: elapsed, span: finish.map { (elapsed, $0) })
                    return detail
                }
                for (name, original, moves) in parsedDocuments {
                    var node = original, collections: [[String: Any]] = []
                    let specifications: [(String, String, String, String?)] = name == "context_intervals.json" ? [("intervals", "context", "start", "end")] :
                        name == WorkAssignmentJournal.filename ? [("changes", "assignment", "elapsed", nil), ("breaks", "assignment_break", "start", "end")] : []
                    for (field, kind, time, finish) in specifications {
                        guard let collection = node.at([field]) else { continue }
                        guard case .array(let entries) = collection else { throw RecordingContract.Invalid.contract }
                        var identifiers: [Int] = []
                        for entry in entries {
                            let definitions: [(String, [String], String?)] = [("elapsed_s", [time], nil), ("end_s", [finish ?? "end"], nil),
                                ("context", ["context"], nil), ("reference", ["id"], kind == "assignment_break" ? "break" : nil),
                                ("project", ["assignment", "projectName"], nil), ("task", ["assignment", "taskTitle"], nil)]
                            identifiers.append(try jsonRecord(entry, kind: kind, definitions: definitions, at: [time], end: finish.map { [$0] }))
                        }
                        node.remove([field]); collections.append(["path": [field], "records": identifiers])
                    }
                    documents.append(["session": reference, "file": name, "remaining_json": node.encoded(), "moves": moves, "collections": collections])
                }
                for name in names.filter({ logNames.contains($0) }).sorted() {
                    let reader = try TimelineRecords(readable.appendingPathComponent(name)); var identifiers: [Int] = []
                    while let line = try reader.next() {
                        try Task.checkCancellation()
                        if line.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty { continue }
                        let node = try DailyExportJSON.parse(line)
                        let isReminder = name == "reminders.jsonl", time = isReminder ? "effectiveElapsed" : "elapsed"
                        let parent = isReminder ? "request" : "prompt"
                        let definitions: [(String, [String], String?)] = [("elapsed_s", [time], nil), ("action", ["action"], nil),
                            ("reference", [parent, "id"], isReminder ? "prompt" : "check_in"),
                            ("context", [parent, isReminder ? "context" : "contextAtPrompt"], nil)]
                        identifiers.append(try jsonRecord(node, kind: isReminder ? "reminder" : "study_check_in", definitions: definitions, at: [time]))
                    }
                    logs.append(["session": reference, "file": name, "records": identifiers])
                }
            }
        }
        try spool.close()
        // Headers are stable across days and selected-session order, without unioning unrelated categories.
        let preferred = ["session", "elapsed_s", "start_s", "end_s", "kind", "event", "action", "reference", "context", "project", "task",
            "repeat", "hold_s", "scroll_x", "scroll_y", "precise", "phase", "since_break_s", "distance_points", "movement_events",
            "since_movement_s", "check_in", "break", "prompt", "due_s", "requested_s", "opened_s", "detail"]
        for table in columns.keys {
            columns[table] = columns[table]!.sorted { a, b in
                let x = preferred.firstIndex(of: a) ?? Int.max, y = preferred.firstIndex(of: b) ?? Int.max
                return x == y ? a < b : x < y
            }
        }
        let sortedURL = stage.appendingPathComponent("sorted.txt"), process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/sort")
        process.arguments = ["-t", "\t", "-k1,1n", "-k2,2n", "-k3,3n", "-k4,4n", "-T", stage.path, "-o", sortedURL.path, spoolURL.path]
        process.environment = ProcessInfo.processInfo.environment.merging(["LC_ALL": "C"]) { _, new in new }
        process.standardOutput = FileHandle.nullDevice; process.standardError = FileHandle.nullDevice
        try process.run(); process.waitUntilExit()
        guard process.terminationStatus == 0 else { throw CocoaError(.fileWriteUnknown) }
        var escaped: [[String: Any]] = [], rowCounts: [String: Int] = [:], outputs: [String: FileHandle] = [:]
        var currentDay = "", previous: [Int: Int] = [:], reordered = Set<Int>()
        defer { for output in outputs.values { try? output.close() } }
        func writeRow(_ values: [String: String], header: [String], path: String, handle: FileHandle, row: Int) throws {
            var cells: [String] = []
            for column in header {
                let value = values[column] ?? ""
                if needsProtection(value) { escaped.append(["file": path, "row": row, "column": column]) }
                cells.append(cell(value))
            }
            try handle.write(contentsOf: Data((cells.joined(separator: ",") + "\n").utf8))
        }
        let reader = try TimelineRecords(sortedURL)
        while let line = try reader.next() {
            try Task.checkCancellation()
            let parts = line.split(separator: "\t", maxSplits: 4, omittingEmptySubsequences: false)
            guard parts.count == 5, let stamp = Double(parts[0]) else { throw RecordingContract.Invalid.contract }
            let item = try JSONDecoder().decode(Spool.self, from: Data(parts[4].utf8))
            let key = day.string(from: Date(timeIntervalSince1970: stamp))
            if currentDay != key {
                for handle in outputs.values { try handle.close() }; outputs = [:]; currentDay = key
                try fm.createDirectory(at: folder.appendingPathComponent(key), withIntermediateDirectories: false, attributes: [.posixPermissions: 0o700])
            }
            let path = key + "/" + item.table, header = columns[item.table]!
            if outputs[item.table] == nil {
                let url = folder.appendingPathComponent(path)
                guard fm.createFile(atPath: url.path, contents: nil, attributes: [.posixPermissions: 0o600]) else { throw CocoaError(.fileWriteUnknown) }
                let handle = try FileHandle(forWritingTo: url); outputs[item.table] = handle
                try handle.write(contentsOf: Data((header.joined(separator: ",") + "\n").utf8))
            }
            rowCounts[path, default: 0] += 1
            try writeRow(item.values, header: header, path: path, handle: outputs[item.table]!, row: rowCounts[path]!)
            if item.source >= 0 {
                if item.index != (previous[item.source] ?? 0) + 1 { reordered.insert(item.source) }
                previous[item.source] = item.index
            }
        }
        for handle in outputs.values { try handle.close() }; outputs = [:]
        if !reordered.isEmpty {
            let reader = try TimelineRecords(sortedURL); var orders: [Int: [Int]] = [:]
            while let line = try reader.next() {
                let parts = line.split(separator: "\t", maxSplits: 4, omittingEmptySubsequences: false)
                let item = try JSONDecoder().decode(Spool.self, from: Data(parts[4].utf8))
                if reordered.contains(item.source) { orders[item.source, default: []].append(item.index) }
            }
            for (source, values) in orders { csvSources[source]["order"] = values }
        }
        let sessionsURL = folder.appendingPathComponent("sessions.csv")
        guard fm.createFile(atPath: sessionsURL.path, contents: nil, attributes: [.posixPermissions: 0o600]) else { throw CocoaError(.fileWriteUnknown) }
        let sessionOutput = try FileHandle(forWritingTo: sessionsURL); defer { try? sessionOutput.close() }
        try sessionOutput.write(contentsOf: Data((sessionColumns.joined(separator: ",") + "\n").utf8))
        for (index, row) in sessionRows.enumerated() { try writeRow(row, header: sessionColumns, path: "sessions.csv", handle: sessionOutput, row: index + 1) }
        try sessionOutput.close()
        let identityFields = Dictionary(uniqueKeysWithValues: ["break_id", "reference_break_id", "check_in_id", "prompt_id", "question_version", "session_id"].map { ($0, domain($0)!) })
        let metadata: [String: Any] = ["export_schema": version, "time_zone": timeZone.identifier, "columns": columns,
            "files": rowCounts, "identities": lookups, "csv_sources": csvSources, "documents": documents,
            "json_logs": logs, "json_records": records, "cross_day": crossDay, "escaped_cells": escaped, "folder_names": folderNames,
            "numeric_csv_fields": numericFields.sorted(), "identity_csv_fields": identityFields,
            "notes": ["Elapsed values stay on each recording's logical clock. Day grouping uses anchor_unix_s + elapsed - elapsed_origin_s in the export timezone.",
                "Inputs and movement omit phase and since-break values. Context/project/task changes are in changes.csv. Exact observation coverage, when recorded, remains once in document metadata.",
                "Movement bounds are rounded to whole seconds and idle measurements to at most two decimals, ties away from zero. Historical grouping and cross_day references use original bounds. Other interval bounds remain unchanged; intervals are [start,end).",
                "Durable bounds are in sessions.csv. Uncheckpointed tails remain present but must not receive work credit. Missing observations are not filled.",
                "CSV source columns/constants and lookup identities reconstruct retained fields. Omitted input/movement phase and since-break values and discarded movement precision are not retained.",
                "JSON moves place scalar values in changes.csv or sessions.csv. remaining_json retains all other fields with exact numeric tokens; collections/logs preserve record order.",
                "escaped_cells lists spreadsheet-protection apostrophes to remove when reconstructing text. Row numbers exclude headers.",
                "CSV source order is chronological unless order maps emitted rows back to their original one-based record indices. No per-event JSON copies or summary rows are stored."]]
        try JSONSerialization.data(withJSONObject: metadata, options: [.sortedKeys, .withoutEscapingSlashes]).write(to: folder.appendingPathComponent("metadata.json"), options: .atomic)
    }
}
