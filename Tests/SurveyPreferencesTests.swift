import Foundation

@main
struct SurveyPreferencesTests {
    @MainActor
    static func main() throws {
        // Isolated settings and synthetic recordings; never touch the user's preferences or sessions.
        let suite = "focusfix.test.surveys.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let preferences = SurveyPreferences(defaults: defaults)
        precondition(preferences.snapshot == SurveyOptions())

        for mask in 0..<8 {
            preferences.beforeSession = mask & 1 != 0
            preferences.beforeBreak = mask & 2 != 0
            preferences.duringWork = mask & 4 != 0
            let snapshot = preferences.snapshot
            precondition(SurveyPreferences(defaults: defaults).snapshot == snapshot)
            precondition(snapshot.isEnabled(for: .sessionStart) == preferences.beforeSession)
            precondition(snapshot.isEnabled(for: .beforeBreak) == preferences.beforeBreak)
            precondition(snapshot.isEnabled(for: .duringWork) == preferences.duringWork)

            // A live session retains its own choices even if the profile switches change.
            preferences.beforeSession.toggle()
            preferences.beforeBreak.toggle()
            preferences.duringWork.toggle()
            precondition(snapshot.beforeSession == (mask & 1 != 0))
            precondition(snapshot.beforeBreak == (mask & 2 != 0))
            precondition(snapshot.duringWork == (mask & 4 != 0))

            var policy = TimedCheckInPolicy()
            for (start, reference) in [(0.0, ""), (900.0, "break-1")] {
                let opportunity = policy.scheduleIfEnabled(from: start, afterBreak: reference, options: snapshot)
                precondition((opportunity != nil) == snapshot.duringWork)
                precondition(policy.tick(at: start + 599, canPrompt: true) == nil)
                let requested = policy.tick(at: start + 600, canPrompt: true)
                precondition((requested != nil) == snapshot.duringWork)
                if snapshot.duringWork { precondition(requested?.referenceBreakID == reference) }
                precondition(policy.tick(at: start + 1200, canPrompt: true) == nil)
            }

            let now = Date()
            let writer = try RecordingWriter(root: root, id: "test-\(mask)", startedAt: now, surveyOptions: snapshot)
            let contexts: [CheckInContext] = [.sessionStart, .beforeBreak, .duringWork]
            for context in contexts {
                try writer.logSurvey(SurveyEntry(id: UUID().uuidString, context: context, status: .answered,
                    breakID: "", shownAt: now, answeredAt: now, shownElapsed: 0, answeredElapsed: 0,
                    fatigue: 3, productivity: context == .sessionStart ? nil : 6))
            }
            let syntheticPrompt = policy.schedule(from: 0)
            try writer.logSurveyPrompt(SurveyPromptEntry(item: syntheticPrompt, action: "scheduled", time: 0))
            try writer.finish(startedAt: now, duration: 1800, reason: "test")
            let metadata = try JSONSerialization.jsonObject(with: Data(contentsOf: writer.folder.appendingPathComponent("session.json"))) as! [String: Any]
            precondition(metadata["survey_options"] as? [String: Bool] == snapshot.metadata)
            let answers = try String(contentsOf: writer.folder.appendingPathComponent("surveys.csv"), encoding: .utf8)
            precondition(answers.split(separator: "\n").count == 1 + contexts.filter { snapshot.isEnabled(for: $0) }.count)
            let prompts = try String(contentsOf: writer.folder.appendingPathComponent("survey_prompts.csv"), encoding: .utf8)
            precondition(prompts.split(separator: "\n").count == (snapshot.duringWork ? 2 : 1))
        }
        // Disabling a new schedule must also clear any previous opportunity.
        var policy = TimedCheckInPolicy()
        _ = policy.schedule(from: 0)
        precondition(policy.scheduleIfEnabled(from: 10, options: SurveyOptions(duringWork: false)) == nil)
        precondition(policy.current == nil && policy.tick(at: 1000, canPrompt: true) == nil)
        print("Survey preferences: all eight combinations, persistence, snapshots, scheduling and saved data passed.")
    }
}
