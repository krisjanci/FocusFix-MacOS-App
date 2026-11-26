import Foundation

@main struct RecordingCoverageTests {
    static func main() throws {
        let date = Date(timeIntervalSince1970: 0)
        var contract = RecordingContract(mode: .automatic, startedAt: date)
        try contract.changeContext(.work, at: 5, effectiveAt: date, recordedAt: date, source: .userAction)
        try contract.changeContext(.nonWork, at: 10, effectiveAt: date, recordedAt: date, source: .userAction)
        try contract.finish(at: 20)
        let summary = try RecordingCoverage(origin: 0, end: 20, labels: contract.intervals,
            observations: [.init(start: 0, end: 8, phase: .normal), .init(start: 8, end: 10, phase: .checkIn),
                           .init(start: 10, end: 12, phase: .normal), .init(start: 15, end: 17, phase: .normal)],
            breaks: [.init(start: 12, end: 15, phase: .explicitBreak)])
        precondition(summary.unknown == 5 && summary.work == 3 && summary.nonWork == 4)
        precondition(summary.explicitBreak == 3 && summary.checkInOrAwaitingReturn == 2 && summary.unavailable == 3)
        let legacy = try RecordingCoverage(origin: 0, end: 10, labels: [], observations: [.init(start: 0, end: 3, phase: .normal)], breaks: [])
        precondition(legacy.unknown == 3 && legacy.work == 0 && legacy.unavailable == 7)
        let missing = try RecordingCoverage(origin: 0, end: 20, labels: contract.intervals, observations: [], breaks: [])
        precondition(missing.work == 0 && missing.unavailable == 20)
        do {
            _ = try RecordingCoverage(origin: 0, end: 20, labels: contract.intervals,
                observations: [.init(start: 0, end: 5, phase: .normal), .init(start: 4, end: 7, phase: .normal)], breaks: [])
            preconditionFailure("Overlapping coverage accepted")
        } catch { }
        // New recordings use exact merged coverage, never rounded measurement rows.
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("coverage-\(UUID())")
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        var observed = ObservedCoverage()
        observed.append(start: 0.125, end: 1.125, phase: .normal)
        observed.append(start: 1.125, end: 1.25, phase: .normal)
        observed.append(start: 1.25, end: 2.25, phase: .checkIn)
        observed.append(start: 3.125, end: 4.125, phase: .normal) // Capture gap must remain.
        observed.append(start: 4.125, end: 5.125, phase: .awaitingReturn)
        precondition(observed.intervals.count == 4 && observed.intervals[0].end == 1.25)
        try observed.save(to: root)
        let decoded = try JSONDecoder().decode(ObservedCoverage.self, from: Data(contentsOf: root.appendingPathComponent(ObservedCoverage.filename)))
        let slices = try decoded.slices(origin: 0, through: 4.75)
        precondition(slices.count == 4 && slices.last?.end == 4.75) // Ignore uncheckpointed tail.
        var manual = RecordingContract(mode: .manual, startedAt: date)
        try manual.finish(at: 4.75)
        try manual.save(to: root)
        func metadata(_ version: Int) throws {
            let fields: [String: Any] = ["schema_version": version, "recording_format": "focusfix.recording.v\(version)",
                "required_capabilities": RecordingContract.capabilities(for: version), "status": "test", "duration_seconds": 4.75,
                "recording_id": manual.recordingID.uuidString, "segment_id": manual.segmentID.uuidString, "recording_mode": "manual"]
            try JSONSerialization.data(withJSONObject: fields).write(to: root.appendingPathComponent("session.json"))
        }
        try metadata(12)
        // Invalid rounded bounds are intentionally ignored by the coverage reader.
        try Data("start_seconds,end_seconds\n0,0\n".utf8).write(to: root.appendingPathComponent("mouse_movement.csv"))
        let expectedCoverage = try RecordingCoverage(origin: 0, end: 4.75, labels: manual.intervals, observations: slices, breaks: [])
        let newCoverage = try RecordingCoverage.load(session: SavedSession(folder: root))
        precondition(newCoverage == expectedCoverage)
        let contractURL = root.appendingPathComponent("context_intervals.json")
        let v12 = try String(contentsOf: contractURL, encoding: .utf8)
        try v12.replacingOccurrences(of: "focusfix.recording.v12", with: "focusfix.recording.v11").write(to: contractURL, atomically: true, encoding: .utf8)
        try metadata(11)
        let legacyCSV = "start_seconds,end_seconds,activity_phase\n0.125,1.25,work\n1.25,2.25,check_in\n3.125,4.125,work\n4.125,5.125,awaiting_return\n"
        try legacyCSV.write(to: root.appendingPathComponent("mouse_movement.csv"), atomically: true, encoding: .utf8)
        let oldCoverage = try RecordingCoverage.load(session: SavedSession(folder: root))
        precondition(oldCoverage == expectedCoverage)
        try v12.write(to: contractURL, atomically: true, encoding: .utf8)
        try metadata(12)
        try FileManager.default.removeItem(at: root.appendingPathComponent(ObservedCoverage.filename))
        do { _ = try RecordingCoverage.load(session: SavedSession(folder: root)); preconditionFailure("Missing exact coverage silently credited rounded data") } catch { }
        let csv = try RecordingCoverage.csv("a,b,c\n1,\"custom,\nlabel\",3\n")
        precondition(csv.count == 2 && csv[1][1] == "custom,\nlabel")
        precondition(RecordingPresentation.status(state: .recording, mode: .automatic, context: .unknown, phase: .normal) == "Recording automatically · Unknown activity")
        precondition(RecordingPresentation.status(state: .userPaused, mode: .automatic, context: .work, phase: .normal) == "Paused")
        precondition(RecordingPresentation.status(state: .permissionUnavailable, mode: .automatic, context: .unknown, phase: .normal) == "Permission needed")
        print("PASS: mixed-context observed coverage, stationary/absent distinction, breaks/check-ins/gaps, legacy unknown, overlap rejection, multiline CSV and shared UI status")
    }
}
