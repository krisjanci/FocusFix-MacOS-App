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
        let csv = try RecordingCoverage.csv("a,b,c\n1,\"custom,\nlabel\",3\n")
        precondition(csv.count == 2 && csv[1][1] == "custom,\nlabel")
        precondition(RecordingPresentation.status(state: .recording, mode: .automatic, context: .unknown, phase: .normal) == "Recording automatically · Unknown activity")
        precondition(RecordingPresentation.status(state: .userPaused, mode: .automatic, context: .work, phase: .normal) == "Paused")
        precondition(RecordingPresentation.status(state: .permissionUnavailable, mode: .automatic, context: .unknown, phase: .normal) == "Permission needed")
        print("PASS: mixed-context observed coverage, stationary/absent distinction, breaks/check-ins/gaps, legacy unknown, overlap rejection, multiline CSV and shared UI status")
    }
}
