import Foundation

@main struct ContextEditingTests {
    static func main() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let date = Date(timeIntervalSince1970: 0)
        let writer = try RecordingWriter(root: root, id: UUID().uuidString, startedAt: date, mode: .automatic)
        try writer.event(time: 1, type: "left_click_down")
        try writer.changeContext(.work, at: 5, effectiveAt: date.addingTimeInterval(5), source: .userAction)
        let workID = writer.contract.currentWorkPeriodID
        try writer.changeContext(.work, at: 6, effectiveAt: date.addingTimeInterval(6), source: .userAction)
        precondition(writer.contract.intervals.count == 2 && writer.contract.currentWorkPeriodID == workID)
        try writer.changeContext(.nonWork, at: 10, effectiveAt: date.addingTimeInterval(10), source: .userAction)
        try writer.changeContext(.unknown, at: 15, effectiveAt: date.addingTimeInterval(15), source: .userAction)
        try writer.finish(startedAt: date, duration: 20, reason: "end_work")
        precondition(writer.contract.intervals.map(\.context) == [.unknown, .work, .nonWork, .unknown])
        precondition(writer.contract.intervals.map(\.start) == [0, 5, 10, 15])
        let rawURL = writer.folder.appendingPathComponent("events.csv")
        let raw = try Data(contentsOf: rawURL)
        let session = try SavedSession(folder: writer.folder)
        let original = session.recordingContract!
        let action = UUID()
        try SessionFiles.correctContext(.work, start: 2, end: 12, for: session, root: root, active: nil,
                                        actionID: action, expectedRevision: 0)
        let corrected = try RecordingContract.load(from: writer.folder)
        precondition(corrected.revisions.count == 1 && corrected.revisions[0].previousIntervals == original.intervals)
        precondition(corrected.intervals.first!.context == .unknown && corrected.intervals.first!.end == 2)
        precondition(corrected.intervals.last!.context == .unknown)
        let unchanged = try Data(contentsOf: rawURL)
        precondition(raw == unchanged)
        // Repeating an action after a retry cannot create another revision.
        try SessionFiles.correctContext(.work, start: 2, end: 12, for: session, root: root, active: nil,
                                        actionID: action, expectedRevision: 0)
        let retried = try RecordingContract.load(from: writer.folder)
        precondition(retried.revisions.count == 1)
        for bounds in [(-1.0, 2.0), (1, 21), (5, 5), (.nan, 10)] {
            do {
                try SessionFiles.correctContext(.nonWork, start: bounds.0, end: bounds.1, for: session,
                    root: root, active: nil, expectedRevision: 1)
                preconditionFailure("Invalid bounds accepted")
            } catch { }
        }
        do {
            try SessionFiles.correctContext(.unknown, start: 0, end: 2, for: session,
                root: root, active: nil, expectedRevision: 0)
            preconditionFailure("Stale revision accepted")
        } catch { }
        let afterInvalid = try RecordingContract.load(from: writer.folder)
        precondition(afterInvalid == corrected)
        print("PASS: forward-only labels, repeated Start, End/unknown, mixed context, bounded revisions, stale/retried edits and unchanged raw bytes")
    }
}
