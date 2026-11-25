import Foundation

// The retired daily survey is intentionally separate from timed session check-ins.
nonisolated enum RetiredDailySurvey {
    static func cleanup(defaults: UserDefaults = .standard, applicationSupport: URL? = nil) throws {
        let root = try applicationSupport ?? FileManager.default.url(for: .applicationSupportDirectory,
            in: .userDomainMask, appropriateFor: nil, create: false)
        let file = root.appendingPathComponent("FocusFix/start-of-day.json")
        // No completion marker: a failed removal is retried on the next launch.
        if FileManager.default.fileExists(atPath: file.path) {
            try FileManager.default.removeItem(at: file)
        }
        defaults.removeObject(forKey: "focusfix.startOfDaySurvey.enabled")
        defaults.removeObject(forKey: "focusfix.startOfDaySurvey.lastShownDay")
    }
}
