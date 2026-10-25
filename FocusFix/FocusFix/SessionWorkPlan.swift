import Foundation

// A session owns a value snapshot. Later start-window edits cannot change an active plan.
struct SessionWorkPlan: Equatable {
    let targetMinutes: Int?
    private(set) var workSeconds: Double = 0
    private(set) var acknowledged = false

    init(targetMinutes: Int? = nil) {
        self.targetMinutes = targetMinutes.flatMap { (1...480).contains($0) ? $0 : nil }
    }

    var isComplete: Bool { targetMinutes.map { workSeconds >= Double($0) * 60 } ?? false }
    var reminderPending: Bool { isComplete && !acknowledged }
    var summary: String {
        "Planned session · \(Int(min(workSeconds / 60, Double(Int.max / 2)))) / \(targetMinutes ?? 0) min"
    }

    mutating func credit(_ seconds: Double) {
        guard targetMinutes != nil, seconds.isFinite, seconds > 0,
              (workSeconds + seconds).isFinite else { return }
        workSeconds += seconds
    }

    mutating func keepGoing() {
        if isComplete { acknowledged = true }
    }
}
