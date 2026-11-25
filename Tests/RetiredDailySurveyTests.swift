import Foundation

@main struct RetiredDailySurveyTests {
    static func main() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let defaults = UserDefaults(suiteName: "retired-survey-\(UUID())")!
        let file = root.appendingPathComponent("FocusFix/start-of-day.json")
        try FileManager.default.createDirectory(at: file.deletingLastPathComponent(), withIntermediateDirectories: true)
        try Data("previous responses".utf8).write(to: file)
        defaults.set(true, forKey: "focusfix.startOfDaySurvey.enabled")
        defaults.set("2026-11-25", forKey: "focusfix.startOfDaySurvey.lastShownDay")
        defaults.set(true, forKey: "focusfix.personalSurvey.enabled")
        try RetiredDailySurvey.cleanup(defaults: defaults, applicationSupport: root)
        precondition(!FileManager.default.fileExists(atPath: file.path))
        precondition(defaults.object(forKey: "focusfix.startOfDaySurvey.enabled") == nil)
        precondition(defaults.object(forKey: "focusfix.startOfDaySurvey.lastShownDay") == nil)
        precondition(defaults.bool(forKey: "focusfix.personalSurvey.enabled"))
        try RetiredDailySurvey.cleanup(defaults: defaults, applicationSupport: root)
        print("PASS: retired survey cleanup is repeatable and preserves timed survey settings")
    }
}
