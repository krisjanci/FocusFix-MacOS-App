import Foundation
import Combine

@MainActor final class StartOfDayController: ObservableObject {
    static let shared = StartOfDayController()
    @Published private(set) var enabled: Bool
    @Published private(set) var presented: StartOfDayResponse?
    @Published private(set) var entries: [StartOfDayResponse] = []
    @Published var error: String?
    private let defaults: UserDefaults
    private let store: StartOfDayStore?
    private var loaded = false
    private let enabledKey = "focusfix.startOfDaySurvey.enabled"
    // Kept separately so deleting responses cannot cause a second prompt today.
    private let lastDayKey = "focusfix.startOfDaySurvey.lastShownDay"

    init(defaults: UserDefaults = .standard, store: StartOfDayStore? = nil) {
        self.defaults = defaults
        self.store = store ?? (try? StartOfDayStore.local())
        enabled = defaults.bool(forKey: enabledKey)
        reload()
    }

    func reload() {
        do {
            guard let store else { throw CocoaError(.fileNoSuchFile) }
            entries = try store.load()
            loaded = true
            error = nil
        } catch { loaded = false; self.error = "Couldn’t read daily surveys. \(error.localizedDescription)" }
    }

    func setEnabled(_ value: Bool) {
        enabled = value
        defaults.set(value, forKey: enabledKey)
        if !value { presented = nil }
    }

    func isDue(at now: Date = Date(), calendar: Calendar = .current) -> Bool {
        let day = StartOfDayStore.dayKey(now, calendar: calendar)
        return enabled && loaded && presented == nil && defaults.string(forKey: lastDayKey) != day && !entries.contains { $0.day == day }
    }

    func showIfDue(at now: Date = Date(), calendar: Calendar = .current) {
        guard isDue(at: now, calendar: calendar) else { return }
        let entry = StartOfDayResponse(day: StartOfDayStore.dayKey(now, calendar: calendar),
            timeZone: calendar.timeZone.identifier, shownAt: now)
        guard persist(entries + [entry]) else { return }
        defaults.set(entry.day, forKey: lastDayKey)
        presented = entry
    }

    func finish(bedtime: Date? = nil, wakeTime: Date? = nil, rested: Int? = nil,
                fatigue: Int? = nil, stress: Int? = nil, skipping: Bool = false, now: Date = Date()) {
        guard var entry = presented else { return }
        entry.status = skipping ? "skipped" : "answered"
        entry.answeredAt = now
        if !skipping {
            entry.bedtime = bedtime; entry.wakeTime = wakeTime
            entry.rested = rested; entry.fatigue = fatigue; entry.stress = stress
        }
        let updated = entries.map { $0.day == entry.day ? entry : $0 }
        if persist(updated) { presented = nil }
    }

    func deleteResponses() {
        do {
            guard let store else { throw CocoaError(.fileNoSuchFile) }
            try store.delete()
            entries = []; presented = nil; loaded = true; error = nil
        } catch { self.error = "Couldn’t delete daily surveys. \(error.localizedDescription)" }
    }

    private func persist(_ updated: [StartOfDayResponse]) -> Bool {
        do {
            guard let store else { throw CocoaError(.fileNoSuchFile) }
            try store.save(updated)
            entries = updated; error = nil
            return true
        } catch { self.error = "Couldn’t save daily survey. \(error.localizedDescription)"; return false }
    }
}
