import Foundation

// Private local metadata. Never add this sidecar to recording upload allowlists.
nonisolated struct WorkAssignment: Codable, Hashable {
    var projectID: UUID?
    var projectName: String?
    var projectColor: String?
    var taskID: UUID?
    var taskTitle: String?
    static let none = WorkAssignment()
    var summary: String {
        guard let projectName else { return "No project" }
        return "\(projectName) · \(taskTitle ?? "Untasked Work")"
    }
}

nonisolated struct AssignmentChange: Codable, Hashable {
    let elapsed: Double
    let assignment: WorkAssignment
}
nonisolated struct AssignmentBreak: Codable, Hashable {
    let id: String
    let start: Double
    var end: Double?
}
nonisolated struct AssignedWorkInterval: Hashable {
    let start: Double
    let end: Double
    let assignment: WorkAssignment
}
nonisolated struct WorkAssignmentJournal: Codable, Hashable {
    static let filename = "work_assignments.json"
    var changes: [AssignmentChange] = []
    var breaks: [AssignmentBreak] = []

    mutating func select(_ assignment: WorkAssignment, at time: Double) throws {
        guard time.isFinite, time >= 0, time >= (changes.last?.elapsed ?? 0) else { throw RecordingContract.Invalid.bounds }
        if changes.last?.assignment == assignment { return }
        if changes.last?.elapsed == time { changes.removeLast() }
        changes.append(AssignmentChange(elapsed: time, assignment: assignment))
    }

    mutating func recordBreak(id: String, start: Double, end: Double?) {
        if let index = breaks.firstIndex(where: { $0.id == id }) { breaks[index].end = end }
        else { breaks.append(AssignmentBreak(id: id, start: start, end: end)) }
    }

    func save(to folder: URL) throws {
        try JSONEncoder().encode(self).write(to: folder.appendingPathComponent(Self.filename), options: .atomic)
    }
    static func load(from folder: URL) throws -> Self {
        let journal = try JSONDecoder().decode(Self.self, from: SessionStorage.data(filename, in: folder))
        var previous = -Double.infinity
        for change in journal.changes {
            guard change.elapsed.isFinite, change.elapsed >= 0, change.elapsed > previous else { throw RecordingContract.Invalid.bounds }
            previous = change.elapsed
        }
        for item in journal.breaks {
            guard item.start.isFinite, item.start >= 0,
                  item.end.map({ $0.isFinite && $0 >= item.start }) ?? true else { throw RecordingContract.Invalid.bounds }
        }
        return journal
    }

    // Intersect with durable observed work; never attribute downtime, Unknown, or breaks.
    func intervals(in contract: RecordingContract, observedWork: [(start: Double, end: Double)]? = nil) -> [AssignedWorkInterval] {
        var result: [AssignedWorkInterval] = []
        for (index, change) in changes.enumerated() {
            let limit = index + 1 < changes.count ? changes[index + 1].elapsed : contract.observedThrough
            for context in contract.intervals where context.context == .work {
                let start = max(change.elapsed, context.start, contract.elapsedOrigin)
                let end = min(limit, context.end ?? contract.observedThrough, contract.observedThrough)
                guard end > start else { continue }
                var slices = [(start, end)]
                for pause in breaks {
                    slices = slices.flatMap { a, b -> [(Double, Double)] in
                        let x = max(a, pause.start), y = min(b, pause.end ?? contract.observedThrough)
                        guard y > x else { return [(a, b)] }
                        return [(a, x), (y, b)].filter { $0.1 > $0.0 }
                    }
                }
                result += slices.map { AssignedWorkInterval(start: $0.0, end: $0.1, assignment: change.assignment) }
            }
        }
        if let observedWork {
            result = result.flatMap { interval in
                observedWork.compactMap { observed in
                    let start = max(interval.start, observed.start), end = min(interval.end, observed.end)
                    return end > start ? AssignedWorkInterval(start: start, end: end, assignment: interval.assignment) : nil
                }
            }
        }
        var merged: [AssignedWorkInterval] = []
        for interval in result {
            if let last = merged.last, last.assignment == interval.assignment, last.end == interval.start {
                merged[merged.count - 1] = AssignedWorkInterval(start: last.start, end: interval.end, assignment: last.assignment)
            } else { merged.append(interval) }
        }
        return merged
    }
}
