import Foundation

@main struct RecordingContractTests {
    static func rejects(_ operation: () throws -> Void) {
        do { try operation(); preconditionFailure("Expected invalid contract to be rejected") } catch { }
    }
    static func main() throws {
        let date = Date(timeIntervalSince1970: 100)
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        var automatic = RecordingContract(mode: .automatic, startedAt: date)
        precondition(automatic.intervals[0].context == .unknown && automatic.intervals[0].context != .nonWork)
        precondition(InterventionPhase(legacyPhase: "work") == .normal)
        precondition(InterventionPhase(legacyPhase: "resting") == .explicitBreak)
        try automatic.observe(through: 10)
        try automatic.save(to: root)
        let loaded = try RecordingContract.load(from: root)
        precondition(loaded == automatic)
        rejects { try automatic.observe(through: 9) }
        rejects { try automatic.observe(through: .nan) }
        try automatic.finish(at: 12)
        try automatic.save(to: root)
        precondition(automatic.intervals[0].end == 12 && automatic.finalized)
        let finalized = try RecordingContract.load(from: root)
        precondition(finalized == automatic)
        rejects { try automatic.observe(through: 13) }
        var overlap = automatic
        overlap.intervals.append(overlap.intervals[0])
        rejects { try overlap.validate() }
        var badBounds = automatic
        badBounds.intervals[0].end = 13
        rejects { try badBounds.validate() }
        var open = automatic
        open.intervals[0].end = nil
        rejects { try open.validate() }
        // Earlier local additive snapshots used ISO UTC strings and omitted the new origin/zone.
        let url = root.appendingPathComponent("context_intervals.json")
        var old = try JSONSerialization.jsonObject(with: Data(contentsOf: url)) as! [String: Any]
        old.removeValue(forKey: "elapsedOrigin"); old.removeValue(forKey: "scoringTimeZone")
        var labels = old["intervals"] as! [[String: Any]]
        labels[0]["effectiveAtUTC"] = "1970-01-01T00:01:40Z"
        labels[0]["recordedAtUTC"] = "1970-01-01T00:01:40Z"
        old["intervals"] = labels
        let oldBytes = try JSONSerialization.data(withJSONObject: old)
        try oldBytes.write(to: url)
        let compatible = try RecordingContract.load(from: root)
        precondition(compatible.elapsedOrigin == 0 && compatible.scoringTimeZone == "UTC")
        precondition(compatible.intervals[0].effectiveAtUTC == date)
        let kept = try Data(contentsOf: url)
        precondition(kept == oldBytes)
        var manual = RecordingContract(mode: .manual, startedAt: date)
        precondition(manual.intervals[0].context == .work && manual.intervals[0].source == .manualStart)
        try manual.finish(at: 0)
        precondition(manual.intervals.isEmpty)
        print("PASS: context round-trip, separate phase/context, half-open bounds, malformed/overlapping rejection and monotonic elapsed validation")
    }
}
