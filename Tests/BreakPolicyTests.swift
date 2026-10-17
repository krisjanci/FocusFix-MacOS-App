import Foundation
import CoreGraphics

@main
struct BreakPolicyTests {
    static func near(_ a: Double, _ b: Double) { precondition(abs(a - b) < 0.00001, "\(a) != \(b)") }
    static func main() throws {
        var policy = BreakPolicy()
        // A single long idle stretch is NOT two separate pauses.
        precondition(policy.tick(at: 1500) == nil)
        policy.input(at: 1501)
        precondition(policy.tick(at: 1505.9) == nil)
        let prompt = policy.tick(at: 1506)!
        precondition(prompt.action == "prompt")
        precondition(policy.tick(at: 1510) == nil) // Never repeat unanswered prompts.
        let skipped = policy.deferPrompt(at: 1511, snooze: false)!
        near(skipped.nextEligible!, 3011)
        near(policy.sinceLastBreak(at: 1511), 1511) // Skip does not pretend a break happened.
        precondition(policy.deferPrompt(at: 1512, snooze: false) == nil)
        precondition(policy.tick(at: 3011) == nil) // Reset old idle history on Skip.
        policy.input(at: 3012)
        precondition(policy.tick(at: 3017)?.action == "prompt")
        let snoozed = policy.deferPrompt(at: 3018, snooze: true)!
        near(snoozed.nextEligible!, 3618)
        policy.input(at: 3613)
        precondition(policy.tick(at: 3617.9) == nil)
        precondition(policy.tick(at: 3618)?.action == "prompt")

        var stale = BreakPolicy(workDelay: 0)
        stale.input(at: 6)
        stale.input(at: 12)
        precondition(stale.tick(at: 13) == nil) // Two earlier pauses but currently busy.
        precondition(stale.tick(at: 80) == nil) // Old pauses fall outside the minute.
        var boundary = BreakPolicy(workDelay: 0)
        boundary.input(at: 6)
        precondition(boundary.tick(at: 61)?.action == "prompt") // Exactly 5 sec of earlier gap remains.
        var tooOld = BreakPolicy(workDelay: 0)
        tooOld.input(at: 6)
        precondition(tooOld.tick(at: 61.01) == nil)

        precondition(policy.begin(at: 3620, seconds: .nan, activity: "Walk") == nil)
        precondition(policy.begin(at: 3620, seconds: 0, activity: "Walk") == nil)
        let start = policy.begin(at: 3620, seconds: 300, activity: "Walk")!
        precondition(start.action == "break_start" && policy.phase == .resting)
        precondition(policy.begin(at: 3621, seconds: 300, activity: "Walk") == nil)
        precondition(policy.tick(at: 3919.99) == nil)
        let expiry = policy.tick(at: 3921)!
        near(expiry.time, 3920) // Deadline, not the delayed callback time.
        precondition(policy.phase == .awaitingReturn && policy.tick(at: 3930) == nil)
        let returned = policy.finish(at: 4040, reason: "outside_app_input")!
        near(returned.record!.actualSeconds!, 420)
        near(returned.record!.extraIdleSeconds!, 120)
        precondition(policy.phase == .work)
        near(policy.nextEligible, 5540)
        near(policy.sinceLastBreak(at: 4045), 5)
        precondition(policy.finish(at: 4041, reason: "explicit_return") == nil)
        let correction = policy.updateActivity("Rest my eyes", at: 4045)!
        precondition(correction.record!.plannedActivity == "Walk")
        precondition(correction.record!.actualActivity == "Rest my eyes")
        precondition(correction.record!.id == start.record!.id)

        var early = BreakPolicy()
        _ = early.begin(at: 100, seconds: 600, activity: "Stretch")
        let earlyEnd = early.finish(at: 220, reason: "explicit_return")!
        near(earlyEnd.record!.actualSeconds!, 120)
        near(earlyEnd.record!.extraIdleSeconds!, 0)
        _ = early.begin(at: 300, seconds: 300, activity: "Rest my eyes")
        let stopped = early.finish(at: 350, reason: "session_sleep_or_inactive_session")!
        precondition(stopped.record!.endReason == "session_sleep_or_inactive_session")
        near(stopped.record!.actualSeconds!, 50) // Truncated, not a fabricated return.

        // Pause gaps must not become zero activity rows or long key holds.
        var before = MouseAccumulator(initialPosition: .zero)
        let preBreakRows = before.stop(at: 1.5)
        near(preBreakRows.last!.end, 1.5)
        var after = MouseAccumulator(initialPosition: .zero, start: 301.5,
            activityPhase: "awaiting_return", workReference: nil)
        let waitingRows = after.advance(to: 302.5)
        precondition(waitingRows.count == 1 && waitingRows[0].start == 301.5)
        precondition(waitingRows[0].activityPhase == "awaiting_return" && waitingRows[0].secondsSinceLastBreak == nil)
        var resumed = MouseAccumulator(initialPosition: .zero, start: 320, workReference: 320)
        near(resumed.advance(to: 321)[0].secondsSinceLastBreak!, 1)

        let root = FileManager.default.temporaryDirectory.appendingPathComponent("focusfix-break-tests-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: root) }
        let writer = try RecordingWriter(root: root, id: "break-test", startedAt: Date())
        for entry in [prompt, skipped, snoozed, start, expiry, returned, correction, earlyEnd, stopped] {
            try writer.logBreak(entry)
        }
        let csv = try String(contentsOf: writer.folder.appendingPathComponent("breaks.csv"), encoding: .utf8)
        precondition(csv.split(separator: "\n").count == 10)
        precondition(csv.contains("\"activity_updated\"") && csv.contains("420.000000,120.000000"))
        precondition(BreakLogEntry.text("Water, \"tea\"") == "\"Water, \"\"tea\"\"\"")
        precondition(BreakLogEntry.text("=1+1") == "\"'=1+1\"")
        precondition(BreakLogEntry.text("  @SUM(A1)") == "\"'  @SUM(A1)\"")
        print("PASS: distinct idle gaps, 25/10 minute delays, no duplicate prompts, early/late return, activity corrections, truncated breaks, paused intervals, break CSV and escaping.")
    }
}
