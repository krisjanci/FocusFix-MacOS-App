import Foundation

@main @MainActor
struct SessionWorkPlanTests {
    static func main() {
        var draft = SessionStartDraft(asksForFatigue: false)
        precondition(!draft.planning && draft.selection()?.plan.targetMinutes == nil)
        var disabled = draft.selection()!.plan
        disabled.credit(3600)
        precondition(disabled.workSeconds == 0 && !disabled.isComplete)
        draft.addPlan()
        precondition(draft.targetMinutes == 60)
        var plan = draft.selection()!.plan
        precondition(plan.summary == "Planned session · 0 / 60 min")
        draft.durationChoice = 30
        precondition(plan.targetMinutes == 60 && draft.selection()?.plan.targetMinutes == 30)
        draft.durationChoice = 0
        for invalid in ["", "0", "481", "-1", "1.5", "abc"] {
            draft.customMinutes = invalid
            precondition(!draft.validPlan && draft.selection() == nil)
            precondition(draft.selection(skippingFatigue: true) == nil)
        }
        for valid in ["1", "60", "480"] {
            draft.customMinutes = valid
            precondition(draft.validPlan && draft.selection()?.plan.targetMinutes == Int(valid))
        }
        draft.removePlan()
        precondition(draft.selection()?.plan.targetMinutes == nil)
        draft.addPlan()
        precondition(draft.targetMinutes == 60)
        // Dismissal destroys the window's draft; the next attempt starts untargeted.
        draft = SessionStartDraft(asksForFatigue: false)
        precondition(!draft.planning && draft.selection()?.plan.targetMinutes == nil)
        // Survey-disabled starts never supply a survey answer, even if a stale value is set.
        draft.fatigue = 8
        precondition(draft.selection()?.fatigue == nil)
        for asksForFatigue in [false, true] {
            var attempt = SessionStartDraft(asksForFatigue: asksForFatigue)
            attempt.addPlan()
            if asksForFatigue { precondition(attempt.selection() == nil) }
            let skipped = attempt.selection(skippingFatigue: true)!
            precondition(skipped.fatigue == nil && skipped.plan.targetMinutes == 60)
            attempt.fatigue = 7
            let answered = attempt.selection()!
            precondition(answered.fatigue == (asksForFatigue ? 7 : nil))
            precondition(answered.plan.targetMinutes == 60)
            attempt.fatigue = 11
            if asksForFatigue { precondition(attempt.selection() == nil) }
        }

        for minutes in [1, 30, 60, 90, 480] {
            var boundary = SessionWorkPlan(targetMinutes: minutes)
            boundary.credit(Double(minutes * 60) - 0.001)
            precondition(!boundary.isComplete)
            boundary.credit(0.001)
            precondition(boundary.isComplete && boundary.reminderPending)
        }
        plan.credit(3599)
        plan.keepGoing() // Cannot acknowledge a future reminder.
        precondition(!plan.isComplete && !plan.acknowledged)
        plan.credit(1)
        precondition(plan.isComplete && plan.reminderPending)
        plan.keepGoing()
        plan.credit(900)
        precondition(plan.isComplete && !plan.reminderPending && plan.workSeconds == 4500)
        plan.keepGoing()
        plan.credit(.nan); plan.credit(.infinity); plan.credit(-60)
        precondition(plan.workSeconds == 4500)
        precondition(!SessionWorkPlan(targetMinutes: 0).isComplete)
        precondition(!SessionWorkPlan(targetMinutes: 481).isComplete)

        // The same returned credit drives both ledgers, including transitions between ticks.
        var clock = ProgressClock()
        var daily = DailyProgress()
        var session = SessionWorkPlan(targetMinutes: 30)
        let start = Date(timeIntervalSince1970: 1_790_000_000)
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        func update(_ elapsed: Double, working: Bool) {
            session.credit(clock.update(&daily, elapsed: elapsed, date: start.addingTimeInterval(elapsed),
                working: working, calendar: calendar))
        }
        update(0, working: true)
        update(600, working: true) // Quiet reading is ordinary work.
        update(610, working: false) // Settle work before entering a break/check-in/lock.
        update(1200, working: false)
        update(1500, working: false)
        update(1800, working: false)
        update(2100, working: true) // Return does not retroactively credit the exclusion.
        update(3289, working: true)
        precondition(session.workSeconds == 1799 && !session.isComplete)
        update(3290, working: false) // Stop settles the last second using the same clock.
        update(3290, working: false) // Duplicate transition must not award anything twice.
        update(4000, working: false) // Time outside recording remains excluded.
        precondition(session.workSeconds == 1800 && session.reminderPending)
        precondition(daily.days.values.reduce(0) { $0 + $1.workSeconds } == session.workSeconds)
        session = SessionStartDraft(asksForFatigue: false).selection()!.plan // New session, no carryover.
        precondition(session.workSeconds == 0 && !session.acknowledged)
        print("Per-session planning, survey choices, reset, shared work credit and one-time completion passed")
    }
}
