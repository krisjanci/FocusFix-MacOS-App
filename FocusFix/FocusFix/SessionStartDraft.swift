import Foundation

// Ephemeral choices for one start window. Nothing here reads or writes preferences.
struct SessionStartDraft {
    let asksForFatigue: Bool
    var fatigue: Int?
    var planning = false
    // Zero represents Custom; all other choices are preset minutes.
    var durationChoice = 60
    var customMinutes = "60"

    var targetMinutes: Int? {
        guard planning else { return nil }
        let value = durationChoice == 0 ? Int(customMinutes) : durationChoice
        return value.flatMap { (1...480).contains($0) ? $0 : nil }
    }

    var validPlan: Bool { !planning || targetMinutes != nil }

    mutating func addPlan() {
        planning = true
        durationChoice = 60
        customMinutes = "60"
    }

    mutating func removePlan() {
        planning = false
        durationChoice = 60
        customMinutes = "60"
    }

    func selection(skippingFatigue: Bool = false) -> SessionStartSelection? {
        guard validPlan else { return nil }
        let answer = asksForFatigue && !skippingFatigue ? fatigue : nil
        if asksForFatigue && !skippingFatigue && answer == nil { return nil }
        guard answer.map({ (0...10).contains($0) }) ?? true else { return nil }
        return SessionStartSelection(fatigue: answer, plan: SessionWorkPlan(targetMinutes: targetMinutes))
    }
}

struct SessionStartSelection {
    let fatigue: Int?
    let plan: SessionWorkPlan
}
