import Foundation

// Work credit belongs to the current work period, even before a target is chosen.
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
        "Work target · \(Int(min(workSeconds / 60, Double(Int.max / 2)))) / \(targetMinutes ?? 0) min"
    }

    mutating func credit(_ seconds: Double) {
        guard seconds.isFinite, seconds > 0,
              (workSeconds + seconds).isFinite else { return }
        workSeconds += seconds
    }

    // Editing a target keeps work already observed, without crediting it twice.
    mutating func setTarget(_ minutes: Int?) {
        let replacement = SessionWorkPlan(targetMinutes: minutes)
        guard replacement.targetMinutes != targetMinutes else { return }
        let observedWorkSeconds = workSeconds
        self = replacement
        credit(observedWorkSeconds)
    }

    mutating func keepGoing() {
        if isComplete { acknowledged = true }
    }
}
