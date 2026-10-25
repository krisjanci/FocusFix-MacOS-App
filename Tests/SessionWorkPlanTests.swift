import Foundation

@main @MainActor
struct SessionWorkPlanTests {
    static func main() {
        let suite = "focusfix.test.plan.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }
        let preferences = SessionWorkPlanPreferences(defaults: defaults)
        precondition(!preferences.enabled && preferences.minutes == 60)
        var disabled = preferences.snapshot
        disabled.credit(3600)
        precondition(disabled.workSeconds == 0 && !disabled.isComplete)
        preferences.enabled = true
        var plan = preferences.snapshot
        preferences.setMinutes(30)
        precondition(plan.targetMinutes == 60 && preferences.snapshot.targetMinutes == 30)
        precondition(!preferences.setMinutes(0) && !preferences.setMinutes(481))
        precondition(preferences.setMinutes(1) && preferences.setMinutes(480))
        precondition(SessionWorkPlanPreferences(defaults: defaults).minutes == 480)
        precondition(SessionWorkPlanPreferences(defaults: defaults).enabled)
        preferences.enabled = false
        precondition(preferences.snapshot.targetMinutes == nil)
        defaults.set(-12, forKey: "focusfix.plan.minutes")
        precondition(SessionWorkPlanPreferences(defaults: defaults).minutes == 60)

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
        preferences.enabled = true
        session = preferences.snapshot // New session, no carryover from the old plan.
        precondition(session.workSeconds == 0 && !session.acknowledged)
        print("Session target boundaries, shared clock, exclusions, snapshots and one-time completion passed")
    }
}
