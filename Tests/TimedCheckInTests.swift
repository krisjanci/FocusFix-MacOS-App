import Foundation

@main
struct TimedCheckInTests {
    static func main() throws {
        var policy = TimedCheckInPolicy()
        precondition(policy.tick(at: 999, canPrompt: true) == nil)
        let first = policy.schedule(from: 0)
        precondition(first.due == 600 && first.referenceBreakID.isEmpty)
        precondition(!policy.hasPending)
        precondition(policy.open(token: first.id, at: 50) == nil)
        precondition(policy.tick(at: 599.99, canPrompt: true) == nil)
        precondition(policy.tick(at: 600, canPrompt: false) == nil)
        let requested = policy.tick(at: 602, canPrompt: true)!
        precondition(requested.id == first.id && requested.requestedAt == 602)
        precondition(requested.due == 600 && policy.hasPending)
        precondition(policy.tick(at: 1200, canPrompt: true) == nil) // Not every 10 minutes.
        precondition(policy.open(token: "stale", at: 605) == nil)
        precondition(policy.open(token: first.id, at: 601) == nil)
        let opened = policy.open(token: first.id, at: 610)!
        precondition(opened.openedAt == 610)
        precondition(policy.open(token: first.id, at: 611) == nil)
        let answered = policy.finish()!
        precondition(answered.id == first.id)
        precondition(policy.finish() == nil && !policy.hasPending)
        precondition(policy.tick(at: 1800, canPrompt: true) == nil)

        // An early break cancels the old schedule; return starts a fresh ten minutes.
        _ = policy.schedule(from: 0)
        _ = policy.finish()
        precondition(policy.tick(at: 600, canPrompt: true) == nil)
        let next = policy.schedule(from: 780, afterBreak: "break-1")
        precondition(next.due == 1380 && next.id != first.id)
        precondition(policy.tick(at: 1379, canPrompt: true) == nil)
        precondition(policy.tick(at: 1380, canPrompt: true)?.referenceBreakID == "break-1")
        precondition(policy.open(token: first.id, at: 1381) == nil)
        _ = policy.finish() // Skip without opening.
        precondition(policy.tick(at: 2000, canPrompt: true) == nil)

        // Test actual return, not planned break expiry, with the existing break policy.
        var breaks = BreakPolicy()
        _ = breaks.begin(at: 100, seconds: 300, activity: "Walk")
        _ = breaks.tick(at: 400)
        precondition(breaks.phase == .awaitingReturn)
        precondition(policy.current == nil)
        let returned = breaks.finish(at: 520, reason: "explicit_return")!
        let afterReturn = policy.schedule(from: returned.time, afterBreak: returned.record!.id)
        precondition(afterReturn.due == 1120) // Not 1000 (timer expiry + 600).
        // Break reminder Skip/Snooze only changes the break policy, not this due time.
        let savedDue = policy.current!.due
        var reminders = BreakPolicy(workDelay: 0)
        reminders.input(at: 5)
        precondition(reminders.tick(at: 10)?.action == "prompt")
        precondition(reminders.deferPrompt(at: 11, snooze: true)?.action == "snooze")
        precondition(policy.current!.due == savedDue)
        _ = policy.finish() // Stop cancels pending and scheduled opportunities.
        precondition(policy.open(token: afterReturn.id, at: 1200) == nil)
        let restarted = policy.schedule(from: 0)
        precondition(restarted.id != afterReturn.id && restarted.due == 600)
        precondition(policy.open(token: afterReturn.id, at: 1200) == nil)
        var earlyBreak = BreakPolicy()
        _ = earlyBreak.begin(at: 30, seconds: 300, activity: "Stretch")
        let earlyReturn = earlyBreak.finish(at: 150, reason: "outside_app_input")!
        let early = policy.schedule(from: earlyReturn.time, afterBreak: earlyReturn.record!.id)
        precondition(early.due == 750)

        let root = FileManager.default.temporaryDirectory.appendingPathComponent("focusfix-timed-tests-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: root) }
        let writer = try RecordingWriter(root: root, id: "synthetic", startedAt: Date(timeIntervalSince1970: 0))
        try writer.logSurveyPrompt(SurveyPromptEntry(item: first, action: "scheduled", time: 0))
        try writer.logSurveyPrompt(SurveyPromptEntry(item: requested, action: "requested", time: 602))
        try writer.logSurveyPrompt(SurveyPromptEntry(item: opened, action: "opened", time: 610))
        try writer.logSurveyPrompt(SurveyPromptEntry(item: answered, action: "answered", time: 615))
        try writer.logSurvey(SurveyEntry(id: answered.id, context: .duringWork, status: .answered,
            breakID: "", shownAt: Date(timeIntervalSince1970: 610), answeredAt: Date(timeIntervalSince1970: 615),
            shownElapsed: 610, answeredElapsed: 615, fatigue: 2, productivity: 8))
        let prompts = try String(contentsOf: writer.folder.appendingPathComponent("survey_prompts.csv"), encoding: .utf8)
        precondition(prompts.split(separator: "\n").count == 5)
        precondition(prompts.split(separator: "\n").allSatisfy { $0.split(separator: ",", omittingEmptySubsequences: false).count == 8 })
        precondition(prompts.contains("602.000000,600.000000,602.000000,,"))
        precondition(prompts.contains("615.000000,600.000000,602.000000,610.000000,"))
        let surveys = try String(contentsOf: writer.folder.appendingPathComponent("surveys.csv"), encoding: .utf8)
        precondition(surveys.contains("during_work,answered") && surveys.contains(answered.id))
        precondition(surveys.contains("610.000000,615.000000,2,8"))
        print("PASS: ten-minute boundary, one prompt per work period, deferral, stale/duplicate actions, stop/break cancellation, actual return timing and linked prompt/answer CSVs.")
    }
}
