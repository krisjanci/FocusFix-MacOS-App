import Foundation

@main struct StudyCheckInTests {
    @MainActor static func main() throws {
        let suite = "focusfix.study.synthetic.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }
        defaults.set(true, forKey: "focusfix.surveys.beforeSession")
        defaults.set(true, forKey: "focusfix.surveys.beforeBreak")
        defaults.set(true, forKey: "focusfix.surveys.duringWork")
        let disabled = SurveyOptions(beforeSession: false, beforeBreak: false, duringWork: false)
        let ordinary = SurveyPreferences(defaults: defaults)
        precondition(ordinary.snapshot == disabled) // Old switches and sharing cannot activate a new scope.
        ordinary.setStudyCheckInsEnabled(true)
        precondition(ordinary.snapshot == disabled) // No reviewed configuration.
        let refusedSynthetic = SurveyPreferences(defaults: defaults, configuration: .synthetic)
        precondition(refusedSynthetic.snapshot == disabled)
        let demo = SurveyPreferences(defaults: defaults, configuration: .synthetic, allowSynthetic: true)
        precondition(demo.snapshot == disabled)
        demo.setStudyCheckInsEnabled(true)
        precondition(demo.snapshot == SurveyOptions())
        var revoked = false
        demo.onRevoke = { revoked = true }
        demo.setStudyCheckInsEnabled(false)
        precondition(revoked && demo.snapshot == disabled)
        var calendar = Calendar(identifier: .gregorian); calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        let noon = ISO8601DateFormatter().date(from: "2026-11-02T12:00:00Z")!
        var budget = StudyPromptBudget()
        precondition(budget.request(at: noon, configuration: .synthetic, calendar: calendar))
        precondition(!budget.request(at: noon.addingTimeInterval(599), configuration: .synthetic, calendar: calendar))
        precondition(!budget.request(at: noon.addingTimeInterval(-60), configuration: .synthetic, calendar: calendar))
        for index in 1..<6 { precondition(budget.request(at: noon.addingTimeInterval(Double(index) * 600), configuration: .synthetic, calendar: calendar)) }
        precondition(!budget.request(at: noon.addingTimeInterval(3600), configuration: .synthetic, calendar: calendar))
        precondition(budget.request(at: noon.addingTimeInterval(86401), configuration: .synthetic, calendar: calendar))
        let quiet = ISO8601DateFormatter().date(from: "2026-11-04T01:00:00Z")!
        precondition(!budget.eligible(at: quiet, configuration: .synthetic, calendar: calendar))
        try demo.saveBudget(budget)
        precondition(demo.loadBudget().requests == budget.requests)
        defaults.set(Data("broken".utf8), forKey: "focusfix.studyCheckIns.budget")
        precondition(!demo.loadBudget().eligible(at: noon, configuration: .synthetic, calendar: calendar))
        for context in [ActivityContext.work, .nonWork, .unknown] {
            let prompt = StudyPromptSnapshot(id: UUID().uuidString, scheduleVersion: StudyCheckInConfiguration.synthetic.version,
                configurationScope: .synthetic, recordingID: UUID(), contextAtPrompt: context,
                requestedElapsed: 600, recallStart: 300, recallEnd: 600, requestedAtUTC: noon)
            let encoder = JSONEncoder(); encoder.dateEncodingStrategy = .secondsSince1970
            let decoder = JSONDecoder(); decoder.dateDecodingStrategy = .secondsSince1970
            let loaded = try decoder.decode(StudyPromptSnapshot.self, from: encoder.encode(prompt))
            precondition(loaded == prompt && loaded.recallEnd == loaded.requestedElapsed)
        }
        // Personal check-ins are explicit, separate from reviewed-study enrollment.
        let personal = SurveyPreferences(defaults: defaults)
        precondition(!personal.personalSurveysEnabled && personal.promptsPerDay == 2)
        var changes = 0
        personal.onPersonalChange = { changes += 1 }
        personal.setPersonalSurveysEnabled(true)
        precondition(personal.activeConfiguration?.scope == .personal)
        precondition(personal.snapshot == SurveyOptions(beforeSession: false, beforeBreak: false, duringWork: true))
        personal.setPromptsPerDay(99)
        precondition(personal.promptsPerDay == 5 && changes == 2)
        let restored = SurveyPreferences(defaults: defaults)
        precondition(restored.personalSurveysEnabled && restored.promptsPerDay == 5)
        personal.setPromptsPerDay(-1)
        precondition(personal.promptsPerDay == 1)
        personal.setPersonalSurveysEnabled(false)
        precondition(personal.activeConfiguration == nil && personal.snapshot == disabled)

        // Every slider setting and random extreme preserves the spacing and day bounds.
        let midnight = calendar.startOfDay(for: noon)
        for count in 1...5 {
            for draw in [0.0, 0.5, 0.999999] {
                let plan = PersonalSurveySchedule.make(at: noon, target: count, requests: [], calendar: calendar, random: { draw })
                precondition(plan.dates.count == count)
                precondition(plan.dates.allSatisfy { $0 > noon && $0 < midnight.addingTimeInterval(86400) })
                for pair in zip(plan.dates, plan.dates.dropFirst()) { precondition(pair.1.timeIntervalSince(pair.0) >= 1800) }
            }
        }
        // A restart preserves the randomized plan; late opportunities coalesce.
        personal.setPromptsPerDay(5)
        let emptyBudget = StudyPromptBudget()
        let plan = try personal.personalSchedule(at: noon, budget: emptyBudget, calendar: calendar)
        let restartPlan = try restored.personalSchedule(at: noon.addingTimeInterval(60), budget: emptyBudget, calendar: calendar)
        precondition(plan.dates == restartPlan.dates)
        var latePlan = plan
        latePlan.requested(at: plan.dates[2])
        precondition(latePlan.dates == Array(plan.dates.suffix(2)))
        try personal.savePersonalSchedule(latePlan)
        let consumedPlan = try personal.personalSchedule(at: noon, budget: emptyBudget, calendar: calendar)
        precondition(consumedPlan.dates == latePlan.dates)

        // Actual requests enforce the selected daily cap and 30-minute gap,
        // including midnight, relaunch, late delivery and a slider increase.
        var personalBudget = StudyPromptBudget()
        let one = StudyCheckInConfiguration.personal(promptsPerDay: 1)
        let five = StudyCheckInConfiguration.personal(promptsPerDay: 5)
        precondition(personalBudget.request(at: noon, configuration: one, calendar: calendar))
        precondition(!personalBudget.request(at: noon.addingTimeInterval(1799), configuration: five, calendar: calendar))
        precondition(!personalBudget.request(at: noon.addingTimeInterval(1800), configuration: one, calendar: calendar))
        precondition(personalBudget.request(at: noon.addingTimeInterval(1800), configuration: five, calendar: calendar))
        let reduced = PersonalSurveySchedule.make(at: noon.addingTimeInterval(1801), target: 1,
            requests: personalBudget.requests, calendar: calendar)
        precondition(reduced.dates.isEmpty)
        let increased = PersonalSurveySchedule.make(at: noon.addingTimeInterval(1801), target: 5,
            requests: personalBudget.requests, calendar: calendar)
        precondition(increased.dates.count == 3 && increased.dates[0].timeIntervalSince(personalBudget.requests.last!) >= 1800)
        var overnight = StudyPromptBudget()
        let nearMidnight = midnight.addingTimeInterval(86400 - 600)
        precondition(overnight.request(at: nearMidnight, configuration: one, calendar: calendar))
        precondition(!overnight.request(at: nearMidnight.addingTimeInterval(1799), configuration: one, calendar: calendar))
        precondition(overnight.request(at: nearMidnight.addingTimeInterval(1800), configuration: one, calendar: calendar))
        for index in 2..<5 {
            precondition(personalBudget.request(at: noon.addingTimeInterval(Double(index) * 1800), configuration: five, calendar: calendar))
        }
        precondition(!personalBudget.request(at: noon.addingTimeInterval(9000), configuration: five, calendar: calendar))
        try personal.saveBudget(personalBudget)
        precondition(!restored.loadBudget().eligible(at: noon.addingTimeInterval(10800), configuration: five, calendar: calendar))
        let earlyDraw = PersonalSurveySchedule.make(at: noon, target: 2, requests: [], calendar: calendar, random: { 0.1 })
        let lateDraw = PersonalSurveySchedule.make(at: noon, target: 2, requests: [], calendar: calendar, random: { 0.9 })
        precondition(earlyDraw.dates != lateDraw.dates)
        // The production timer policy requests a scheduled opportunity just once.
        var timer = TimedCheckInPolicy()
        let due = earlyDraw.next!.timeIntervalSince(noon)
        _ = timer.schedule(from: 0, delay: due)
        precondition(timer.tick(at: due - 1, canPrompt: true) == nil)
        precondition(timer.tick(at: due, canPrompt: false) == nil)
        precondition(timer.tick(at: due + 60, canPrompt: true) != nil)
        precondition(timer.tick(at: due + 120, canPrompt: true) == nil)
        _ = timer.finish()
        precondition(timer.current == nil)
        let packed = PersonalSurveySchedule.make(at: midnight.addingTimeInterval(86370), target: 5,
            requests: [], calendar: calendar)
        precondition(packed.dates.isEmpty)
        // DST uses calendar-day boundaries rather than assuming all days last 24 hours.
        var eastern = calendar; eastern.timeZone = TimeZone(identifier: "America/New_York")!
        for stamp in ["2026-03-08T06:00:00Z", "2026-11-01T05:00:00Z"] {
            let date = ISO8601DateFormatter().date(from: stamp)!
            let dstPlan = PersonalSurveySchedule.make(at: date, target: 5, requests: [], calendar: eastern)
            precondition(dstPlan.dates.count == 5 && dstPlan.dates.allSatisfy { eastern.isDate($0, inSameDayAs: date) })
        }
        // On the 25-hour fall-back day, earlier same-day requests still count.
        let fallStart = ISO8601DateFormatter().date(from: "2026-11-01T04:00:00Z")!
        var longDayBudget = StudyPromptBudget()
        for offset in [0.0, 1800, 3600, 5400, 87000] {
            precondition(longDayBudget.request(at: fallStart.addingTimeInterval(offset), configuration: five, calendar: eastern))
        }
        precondition(!longDayBudget.eligible(at: fallStart.addingTimeInterval(88800), configuration: five, calendar: eastern))
        print("PASS: ordinary/upgrade survey-free gating, explicit study scope, missing reviewed config, synthetic cross-context recall snapshots, missing/skip semantics, revoke, rate/quiet limits, personal 1–5 controls, randomized persistent schedules, daily caps, 30-minute gaps and DST")
    }
}
