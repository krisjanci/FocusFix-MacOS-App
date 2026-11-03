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
        print("PASS: ordinary/upgrade survey-free gating, explicit study scope, missing reviewed config, synthetic cross-context recall snapshots, missing/skip semantics, revoke and rate/quiet limits")
    }
}
