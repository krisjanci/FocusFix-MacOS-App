import Foundation

@main struct ExperimentalActivityPolicyTests {
    static func main() throws {
        let bins = (0..<300).map { ActivityRateBin(start: Double($0), end: Double($0 + 1), distance: 3, movementEvents: $0 < 150 ? 2 : 1, phase: .normal) }
        var events: [ActivityRateEvent] = []
        for (type, count) in [("key_down", 108), ("delete_down", 12), ("left_click_down", 6), ("app_switch", 2), ("scroll", 5)] {
            events += (0..<count).map { ActivityRateEvent(elapsed: Double($0), type: type) }
        }
        events.append(ActivityRateEvent(elapsed: 300, type: "key_down")) // Half-open end is excluded.
        let features = ActivityRateFeatures.make(start: 0, end: 300, bins: bins, events: events, explicitBreak: false)!
        let fixture = try JSONSerialization.jsonObject(with: Data(contentsOf: URL(fileURLWithPath: "Tests/Fixtures/activity-rate-parity.json"))) as! [String: Any]
        precondition(features == fixture["expected"] as! [Double])
        precondition(ActivityRateFeatures.make(start: 0, end: 300, bins: Array(bins.dropFirst()), events: events, explicitBreak: false) == nil)
        precondition(ActivityRateFeatures.make(start: 0, end: 300, bins: bins, events: events, explicitBreak: true) == nil)
        let date = Date(timeIntervalSince1970: 100)
        let input = ExperimentalPolicyInput(featureVersion: ActivityRateFeatures.version, features: features,
            context: .work, screenUseReminders: false, paused: false, cooldownReady: true, nowUTC: date)
        let model = ClusterPreviewModel(feature_version: ActivityRateFeatures.version, features: ActivityRateFeatures.names,
            window_seconds: 300, model_version: "synthetic-parity", synthetic: true, deployment_ready: false,
            mean: features, scale: Array(repeating: 1, count: 7), centers: [Array(repeating: 0, count: 7)])
        var provider = SyntheticClusterPreviewProvider(model: model, createdAtUTC: date, maximumAgeSeconds: 60, maximumSquaredDistance: 1)
        precondition(provider.result(for: input) == .baseline("Experimental policy disabled"))
        provider.explicitlyEnabled = true
        precondition(provider.result(for: input) == .descriptiveCluster(0, modelVersion: "synthetic-parity"))
        for (version, values, context, paused, cooldown, now) in [
            ("unsupported", features as [Double]?, ActivityContext.work, false, true, date),
            (ActivityRateFeatures.version, nil, .work, false, true, date),
            (ActivityRateFeatures.version, features, .unknown, false, true, date),
            (ActivityRateFeatures.version, features, .work, true, true, date),
            (ActivityRateFeatures.version, features, .work, false, false, date),
            (ActivityRateFeatures.version, features, .work, false, true, date.addingTimeInterval(61))] {
            let result = provider.result(for: ExperimentalPolicyInput(featureVersion: version, features: values, context: context,
                screenUseReminders: false, paused: paused, cooldownReady: cooldown, nowUTC: now))
            if case .baseline = result {} else { preconditionFailure("Unsafe experimental prediction") }
        }
        let unknown = provider.result(for: ExperimentalPolicyInput(featureVersion: ActivityRateFeatures.version,
            features: Array(repeating: 1e6, count: 7), context: .work, screenUseReminders: false, paused: false, cooldownReady: true, nowUTC: date))
        precondition(unknown == .baseline("Unknown cluster"))
        precondition(FixedTimerPolicyProvider().version == ReminderRequest.policyVersion)
        print("PASS: Python/Swift float32 feature parity, full coverage, unsupported/missing/stale models, context/pause/cooldown and safe baseline fallback")
    }
}
