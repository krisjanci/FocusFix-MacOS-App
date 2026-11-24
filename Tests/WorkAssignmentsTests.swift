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
        // Coverage contains a check-in and an unavailable gap; neither counts as task time.
        for (start, end, phase) in [(0.0, 12.0, "work"), (16, 17, "work"), (17, 18, "check_in"), (18, 19, "work"), (20, 30, "work")] {
            writer.append([MouseSummary(start: start, end: end, distance: 0, events: 0, secondsSinceMovement: nil, activityPhase: phase)])
        }
        try writer.finish(startedAt: started, duration: 30, reason: "test")
        let journal = try WorkAssignmentJournal.load(from: writer.folder)
        let intervals = journal.intervals(in: writer.contract)
        precondition(intervals.map { $0.end - $0.start } == [10, 2, 4, 5])
        precondition(intervals.map(\.assignment) == [a, b, b, .none])
        let saved = try SavedSession(folder: writer.folder)
        precondition(saved.assignedWork.map { $0.end - $0.start } == [10, 2, 1, 1, 5])
        precondition(saved.assignedWork.map(\.assignment) == [a, b, b, b, .none])
        precondition(saved.assignmentNotice == nil)
        // Finishing an assignment ends its attribution, while the work context continues.
        let later = started.addingTimeInterval(60)
        let ongoing = try RecordingWriter(root: root, id: UUID().uuidString, startedAt: later)
        var renamed = a; renamed.projectName = "Renamed project"; renamed.taskTitle = "Renamed task"
        try ongoing.selectAssignment(renamed, at: 0)
        try ongoing.selectAssignment(.none, at: 5)
        precondition(ongoing.contract.intervals.last?.context == .work && !ongoing.contract.finalized)
        try ongoing.selectAssignment(renamed, at: 10)
        try ongoing.selectAssignment(.none, at: 15)
        ongoing.append([MouseSummary(start: 0, end: 20, distance: 0, events: 0, secondsSinceMovement: nil, activityPhase: "work")])
        try ongoing.checkpoint(at: 20)
        let total = try SavedSession.totalTaskWork(project: a.projectID!, task: a.taskID!,
            through: later.addingTimeInterval(20), root: root)
        precondition(total == 20, "Sum prior recordings and repeated task stints, excluding no-project work")
        let clipped = try SavedSession.totalTaskWork(project: a.projectID!, task: a.taskID!,
            through: later.addingTimeInterval(12), root: root)
        precondition(clipped == 17, "A completion must exclude subsequent work even if the same task resumes")
        let otherProject = try SavedSession.totalTaskWork(project: UUID(), task: a.taskID!, through: later, root: root)
        precondition(otherProject == 0)
        try ongoing.finish(startedAt: later, duration: 20, reason: "test")
        let export = fm.temporaryDirectory.appendingPathComponent("assignment-export-\(UUID())", isDirectory: true)
        defer { try? fm.removeItem(at: export) }
        try fm.createDirectory(at: export, withIntermediateDirectories: true)
        let copy = try SessionFiles.export(saved, to: export, root: root, active: nil)
        precondition(fm.fileExists(atPath: copy.appendingPathComponent(WorkAssignmentJournal.filename).path))
        // No names in session.json; upload allowlist excludes the sidecar.
        let metadata = try String(contentsOf: writer.folder.appendingPathComponent("session.json"), encoding: .utf8)
        precondition(!metadata.contains("Private project") && !metadata.contains("Private task"))
        precondition(!DevelopmentArchive.files.contains(WorkAssignmentJournal.filename))
        let upload = try DevelopmentArchive.sources(id: saved.id, root: root)
        precondition(!upload.contains { $0.lastPathComponent == WorkAssignmentJournal.filename })
        let zip = export.appendingPathComponent("shared.zip")
        let consent = DevelopmentConsent(id: UUID(), owner: UUID(), origin: "https://example.invalid", policyVersion: "test", startedAt: started)
        _ = try DevelopmentArchive.prepare(id: saved.id, root: root, consent: consent, destination: zip)
        let unzip = Process(), output = Pipe()
        unzip.executableURL = URL(fileURLWithPath: "/usr/bin/unzip")
        unzip.arguments = ["-p", zip.path]; unzip.standardOutput = output; unzip.standardError = FileHandle.nullDevice
        try unzip.run()
        let payload = String(decoding: output.fileHandleForReading.readDataToEndOfFile(), as: UTF8.self)
        unzip.waitUntilExit()
        precondition(unzip.terminationStatus == 0 && !payload.contains("Private project") && !payload.contains("Private task"))
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
        let sidecar = rotated.folder.appendingPathComponent(WorkAssignmentJournal.filename)
        try fm.removeItem(at: sidecar)
        try fm.createDirectory(at: sidecar, withIntermediateDirectories: false)
        let preserved = rotated.assignments
        // Finalized recordings reject new assignments before any file mutation.
        do { try rotated.selectAssignment(b, at: 41); preconditionFailure("Expected finalized writer failure") } catch { }
        precondition(rotated.assignments == preserved)
        // Renaming/deleting the catalog cannot change frozen assignment snapshots.
        precondition(journal.changes.first?.assignment.projectName == "Private project")
        try fm.removeItem(at: writer.folder.appendingPathComponent(WorkAssignmentJournal.filename))
        let legacy = try SavedSession(folder: writer.folder)
        precondition(legacy.assignedWork.isEmpty)
        let corrupt = writer.folder.appendingPathComponent(WorkAssignmentJournal.filename)
        try Data("broken".utf8).write(to: corrupt)
        let unreadable = try SavedSession(folder: writer.folder)
        precondition(unreadable.assignmentNotice != nil)
        let kept = try String(contentsOf: corrupt, encoding: .utf8)
        precondition(kept == "broken")
        let failingWriter = try RecordingWriter(root: root, id: UUID().uuidString, startedAt: started)
        let blockedSidecar = failingWriter.folder.appendingPathComponent(WorkAssignmentJournal.filename)
        try fm.removeItem(at: blockedSidecar)
        try fm.createDirectory(at: blockedSidecar, withIntermediateDirectories: false)
        let previous = failingWriter.assignments
        do { try failingWriter.selectAssignment(a, at: 1); preconditionFailure("Expected sidecar write failure") } catch { }
        precondition(failingWriter.assignments == previous)
        print("WorkAssignmentsTests passed")
    }
}
