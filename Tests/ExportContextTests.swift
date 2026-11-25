import Foundation
import CoreGraphics

@main struct ExportContextTests {
    static func expect(_ value: Bool) { precondition(value) }

    static func main() throws {
        let temporary = FileManager.default.temporaryDirectory.appendingPathComponent("focusfix-context-exports-\(UUID())")
        let root = temporary.appendingPathComponent("sessions")
        let exports = temporary.appendingPathComponent("exports")
        try FileManager.default.createDirectory(at: exports, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: temporary) }
        let start = Date(timeIntervalSince1970: 1_800_000_000)
        let writer = try RecordingWriter(root: root, id: "legacy-context", startedAt: start, tags: ["non_work"])
        try writer.changeContext(.nonWork, at: 5, effectiveAt: start.addingTimeInterval(5), source: .userAction)
        try writer.changeContext(.unknown, at: 10, effectiveAt: start.addingTimeInterval(10), source: .userAction)
        try writer.finish(startedAt: start, duration: 20, reason: "user_stop")
        // Leave non_work in both current intervals and a historical revision.
        var contract = try RecordingContract.load(from: writer.folder)
        try contract.correctContext(.work, start: 10, end: 15, effectiveAt: start.addingTimeInterval(10),
                                    recordedAt: start.addingTimeInterval(21), actionID: UUID(), expectedRevision: 0)
        try contract.save(to: writer.folder)
        let reminders = writer.folder.appendingPathComponent("reminders.jsonl")
        let study = writer.folder.appendingPathComponent("study_check_ins.jsonl")
        let reminder = "{\"request\":{\"context\":\"non_work\",\"id\":\"non_work\",\"scheduledElapsed\":5.25},\"action\":\"not_working\",\"note\":\"non_work\"}\n"
        // Exercise chunk boundaries, blank lines and a final line without a newline.
        try (String(repeating: reminder, count: 900) + "\n\t\n" + String(reminder.dropLast()))
            .write(to: reminders, atomically: true, encoding: .utf8)
        try "{\"prompt\":{\"contextAtPrompt\":\"non_work\",\"id\":\"non_work\",\"requestedElapsed\":9.5},\"action\":\"answered\",\"note\":{\"context\":\"non_work\"}}"
            .write(to: study, atomically: true, encoding: .utf8)
        let saved = try SavedSession(folder: writer.folder)
        let originals = try snapshot(writer.folder)
        func check(_ copy: URL) throws {
            let exported = try RecordingContract.load(from: copy)
            precondition(exported.intervals.allSatisfy { $0.context != .nonWork })
            precondition(exported.revisions.allSatisfy { $0.previousIntervals.allSatisfy { $0.context != .nonWork } })
            precondition(exported.intervals.map(\.id) == contract.intervals.map(\.id))
            precondition(exported.intervals.map(\.logicalID) == contract.intervals.map(\.logicalID))
            precondition(exported.intervals.map(\.start) == contract.intervals.map(\.start))
            precondition(exported.intervals.map(\.end) == contract.intervals.map(\.end))
            precondition(exported.intervals.map(\.effectiveAtUTC) == contract.intervals.map(\.effectiveAtUTC))
            precondition(exported.intervals.map(\.recordedAtUTC) == contract.intervals.map(\.recordedAtUTC))
            precondition(exported.revisions.map(\.id) == contract.revisions.map(\.id))
            precondition(exported.recordingID == contract.recordingID && exported.observedThrough == contract.observedThrough)
            precondition(exported.intervals.first?.context == .work)
            let lines = try String(contentsOf: copy.appendingPathComponent("reminders.jsonl"), encoding: .utf8)
                .split(separator: "\n").filter { !$0.trimmingCharacters(in: .whitespaces).isEmpty }
            precondition(lines.count == 901)
            for line in lines {
                let object = try JSONSerialization.jsonObject(with: Data(line.utf8)) as! [String: Any]
                let request = object["request"] as! [String: Any]
                precondition(request["context"] as? String == "unknown")
                precondition(request["id"] as? String == "non_work")
                precondition(request["scheduledElapsed"] as? Double == 5.25)
                precondition(object["action"] as? String == "not_working" && object["note"] as? String == "non_work")
            }
            let object = try JSONSerialization.jsonObject(with: Data(contentsOf: copy.appendingPathComponent("study_check_ins.jsonl"))) as! [String: Any]
            let prompt = object["prompt"] as! [String: Any]
            precondition(prompt["contextAtPrompt"] as? String == "unknown" && prompt["id"] as? String == "non_work")
            precondition(prompt["requestedElapsed"] as? Double == 9.5)
            precondition((object["note"] as! [String: Any])["context"] as? String == "non_work")
            for file in ["session.json", "events.csv", "mouse_movement.csv", "breaks.csv", "surveys.csv", "survey_prompts.csv"] {
                try expect(Data(contentsOf: copy.appendingPathComponent(file)) == originals[file])
            }
            try expect(String(contentsOf: copy.appendingPathComponent("export-notes.txt"), encoding: .utf8).contains("Saved originals are unchanged"))
        }
        try check(SessionFiles.exportOriginal(saved, to: exports, root: root, active: nil))
        let selected = try SessionFiles.exportSelectedOriginal([saved], to: exports, root: root, active: nil)
        try check(selected.folder.appendingPathComponent(saved.exportName()))
        let all = try SessionFiles.exportAllOriginal(to: exports, root: root, active: nil)
        try check(all.folder.appendingPathComponent(saved.exportName()))
        try expect(snapshot(writer.folder) == originals)

        // Unchanged logs preserve their exact bytes, including blank lines and CRLF.
        let clean = try RecordingWriter(root: root, id: "clean", startedAt: start.addingTimeInterval(86400), mode: .automatic)
        try clean.changeContext(.work, at: 5, effectiveAt: start, source: .userAction)
        try clean.changeContext(.unknown, at: 10, effectiveAt: start, source: .userAction)
        try clean.finish(startedAt: start.addingTimeInterval(86400), duration: 20, reason: "end_work")
        let cleanLog = " {\"request\":{\"context\":\"unknown\"},\"note\":\"non_work\"} \r\n\r\n"
        try cleanLog.write(to: clean.folder.appendingPathComponent("reminders.jsonl"), atomically: true, encoding: .utf8)
        let cleanSaved = try SavedSession(folder: clean.folder)
        let cleanCopy = try SessionFiles.exportOriginal(cleanSaved, to: exports, root: root, active: nil)
        try expect(String(contentsOf: cleanCopy.appendingPathComponent("reminders.jsonl"), encoding: .utf8) == cleanLog)
        try expect(Data(contentsOf: cleanCopy.appendingPathComponent("context_intervals.json")) == Data(contentsOf: clean.folder.appendingPathComponent("context_intervals.json")))
        let beforeFailure = try FileManager.default.contentsOfDirectory(atPath: exports.path).sorted()
        try "invalid JSON".write(to: study, atomically: true, encoding: .utf8)
        for kind in 0..<3 {
            do {
                switch kind {
                case 0: _ = try SessionFiles.exportOriginal(saved, to: exports, root: root, active: nil)
                case 1: _ = try SessionFiles.exportSelectedOriginal([cleanSaved, saved], to: exports, root: root, active: nil)
                default: _ = try SessionFiles.exportAllOriginal(to: exports, root: root, active: nil)
                }
                preconditionFailure("Malformed logs must fail and remove incomplete exports")
            } catch {}
            try expect(FileManager.default.contentsOfDirectory(atPath: exports.path).sorted() == beforeFailure)
        }
        // Never follow a copied context-log symlink into an unrelated file.
        try FileManager.default.removeItem(at: study)
        let external = temporary.appendingPathComponent("external.jsonl")
        try reminder.write(to: external, atomically: true, encoding: .utf8)
        try FileManager.default.createSymbolicLink(at: study, withDestinationURL: external)
        do {
            _ = try SessionFiles.exportOriginal(saved, to: exports, root: root, active: nil)
            preconditionFailure("Context-log symlinks must fail")
        } catch {}
        try expect(String(contentsOf: external, encoding: .utf8) == reminder)
        try expect(FileManager.default.contentsOfDirectory(atPath: exports.path).sorted() == beforeFailure)
        print("PASS: export-only context normalization, nested revisions, streamed logs, all export paths, unchanged originals and failure cleanup")
    }

    static func snapshot(_ folder: URL) throws -> [String: Data] {
        var result: [String: Data] = [:]
        for file in try FileManager.default.contentsOfDirectory(atPath: folder.path) {
            result[file] = try Data(contentsOf: folder.appendingPathComponent(file))
        }
        return result
    }
}
