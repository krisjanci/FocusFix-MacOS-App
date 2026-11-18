import Foundation

@main struct StartOfDaySurveyTests {
    @MainActor static func main() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let store = StartOfDayStore(url: root.appendingPathComponent("daily.json"))
        let suite = "focusfix-daily-tests-\(UUID())"
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "America/New_York")!
        let iso = ISO8601DateFormatter()
        let now = iso.date(from: "2026-11-18T14:00:00Z")!
        let next = calendar.date(byAdding: .day, value: 1, to: now)!
        let controller = StartOfDayController(defaults: defaults, store: store)
        precondition(!controller.enabled && !controller.isDue(at: now, calendar: calendar))
        controller.setEnabled(true)
        precondition(controller.isDue(at: now, calendar: calendar))
        controller.showIfDue(at: now, calendar: calendar)
        precondition(controller.presented?.day == "2026-11-18")
        let restored = StartOfDayController(defaults: defaults, store: store)
        precondition(!restored.isDue(at: now, calendar: calendar), "An unanswered launch must not repeat")
        controller.finish(bedtime: now.addingTimeInterval(-9 * 3600), wakeTime: now.addingTimeInterval(-3600), rested: 7, fatigue: 2, stress: 3, now: now)
        precondition(controller.presented == nil && controller.entries[0].status == "answered")
        let saved = try store.load()
        precondition(saved == controller.entries)
        let csv = StartOfDayStore.csv(controller.entries)
        precondition(csv.contains("8.000,7,2,3") && csv.contains("America/New_York"))
        precondition(!controller.isDue(at: now, calendar: calendar))
        controller.showIfDue(at: next, calendar: calendar)
        controller.finish(rested: 11, fatigue: 2, stress: 3, now: next)
        precondition(controller.presented != nil && controller.error != nil, "Invalid answers must stay open")
        controller.finish(skipping: true, now: next)
        precondition(controller.entries.last?.status == "skipped" && controller.entries.last?.rested == nil)
        controller.setEnabled(false)
        precondition(!controller.isDue(at: next, calendar: calendar))
        controller.setEnabled(true)
        precondition(!controller.isDue(at: next, calendar: calendar))
        controller.deleteResponses()
        precondition(controller.entries.isEmpty && !FileManager.default.fileExists(atPath: store.url.path))
        precondition(!controller.isDue(at: next, calendar: calendar), "Deletion must not re-prompt today")
        // Local midnight and daylight-saving transitions use calendar dates, not 24-hour timers.
        let beforeMidnight = iso.date(from: "2026-11-20T04:59:00Z")!
        let afterMidnight = iso.date(from: "2026-11-20T05:01:00Z")!
        precondition(StartOfDayStore.dayKey(beforeMidnight, calendar: calendar) == "2026-11-19")
        precondition(StartOfDayStore.dayKey(afterMidnight, calendar: calendar) == "2026-11-20")
        let bed = iso.date(from: "2026-11-01T03:00:00Z")!
        let wake = iso.date(from: "2026-11-01T12:00:00Z")!
        var dst = StartOfDayResponse(day: "2026-11-01", timeZone: calendar.timeZone.identifier, shownAt: wake)
        dst.status = "answered"; dst.answeredAt = wake; dst.bedtime = bed; dst.wakeTime = wake
        dst.rested = 0; dst.fatigue = 10; dst.stress = 5
        try dst.validate()
        precondition(StartOfDayStore.csv([dst]).contains("9.000,0,10,5"))
        // A failed write must not consume the day or silently discard the response.
        let blocker = root.appendingPathComponent("blocker")
        try Data().write(to: blocker)
        let broken = StartOfDayController(defaults: defaults, store: StartOfDayStore(url: blocker.appendingPathComponent("data")))
        broken.showIfDue(at: afterMidnight, calendar: calendar)
        precondition(broken.presented == nil && broken.error != nil)
        print("Start of day survey tests passed")
    }
}
