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
        for time in [0.25, 0.25, 1.5, 3.0] { try writer.event(time: time, type: "key_down", repeated: false) }
        writer.append([MouseSummary(start: 0, end: 4, distance: 123.125, events: 4, secondsSinceMovement: nil)])
        let pause = BreakRecord(id: "break", promptID: "prompt", start: 1, plannedSeconds: 2, plannedActivity: "Rest, stretch", actualActivity: "Rest", end: 3)
        try writer.logBreak(BreakLogEntry(time: 1, action: "break_start", promptID: "prompt", record: pause, nextEligible: nil, sinceLastBreak: 1))
        try writer.logBreak(BreakLogEntry(time: 3, action: "break_end", promptID: "prompt", record: pause, nextEligible: nil, sinceLastBreak: 0))
        let check = TimedCheckIn(id: "check", due: 3, referenceBreakID: "break", requestedAt: 3)
        try writer.logSurveyPrompt(SurveyPromptEntry(item: check, action: "requested", time: 3))
        try writer.logSurveyPrompt(SurveyPromptEntry(item: check, action: "reminder_requested", time: 3.25))
        try writer.logSurvey(SurveyEntry(id: "check", context: .duringWork, status: .skipped, breakID: "", shownAt: start.addingTimeInterval(3), answeredAt: start.addingTimeInterval(3.5), shownElapsed: 3, answeredElapsed: 3.5, fatigue: nil, productivity: nil))
        try writer.finish(startedAt: start, duration: 4, reason: "test")
        let journal = WorkAssignmentJournal(changes: [.init(elapsed: 0, assignment: project)], breaks: [.init(id: "break", start: 1, end: 3)])
        try journal.save(to: writer.folder)
        let log = "{\"action\":\"requested\",\"effectiveElapsed\":3.125,\"request\":{\"id\":\"reminder\",\"context\":\"non_work\"}}"
        try (log + "\n").write(to: writer.folder.appendingPathComponent("reminders.jsonl"), atomically: true, encoding: .utf8)
        let studyLog = "{\"action\":\"requested\",\"elapsed\":3.25,\"prompt\":{\"id\":\"check\",\"recallStart\":0,\"recallEnd\":3.25}}"
        try (studyLog + "\n").write(to: writer.folder.appendingPathComponent("study_check_ins.jsonl"), atomically: true, encoding: .utf8)
        // Raw tail is preserved, but cannot be credited as durable activity.
        let eventsURL = writer.folder.appendingPathComponent("events.csv")
        let handle = try FileHandle(forWritingTo: eventsURL); try handle.seekToEnd()
        try handle.write(contentsOf: Data("5.000000,key_down,0,,,,,work,5.000000\n".utf8)); try handle.close()
        let originalEvents = try Data(contentsOf: eventsURL)
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
        let legacy = try SavedSession(folder: legacyFolder)
        let result = try SessionFiles.exportSelected([legacy, saved], to: destination, root: root, active: nil, timeZone: utc)
        let files = try fm.contentsOfDirectory(atPath: result.folder.path).sorted()
        try expect(files == ["activity-2026-11-25.csv", "activity-2026-11-26.csv", "metadata.json"])
        let firstDay = try rows(result.folder.appendingPathComponent(files[0]))
        let nextDay = try rows(result.folder.appendingPathComponent(files[1]))
        let all = firstDay + nextDay
        let events = all.filter { $0["source_file"] == "events.csv" && $0["row_type"] == "input_event" }
        try expect(events.count == 6 && events.filter { $0["source_elapsed_seconds"] == "0.250000" }.count == 2)
        try expect(events.first(where: { $0["source_elapsed_seconds"] == "5.000000" })?["coverage_eligible"] == "false")
        try expect(events.first(where: { $0["session_id"] == "legacy" })?["activity_context"] == "unknown")
        try expect(events.first(where: { $0["session_id"] == "legacy" })?["intervention_phase"] == "normal")
        try expect(all.contains { $0["row_type"] == "break_interval" && $0["break_id"] == "legacy-break" })
        try expect(Set(all.compactMap { $0["row_id"] }).count == all.count)
        let intervals = all.filter { $0["row_type"] == "mouse_interval" }
        try expect(intervals.count == 1 && intervals[0]["source_distance_screen_points"] == "123.125000")
        let continuations = nextDay.filter { $0["row_type"] == "interval_continuation" }
        try expect(!continuations.isEmpty && continuations.allSatisfy { $0["source_distance_screen_points"] == "" && !$0["continues_row_id"]!.isEmpty })
        let response = all.first { $0["row_type"] == "check_in_response" }!
        try expect(response["check_in_id"] == "check" && response["source_fatigue_0_10"] == "" && response["source_productivity_0_10"] == "")
        try expect(all.filter { $0["row_type"] == "check_in_action" }.count == 2)
        try expect(all.first { $0["row_type"] == "reminder_action" }?["source_record_json"] == log)
        let displayed = events.first { $0["session_id"] == "first" }!["project_name"]!
        try expect(displayed == "'" + project.projectName!)
        let metadata = try JSONSerialization.jsonObject(with: Data(contentsOf: result.folder.appendingPathComponent("metadata.json"))) as! [String: Any]
        try expect(metadata["time_zone"] as? String == "GMT")
        try expect(metadata["export_schema"] as? String == DailyTimeline.version)
        try expect(try SessionStorage.data("events.csv", in: writer.folder) == originalEvents)
        let again = try SessionFiles.exportSelected([saved, legacy], to: destination, root: root, active: nil, timeZone: utc)
        for file in files { try expect(try Data(contentsOf: result.folder.appendingPathComponent(file)) == Data(contentsOf: again.folder.appendingPathComponent(file))) }
        // Zone changes regroup days consistently for the whole export.
        let east = try SessionFiles.exportSelected([saved, legacy], to: destination, root: root, active: nil, timeZone: TimeZone(identifier: "America/New_York")!)
        try expect(try fm.contentsOfDirectory(atPath: east.folder.path).sorted() == ["activity-2026-11-25.csv", "metadata.json"])
        // Quoting and UTF-8 work across the streaming reader's 64 KiB boundary.
        let parserFile = temporary.appendingPathComponent("parser.csv")
        let longText = String(repeating: "é", count: 32760) + "\"quoted\",\nnext line"
        try ("a,b\r\n" + ["plain", longText].map(DailyTimeline.cell).joined(separator: ",") + "\r\n").write(to: parserFile, atomically: true, encoding: .utf8)
        let parser = try TimelineRecords(parserFile)
        _ = try parser.next(csv: true)
        try expect(try TimelineRecords.cells(parser.next(csv: true)!) == ["plain", longText])
        // A fall-back clock change stays in one local day while UTC order remains monotonic.
        let dstStart = ISO8601DateFormatter().date(from: "2026-11-01T05:59:59Z")!
        let dst = try RecordingWriter(root: root, id: "dst", startedAt: dstStart)
        try dst.event(time: 0.5, type: "key_down")
        try dst.event(time: 1.5, type: "key_up", hold: 1)
        try dst.finish(startedAt: dstStart, duration: 2, reason: "test")
        let dstExport = try SessionFiles.exportSelected([SavedSession(folder: dst.folder)], to: destination, root: root, active: nil,
                                                        timeZone: TimeZone(identifier: "America/New_York")!)
        let dstEvents = try rows(dstExport.folder.appendingPathComponent("activity-2026-11-01.csv")).filter { $0["row_type"] == "input_event" }
        try expect(dstEvents[0]["time_local"]!.hasSuffix("-04:00") && dstEvents[1]["time_local"]!.hasSuffix("-05:00"))
        // Public single and all-session entrypoints use the daily layout too.
        let single = try SessionFiles.export(saved, to: destination, root: root, active: nil)
        try expect(try fm.contentsOfDirectory(atPath: single.path).allSatisfy { $0 == "metadata.json" || $0.hasPrefix("activity-") })
        let everything = try SessionFiles.exportAll(to: destination, root: root, active: nil)
        try expect(everything.count == 3 && fm.fileExists(atPath: everything.folder.appendingPathComponent("metadata.json").path))
        let beforeFailure = try fm.contentsOfDirectory(atPath: destination.path).sorted()
        fails { _ = try SessionFiles.exportSelected([saved, saved], to: destination, root: root, active: nil) }
        fails { _ = try SessionFiles.exportSelected([saved], to: destination, root: root, active: saved.folder) }
        fails { _ = try SessionFiles.exportSelected([saved], to: writer.folder, root: root, active: nil) }
        // Malformed source data removes the entire incomplete batch, not just the last file.
        try Data("elapsed_seconds,event_type\n1,\"unterminated".utf8).write(to: legacyFolder.appendingPathComponent("events.csv"))
        fails { _ = try SessionFiles.exportSelected([saved, legacy], to: destination, root: root, active: nil) }
        try expect(try fm.contentsOfDirectory(atPath: destination.path).sorted() == beforeFailure)
        print("PASS: daily merging, exact events, midnight references, blank ratings, repeated requests, CRLF, multiline text, mixed formats and atomic failure cleanup")
    }
}
