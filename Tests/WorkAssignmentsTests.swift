import Foundation

@main struct WorkAssignmentsTests {
    static func main() throws {
        let fm = FileManager.default
        let root = fm.temporaryDirectory.appendingPathComponent("assignment-tests-\(UUID())")
        try fm.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? fm.removeItem(at: root) }
        let started = Date()
        let a = WorkAssignment(projectID: UUID(), projectName: "Private project", projectColor: "#168B80", taskID: UUID(), taskTitle: "Private task")
        var b = a; b.taskID = nil; b.taskTitle = nil
        let writer = try RecordingWriter(root: root, id: UUID().uuidString, startedAt: started)
        try writer.selectAssignment(a, at: 0)
        try writer.selectAssignment(b, at: 10)
        var pause = BreakRecord(id: "break", promptID: "", start: 12, plannedSeconds: 4, plannedActivity: "Rest", actualActivity: "", end: nil)
        try writer.logBreak(BreakLogEntry(time: 12, action: "break_start", promptID: "", record: pause, nextEligible: nil, sinceLastBreak: 12))
        try writer.checkpoint(at: 15)
        let duringBreak = try WorkAssignmentJournal.load(from: writer.folder).intervals(in: writer.contract)
        precondition(duringBreak.reduce(0) { $0 + $1.end - $1.start } == 12)
        pause.end = 16
        try writer.logBreak(BreakLogEntry(time: 16, action: "break_end", promptID: "", record: pause, nextEligible: nil, sinceLastBreak: 0))
        try writer.changeContext(.unknown, at: 20, effectiveAt: started, source: .userAction)
        try writer.changeContext(.work, at: 25, effectiveAt: started, source: .userAction)
        try writer.selectAssignment(.none, at: 25)
        try writer.finish(startedAt: started, duration: 30, reason: "test")
        let journal = try WorkAssignmentJournal.load(from: writer.folder)
        let intervals = journal.intervals(in: writer.contract)
        precondition(intervals.map { $0.end - $0.start } == [10, 2, 4, 5])
        precondition(intervals.map(\.assignment) == [a, b, b, .none])
        let saved = try SavedSession(folder: writer.folder)
        precondition(saved.assignedWork == intervals && saved.assignmentNotice == nil)
        let export = root.appendingPathComponent("export", isDirectory: true)
        try fm.createDirectory(at: export, withIntermediateDirectories: true)
        let copy = try SessionFiles.export(saved, to: export, root: root, active: nil)
        precondition(fm.fileExists(atPath: copy.appendingPathComponent(WorkAssignmentJournal.filename).path))
        // No names in session.json; upload allowlist excludes the sidecar.
        let metadata = try String(contentsOf: writer.folder.appendingPathComponent("session.json"), encoding: .utf8)
        precondition(!metadata.contains("Private project") && !metadata.contains("Private task"))
        precondition(!DevelopmentArchive.files.contains(WorkAssignmentJournal.filename))
        let upload = try DevelopmentArchive.sources(id: saved.id, root: root)
        precondition(!upload.contains { $0.lastPathComponent == WorkAssignmentJournal.filename })
        // An uncheckpointed choice cannot manufacture time during crash recovery.
        var crash = journal
        try crash.select(a, at: 100)
        precondition(crash.intervals(in: writer.contract) == intervals)
        // Segment continuation uses logical elapsed time and clips at the new origin.
        let next = RecordingContract(recordingID: writer.contract.recordingID, mode: .manual, startedAt: started,
                                     elapsedOrigin: 30, continuing: writer.contract.intervals.last)
        let rotated = try RecordingWriter(root: root, id: UUID().uuidString, startedAt: started, continuingContract: next)
        try rotated.selectAssignment(a, at: 30)
        try rotated.finish(startedAt: started, duration: 40, reason: "test")
        precondition(rotated.assignments.intervals(in: rotated.contract) == [AssignedWorkInterval(start: 30, end: 40, assignment: a)])
        // Renaming/deleting the catalog cannot change frozen assignment snapshots.
        precondition(journal.changes.first?.assignment.projectName == "Private project")
        try fm.removeItem(at: writer.folder.appendingPathComponent(WorkAssignmentJournal.filename))
        precondition(try SavedSession(folder: writer.folder).assignedWork.isEmpty)
        print("WorkAssignmentsTests passed")
    }
}
