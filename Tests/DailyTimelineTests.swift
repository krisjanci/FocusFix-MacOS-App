import Foundation

@main struct DailyTimelineTests {
    static func rows(_ file: URL) throws -> [[String: String]] {
        let reader = try TimelineRecords(file)
        let header = try TimelineRecords.cells(reader.next(csv: true)!)
        var result: [[String: String]] = []
        while let line = try reader.next(csv: true) {
            let cells = try TimelineRecords.cells(line)
            try expect(cells.count == header.count)
            result.append(Dictionary(uniqueKeysWithValues: zip(header, cells)))
        }
        return result
    }
    static func expect(_ value: @autoclosure () throws -> Bool, file: StaticString = #file, line: UInt = #line) throws { let result = try value(); precondition(result, file: file, line: line) }
    static func fails(_ body: () throws -> Void) { do { try body(); preconditionFailure("Expected failure") } catch {} }
    static func main() throws {
        let fm = FileManager.default, utc = TimeZone(secondsFromGMT: 0)!
        let temporary = fm.temporaryDirectory.appendingPathComponent("timeline-tests-\(UUID())")
        let root = temporary.appendingPathComponent("sessions"), destination = temporary.appendingPathComponent("exports")
        try fm.createDirectory(at: destination, withIntermediateDirectories: true)
        defer { try? fm.removeItem(at: temporary) }
        let start = ISO8601DateFormatter().date(from: "2026-11-25T23:59:58Z")!
        let writer = try RecordingWriter(root: root, id: "first", startedAt: start)
        let project = WorkAssignment(projectID: UUID(), projectName: "=Private, \"project\"\n第二行", taskID: UUID(), taskTitle: "Task")
        try writer.selectAssignment(project, at: 0)
        for time in [3.0, 0.25, 0.25, 1.5] { try writer.event(time: time, type: "key_down", repeated: false) }
        writer.append([MouseSummary(start: 0, end: 4, distance: 123.125, events: 4, secondsSinceMovement: nil)])
        let pause = BreakRecord(id: "break", promptID: "prompt", start: 1, plannedSeconds: 2, plannedActivity: "Rest, stretch", actualActivity: "Rest", end: 3)
        try writer.logBreak(BreakLogEntry(time: 1, action: "break_start", promptID: "prompt", record: pause, nextEligible: nil, sinceLastBreak: 1))
        try writer.logBreak(BreakLogEntry(time: 3, action: "break_end", promptID: "prompt", record: pause, nextEligible: nil, sinceLastBreak: 0))
        let check = TimedCheckIn(id: "check", due: 3, referenceBreakID: "break", requestedAt: 3)
        try writer.logSurveyPrompt(SurveyPromptEntry(item: check, action: "requested", time: 3))
        try writer.logSurveyPrompt(SurveyPromptEntry(item: check, action: "reminder_requested", time: 3.25))
        try writer.logSurvey(SurveyEntry(id: "check", context: .duringWork, status: .skipped, breakID: "break", shownAt: start.addingTimeInterval(3), answeredAt: start.addingTimeInterval(3.5), shownElapsed: 3, answeredElapsed: 3.5, fatigue: nil, productivity: nil))
        try writer.finish(startedAt: start, duration: 4, reason: "test")
        let journal = WorkAssignmentJournal(changes: [.init(elapsed: 0, assignment: project)], breaks: [.init(id: "break", start: 1, end: 3)])
        try journal.save(to: writer.folder)
        let log = "{\"action\":\"requested\",\"effectiveElapsed\":3.125,\"recordedAtUTC\":1795641601.1234567890123456789,\"large\":9007199254740993,\"unknown\":[true,null,1e100],\"request\":{\"id\":\"prompt\",\"context\":\"non_work\"}}"
        try (log + "\n").write(to: writer.folder.appendingPathComponent("reminders.jsonl"), atomically: true, encoding: .utf8)
        let studyLog = "{\"action\":\"requested\",\"elapsed\":3.25,\"prompt\":{\"id\":\"check\",\"recallStart\":0,\"recallEnd\":3.25}}"
        try (studyLog + "\n").write(to: writer.folder.appendingPathComponent("study_check_ins.jsonl"), atomically: true, encoding: .utf8)
        // Raw tail is preserved, but cannot be credited as durable activity.
        let eventsURL = writer.folder.appendingPathComponent("events.csv")
        let handle = try FileHandle(forWritingTo: eventsURL); try handle.seekToEnd()
        try handle.write(contentsOf: Data("5.000000,key_down,0,,,,\n".utf8)); try handle.close()
        let originalEvents = try Data(contentsOf: eventsURL)
        try Data("UTF-8 notes, 第二行\n".utf8).write(to: writer.folder.appendingPathComponent("notes.txt"))
        let originalFirst = try snapshot(writer.folder)
        _ = try SessionStorage.compact(writer.folder, force: true)
        let saved = try SavedSession(folder: writer.folder)
        // Second legacy session on the same day joins the same CSV, never gains Work from phase=work.
        let legacyFolder = root.appendingPathComponent("legacy")
        try fm.createDirectory(at: legacyFolder, withIntermediateDirectories: false)
        try Data("{\"started_at_utc\":\"2026-11-26T00:00:00Z\",\"schema_version\":5,\"status\":\"test\",\"duration_seconds\":1}".utf8).write(to: legacyFolder.appendingPathComponent("session.json"))
        try Data("elapsed_seconds,event_type,activity_phase\r\n0.000000,key_down,work\r\n".utf8).write(to: legacyFolder.appendingPathComponent("events.csv"))
        // Legacy break intervals do not require work_assignments.json.
        try (BreakLogEntry.header + "0.000000,break_start,p,legacy-break,4.000000,0.000000,,,,Rest,,,,0.000000\n" +
             "1.000000,break_end,p,legacy-break,4.000000,0.000000,1.000000,1.000000,0.000000,Rest,Rest,return,,0.000000\n").write(to: legacyFolder.appendingPathComponent("breaks.csv"), atomically: true, encoding: .utf8)
        let oldSurvey = SurveyEntry.header.replacingOccurrences(of: "productivity_0_10", with: "workload_0_10") +
            "legacy,check-old,old-protocol,during_work,answered,,2026-11-26T00:00:00Z,2026-11-26T00:00:00Z,0.000000,0.000000,0,7\n"
        try oldSurvey.write(to: legacyFolder.appendingPathComponent("surveys.csv"), atomically: true, encoding: .utf8)
        try Data("start_seconds,end_seconds,distance_screen_points,movement_events,seconds_since_last_movement,activity_phase,seconds_since_last_break\n0.49,0.4999,1.123456,1,0,work,0.4999\n0.5,0.51,2,2,0.005,check_in,0.51\n".utf8).write(to: legacyFolder.appendingPathComponent("mouse_movement.csv"))
        let originalLegacy = try snapshot(legacyFolder)
        let legacy = try SavedSession(folder: legacyFolder)
        let result = try SessionFiles.exportSelected([legacy, saved], to: destination, root: root, active: nil, timeZone: utc)
        let rootFiles = try fm.contentsOfDirectory(atPath: result.folder.path).sorted()
        try expect(rootFiles == ["2026-11-25", "2026-11-26", "metadata.json", "sessions.csv"])
        let exported = try ExportReader(result.folder)
        try exported.verify(["first": originalFirst, "legacy": originalLegacy])
        try expect(exported.metadata["export_schema"] as? String == "focusfix.daily_tables.v3")
        try expect(exported.metadata["time_zone"] as? String == "GMT")
        let inputRows = try exported.category("inputs.csv")
        try expect(inputRows.count == 6 && inputRows.filter { $0["elapsed_s"] == "0.25" }.count == 2)
        try expect(inputRows.allSatisfy { $0["source_record_json"] == nil && $0["time_utc"] == nil && $0["project"] == nil })
        try expect(inputRows[0]["elapsed_s"] == "0.25" && inputRows[1]["elapsed_s"] == "0.25")
        try expect(inputRows.contains { $0["elapsed_s"] == "5" })
        let lookup = exported.sessions.first { $0["session_id"] == "first" }!
        try expect(lookup["observed_through_s"] == "4" && lookup["elapsed_origin_s"] == "0")
        let movement = try exported.category("movement.csv")
        try expect(movement.count == 3 && movement[0]["start_s"] == "0" && movement[0]["end_s"] == "4")
        try expect(movement[0]["distance_points"] == "123.1" && movement[0]["since_movement_s"] == "")
        try expect(movement[0]["phase"] == nil && movement[0]["since_break_s"] == nil)
        try expect(movement[1]["distance_points"] == "1.1" && movement[2]["distance_points"] == "2")
        try expect(movement[1]["start_s"] == "0" && movement[1]["end_s"] == "0" && movement[1]["since_movement_s"] == "0")
        try expect(movement[2]["start_s"] == "1" && movement[2]["end_s"] == "1" && movement[2]["since_movement_s"] == "0.01")
        try expect(inputRows.allSatisfy { $0["phase"] == nil && $0["since_break_s"] == nil })
        let cross = exported.metadata["cross_day"] as! [[String: Any]]
        try expect(cross.contains { ($0["days"] as? [String])?.contains("2026-11-26") == true })
        try expect(!(try exported.category("changes.csv")).contains { $0["kind"] == "interval_continuation" })
        let answer = try exported.category("checkins.csv").first { $0["status"] == "skipped" }!
        let prompt = try exported.category("changes.csv").first { $0["kind"] == "check_in_action" }!
        let study = try exported.category("changes.csv").first { $0["kind"] == "study_check_in" }!
        try expect(answer["check_in"] == prompt["reference"] && answer["check_in"] == study["reference"])
        let pauseRows = try exported.category("breaks.csv").filter { $0["session"] == answer["session"] }
        try expect(pauseRows.allSatisfy { $0["break"] == answer["break"] && $0["prompt"] == "p1" })
        try expect(answer["fatigue_0_10"] == "" && answer["productivity_0_10"] == "")
        try expect((try exported.category("checkins.csv")).contains { $0["fatigue_0_10"] == "0" && $0["workload_0_10"] == "7" })
        try expect((try exported.category("changes.csv")).contains { $0["project"] == project.projectName && $0["task"] == project.taskTitle })
        try expect((exported.metadata["escaped_cells"] as! [[String: Any]]).contains { $0["column"] as? String == "project" })
        try expect((exported.metadata["csv_sources"] as! [[String: Any]]).contains { ($0["file"] as? String) == "events.csv" && $0["order"] != nil })
        try expect(try SessionStorage.data("events.csv", in: writer.folder) == originalEvents)
        let again = try SessionFiles.exportSelected([saved, legacy], to: destination, root: root, active: nil, timeZone: utc)
        try expect(try snapshotTree(result.folder) == snapshotTree(again.folder))
        let east = try SessionFiles.exportSelected([saved, legacy], to: destination, root: root, active: nil, timeZone: TimeZone(identifier: "America/New_York")!)
        try expect(try fm.contentsOfDirectory(atPath: east.folder.path).sorted() == ["2026-11-25", "metadata.json", "sessions.csv"])
        // Long quoted UTF-8 fields cross the parser's 64 KiB boundary.
        let parserFile = temporary.appendingPathComponent("parser.csv")
        let longText = String(repeating: "é", count: 32760) + "\"quoted\",\nnext line"
        try ("a,b\r\n" + ["plain", longText].map(DailyTimeline.cell).joined(separator: ",") + "\r\n").write(to: parserFile, atomically: true, encoding: .utf8)
        let parser = try TimelineRecords(parserFile); _ = try parser.next(csv: true)
        try expect(try TimelineRecords.cells(parser.next(csv: true)!) == ["plain", longText])
        try expect(DailyTimeline.cell("") == "" && DailyTimeline.cell("0") == "0" && DailyTimeline.cell("-0.1") == "-0.1")
        try expect(DailyTimeline.cell("one\r\ntwo") == "\"one\r\ntwo\"")
        try expect(DailyTimeline.compactNumber("0.1234567890123456789000") == "0.1234567890123456789")
        try expect(DailyTimeline.compactNumber("-0.000000") == "-0" && DailyTimeline.compactNumber("1e-30") == "1e-30")
        for (value, places, expected) in [("8.995604", 0, "9"), ("0.499999999999999999", 0, "0"),
            ("0.5", 0, "1"), ("-0.5", 0, "-1"), ("0.004999999", 2, "0"), ("0.005", 2, "0.01"),
            ("-0.005", 2, "-0.01"), ("0.000001", 2, "0"), ("1.2e-7", 2, "0"), ("5e-3", 2, "0.01"),
            ("1.149999999999999999", 1, "1.1"), ("1.15", 1, "1.2"), ("9.95", 1, "10"),
            ("0.049", 1, "0"), ("5e-2", 1, "0.1"), ("-1.15", 1, "-1.2"), ("", 1, ""),
            ("9.999", 2, "10"), ("", 2, ""), ("1.20", 2, "1.2")] {
            try expect(DailyTimeline.roundedNumber(value, places: places) == expected)
        }
        // DST clock reversal does not reverse event order or split the local day.
        let dstStart = ISO8601DateFormatter().date(from: "2026-11-01T05:59:59Z")!
        let dst = try RecordingWriter(root: root, id: "dst", startedAt: dstStart)
        try dst.event(time: 0.5, type: "key_down"); try dst.event(time: 1.5, type: "key_up", hold: 1)
        try dst.finish(startedAt: dstStart, duration: 2, reason: "test")
        let dstExport = try SessionFiles.exportSelected([SavedSession(folder: dst.folder)], to: destination, root: root, active: nil,
                                                        timeZone: TimeZone(identifier: "America/New_York")!)
        let dstReader = try ExportReader(dstExport.folder)
        try expect(try dstReader.category("inputs.csv").map { $0["elapsed_s"]! } == ["0.5", "1.5"])
        try dstReader.verify(["dst": snapshot(dst.folder)])
        // Rotated logical clocks retain full-precision origins and split records by anchored day.
        let rotatedStart = start.addingTimeInterval(1.5), origin = 100.123456789
        let contract = RecordingContract(mode: .automatic, startedAt: rotatedStart, elapsedOrigin: origin)
        let rotated = try RecordingWriter(root: root, id: "rotated", startedAt: rotatedStart, continuingContract: contract)
        try rotated.event(time: origin + 0.1, type: "key_down")
        try rotated.event(time: origin + 1, type: "key_up", hold: 0.9)
        rotated.append([MouseSummary(start: origin, end: origin + 2, distance: 0, events: 0, secondsSinceMovement: nil)])
        try rotated.finish(startedAt: rotatedStart, duration: origin + 2, reason: "test")
        let rotatedOriginal = try snapshot(rotated.folder)
        _ = try SessionStorage.compact(rotated.folder, force: true)
        let rotatedExport = try SessionFiles.exportSelected([SavedSession(folder: rotated.folder)], to: destination, root: root, active: nil, timeZone: utc)
        let rotatedReader = try ExportReader(rotatedExport.folder)
        try rotatedReader.verify(["rotated": rotatedOriginal])
        try expect(rotatedReader.sessions[0]["elapsed_origin_s"] == String(origin))
        try expect(fm.fileExists(atPath: rotatedExport.folder.appendingPathComponent("2026-11-25/inputs.csv").path))
        try expect(fm.fileExists(atPath: rotatedExport.folder.appendingPathComponent("2026-11-26/inputs.csv").path))
        let single = try SessionFiles.export(saved, to: destination, root: root, active: nil)
        try expect(fm.fileExists(atPath: single.appendingPathComponent("sessions.csv").path))
        let everything = try SessionFiles.exportAll(to: destination, root: root, active: nil)
        try expect(everything.count == 4)
        // A completed recording with only empty source tables creates no date folder.
        let empty = try RecordingWriter(root: root, id: "empty", startedAt: start)
        try empty.finish(startedAt: start, duration: 0, reason: "test")
        // Its recorded initial context and assignment are real changes, so remove optional sidecars only in a legacy fixture.
        let noRows = root.appendingPathComponent("no-rows")
        try fm.createDirectory(at: noRows, withIntermediateDirectories: false)
        try Data("{\"schema_version\":5,\"session_id\":\"no-rows\",\"status\":\"test\",\"duration_seconds\":0}".utf8).write(to: noRows.appendingPathComponent("session.json"))
        try Data("elapsed_seconds,event_type\n".utf8).write(to: noRows.appendingPathComponent("events.csv"))
        let emptyExport = try SessionFiles.export(SavedSession(folder: noRows), to: destination, root: root, active: nil)
        try expect(try fm.contentsOfDirectory(atPath: emptyExport.path).sorted() == ["metadata.json", "sessions.csv"])
        try ExportReader(emptyExport).verify(["no-rows": snapshot(noRows)])
        // Unknown columns, changing protocol/session fields, text that looks numeric and formula protection.
        let unusual = root.appendingPathComponent("unusual")
        try fm.createDirectory(at: unusual, withIntermediateDirectories: false)
        try Data("{\"schema_version\":5,\"session_id\":\"=formula-id\",\"status\":\"test\",\"duration_seconds\":3}".utf8).write(to: unusual.appendingPathComponent("session.json"))
        let unusualRows = [["elapsed_seconds", "event_type", "session_id", "question_version", "elapsed_s", "tag", "unknown,header"],
                           ["1.230000000000000000000", "key_down", "001", "q-first", "untouched", "0001.0000", "=formula"],
                           ["2.000000", "key_up", "002", "q-second", "also untouched", "line one\r\nline two", "'literal"]]
        try (unusualRows.map { $0.map { value in
            // This fixture writes original text without export-time spreadsheet protection.
            "\"" + value.replacingOccurrences(of: "\"", with: "\"\"") + "\""
        }.joined(separator: ",") }.joined(separator: "\r\n") + "\r\n").write(to: unusual.appendingPathComponent("events.csv"), atomically: true, encoding: .utf8)
        try Data("unrecognised log; preserved verbatim\r\n".utf8).write(to: unusual.appendingPathComponent("future.jsonl"))
        // Empty strings, null and missing JSON properties are reconstructed distinctly.
        var emptyAssignment = try DailyExportJSON.parse(String(decoding: originalFirst[WorkAssignmentJournal.filename]!, as: UTF8.self))
        emptyAssignment.set(["changes"], to: .array([.object(["elapsed": .number("0"), "assignment": .object(["projectName": .string(""), "taskTitle": .literal("null")])])]))
        try emptyAssignment.encoded().write(to: unusual.appendingPathComponent(WorkAssignmentJournal.filename), atomically: true, encoding: .utf8)
        let unusualOriginal = try snapshot(unusual)
        _ = try SessionStorage.compact(unusual, force: true)
        let unusualSaved = try SavedSession(folder: unusual)
        let unusualA = try SessionFiles.export(unusualSaved, to: destination, root: root, active: nil)
        let unusualB = try SessionFiles.export(unusualSaved, to: destination, root: root, active: nil)
        try expect(try snapshotTree(unusualA) == snapshotTree(unusualB))
        let unusualReader = try ExportReader(unusualA)
        try unusualReader.verify(["unusual": unusualOriginal])
        let unusualInput = try unusualReader.category("inputs.csv")
        try expect(unusualInput[0]["elapsed_s"] == "1.23" && unusualInput[0]["tag"] == "0001.0000")
        try expect(unusualInput[1]["tag"] == "line one\r\nline two")
        try expect(unusualReader.sessions[0]["session_id"] == "=formula-id")
        // Group historical measurements by their original start before rounding across midnight.
        let midnight = root.appendingPathComponent("midnight")
        try fm.createDirectory(at: midnight, withIntermediateDirectories: false)
        try Data("{\"schema_version\":5,\"started_at_utc\":\"2026-11-25T23:59:58Z\",\"status\":\"test\",\"duration_seconds\":3}".utf8).write(to: midnight.appendingPathComponent("session.json"))
        let midnightCSV = "start_seconds,end_seconds,distance_screen_points,movement_events,seconds_since_last_movement,activity_phase,seconds_since_last_break\n2.01,2.02,2,2,0.004,check_in,2.02\n1.99,2.01,1,1,,work,2.01\n"
        try midnightCSV.write(to: midnight.appendingPathComponent("mouse_movement.csv"), atomically: true, encoding: .utf8)
        let midnightExport = try SessionFiles.exportSelected([SavedSession(folder: midnight)], to: destination, root: root, active: nil, timeZone: utc)
        let beforeMidnight = try rows(midnightExport.folder.appendingPathComponent("2026-11-25/movement.csv"))
        let afterMidnight = try rows(midnightExport.folder.appendingPathComponent("2026-11-26/movement.csv"))
        try expect(beforeMidnight.count == 1 && beforeMidnight[0]["start_s"] == "2" && beforeMidnight[0]["end_s"] == "2" && beforeMidnight[0]["distance_points"] == "1")
        try expect(afterMidnight.count == 1 && afterMidnight[0]["start_s"] == "2" && afterMidnight[0]["since_movement_s"] == "0")
        try ExportReader(midnightExport.folder).verify(["midnight": snapshot(midnight)])
        let reducedMetadata = try String(contentsOf: midnightExport.folder.appendingPathComponent("metadata.json"), encoding: .utf8)
        try expect(!reducedMetadata.contains("1.99") && !reducedMetadata.contains("2.01") && !reducedMetadata.contains("0.004"))
        // The original lexical JSON parser also rejects malformed/duplicate fields instead of dropping them.
        fails { _ = try DailyExportJSON.parse("{\"a\":1,\"a\":2}") }
        fails { _ = try DailyExportJSON.parse("{\"a\":01}") }
        let beforeFailure = try fm.contentsOfDirectory(atPath: destination.path).sorted()
        fails { _ = try SessionFiles.exportSelected([saved, saved], to: destination, root: root, active: nil) }
        fails { _ = try SessionFiles.exportSelected([saved], to: destination, root: root, active: saved.folder) }
        fails { _ = try SessionFiles.exportSelected([saved], to: writer.folder, root: root, active: nil) }
        try Data("elapsed_seconds,event_type\n1,\"unterminated".utf8).write(to: legacyFolder.appendingPathComponent("events.csv"))
        fails { _ = try SessionFiles.exportSelected([saved, legacy], to: destination, root: root, active: nil) }
        try expect(try fm.contentsOfDirectory(atPath: destination.path).sorted() == beforeFailure)
        print("PASS: retained CSV/JSON fields reconstruct, approved reductions, daily merging, precision, short references, no empty files, stable ordering, DST and failure cleanup")
    }
    static func snapshot(_ folder: URL) throws -> [String: Data] {
        var result: [String: Data] = [:]
        for name in try SessionStorage.names(in: folder) { result[name] = try SessionStorage.data(name, in: folder) }
        return result
    }
    static func snapshotTree(_ root: URL) throws -> [String: Data] {
        var result: [String: Data] = [:]
        let canonicalRoot = root.resolvingSymlinksInPath().standardizedFileURL
        for case let url as URL in FileManager.default.enumerator(at: canonicalRoot, includingPropertiesForKeys: [.isRegularFileKey])! {
            if try url.resourceValues(forKeys: [.isRegularFileKey]).isRegularFile == true {
                let path = url.resolvingSymlinksInPath().standardizedFileURL.path
                try expect(path.hasPrefix(canonicalRoot.path + "/"))
                result[String(path.dropFirst(canonicalRoot.path.count + 1))] = try Data(contentsOf: url)
            }
        }
        return result
    }
    // Independent inverse of the export schema; proves reconstruction rather than just checking row counts.
    struct ExportReader {
        let root: URL
        let metadata: [String: Any]
        let sessions: [[String: String]]
        init(_ root: URL) throws {
            self.root = root
            metadata = try JSONSerialization.jsonObject(with: Data(contentsOf: root.appendingPathComponent("metadata.json"))) as! [String: Any]
            sessions = try Self.read(root, "sessions.csv", metadata)
        }
        static func read(_ root: URL, _ path: String, _ metadata: [String: Any]) throws -> [[String: String]] {
            var rows = try DailyTimelineTests.rows(root.appendingPathComponent(path))
            for cell in metadata["escaped_cells"] as! [[String: Any]] where cell["file"] as? String == path {
                let index = (cell["row"] as! Int) - 1, column = cell["column"] as! String
                try expect(rows[index][column]!.first == "'")
                rows[index][column]!.removeFirst()
            }
            return rows
        }
        func category(_ table: String) throws -> [[String: String]] {
            var result: [[String: String]] = []
            for path in (metadata["files"] as! [String: Int]).keys.sorted() where path.hasSuffix("/" + table) {
                result += try Self.read(root, path, metadata)
            }
            return result
        }
        func lookup(_ value: String, _ domain: String) -> String {
            if value.isEmpty { return "" }
            return (metadata["identities"] as! [String: [String: String]])[domain]![value]!
        }
        func restored(_ descriptor: [String: Any], row: [String: String]) throws -> DailyExportJSON {
            var result = try DailyExportJSON.parse(descriptor["remaining_json"] as! String)
            for move in descriptor["moves"] as! [[String: Any]] {
                var text = row[move["column"] as! String]!
                if let domain = move["lookup"] as? String { text = lookup(text, domain) }
                let value: DailyExportJSON = move["type"] as? String == "number" ? .number(text) : .string(text)
                result.set(move["path"] as! [String], to: value)
            }
            return result
        }
        func verify(_ originals: [String: [String: Data]]) throws {
            let sources = metadata["csv_sources"] as! [[String: Any]]
            let allChanges = try category("changes.csv")
            let byDetail = Dictionary(uniqueKeysWithValues: allChanges.compactMap { row -> (Int, [String: String])? in
                guard let value = row["detail"], let key = Int(value) else { return nil }; return (key, row)
            })
            let details = metadata["json_records"] as! [[String: Any]]
            func record(_ key: Int) throws -> DailyExportJSON { try restored(details[key - 1], row: byDetail[key]!) }
            func original(_ session: String, _ file: String) -> Data {
                let row = sessions.first { $0["session"] == session }!
                let folder = (metadata["folder_names"] as! [String: String])[session] ?? row["session_id"]!
                return originals[folder]![file]!
            }
            var accounted: [String: Set<String>] = [:]
            for source in sources {
                let session = source["session"] as! String, name = source["file"] as! String, table = source["table"] as! String
                let header = source["header"] as! [String], mapping = source["columns"] as! [String: String]
                let constants = source["constants"] as! [String: [String: String]]
                var rows = try category(table).filter { $0["session"] == session && (table != "changes.csv" || Int($0["detail"] ?? "") == nil) }
                if let order = source["order"] as? [Int] { rows = zip(order, rows).sorted { $0.0 < $1.0 }.map { $0.1 } }
                let data = original(session, name)
                let temporary = FileManager.default.temporaryDirectory.appendingPathComponent("source-csv-\(UUID()).csv")
                try data.write(to: temporary)
                defer { try? FileManager.default.removeItem(at: temporary) }
                let reader = try TimelineRecords(temporary)
                let expected = try TimelineRecords.cells(reader.next(csv: true)!)
                let omitted: Set<String> = ["inputs.csv", "movement.csv"].contains(table) ? ["activity_phase", "seconds_since_last_break"] : []
                try expect(expected.filter { !omitted.contains($0) } == header)
                var parsed = [expected]
                while let line = try reader.next(csv: true) { if !line.isEmpty { parsed.append(try TimelineRecords.cells(line)) } }
                try expect(rows.count == parsed.count - 1 && rows.count == source["records"] as! Int)
                for (index, row) in rows.enumerated() {
                    for (column, field) in expected.enumerated() where !omitted.contains(field) {
                        let value: String
                        if let constant = constants[field] {
                            value = constant["session_column"].map { key in sessions.first { $0["session"] == session }![key]! } ?? lookup(constant["reference"]!, constant["lookup"]!)
                        } else {
                            let cell = row[mapping[field]!]!
                            let domain = (metadata["identity_csv_fields"] as! [String: String])[field]
                            value = domain.map { lookup(cell, $0) } ?? cell
                        }
                        let sourceValue = parsed[index + 1][column]
                        let numeric = Set(metadata["numeric_csv_fields"] as! [String]).contains(field)
                        let roundedPlaces: Int? = table == "movement.csv" ? (["start_seconds", "end_seconds"].contains(field) ? 0 : (field == "seconds_since_last_movement" ? 2 : (field == "distance_screen_points" ? 1 : nil))) : nil
                        let expectedValue = roundedPlaces.map { DailyTimeline.roundedNumber(sourceValue, places: $0) } ?? (numeric ? DailyTimeline.compactNumber(sourceValue) : sourceValue)
                        try expect(value == expectedValue)
                    }
                }
                accounted[session, default: []].insert(name)
            }
            for document in metadata["documents"] as! [[String: Any]] {
                let session = document["session"] as! String, name = document["file"] as! String
                if let text = document["text"] as? String { try expect(Data(text.utf8) == original(session, name)) }
                else {
                    var value = try restored(document, row: sessions.first { $0["session"] == session }!)
                    for collection in document["collections"] as! [[String: Any]] {
                        let entries = try (collection["records"] as! [Int]).map { try record($0) }
                        value.set(collection["path"] as! [String], to: .array(entries))
                    }
                    try expect(canonical(value) == canonical(DailyExportJSON.parse(String(decoding: original(session, name), as: UTF8.self))))
                }
                accounted[session, default: []].insert(name)
            }
            for log in metadata["json_logs"] as! [[String: Any]] {
                let session = log["session"] as! String, name = log["file"] as! String
                let expected = String(decoding: original(session, name), as: UTF8.self).split(separator: "\n").filter { !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
                let keys = log["records"] as! [Int]
                try expect(keys.count == expected.count)
                for (index, key) in keys.enumerated() { try expect(canonical(record(key)) == canonical(DailyExportJSON.parse(String(expected[index])))) }
                accounted[session, default: []].insert(name)
            }
            for session in sessions {
                let key = session["session"]!, folder = (metadata["folder_names"] as! [String: String])[key] ?? session["session_id"]!
                try expect(accounted[key] == Set(originals[folder]!.keys))
            }
        }
        func canonical(_ value: DailyExportJSON) -> String {
            switch value {
            case .number(let value): return DailyTimeline.compactNumber(value)
            case .array(let values): return "[" + values.map(canonical).joined(separator: ",") + "]"
            case .object(let fields): return "{" + fields.keys.sorted().map { DailyExportJSON.quoted($0) + ":" + canonical(fields[$0]!) }.joined(separator: ",") + "}"
            default: return value.encoded()
            }
        }
    }
}
