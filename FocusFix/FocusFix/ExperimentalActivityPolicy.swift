import Foundation

// A disabled seam. Shipping eligibility/cooldowns remain in the existing fixed policy.
nonisolated struct ActivityRateBin {
    let start: Double
    let end: Double
    let distance: Double
    let movementEvents: Int
    let phase: InterventionPhase
}
nonisolated struct ActivityRateEvent { let elapsed: Double; let type: String }
nonisolated enum ActivityRateFeatures {
    static let version = "focusfix_activity_rates_v1"
    static let names = ["keys_per_minute", "deletes_per_minute", "clicks_per_minute", "switches_per_minute",
                        "scrolls_per_minute", "mouse_points_per_minute", "mouse_events_per_minute"]
    static func make(start: Double, end: Double, bins: [ActivityRateBin], events: [ActivityRateEvent], explicitBreak: Bool) -> [Double]? {
        guard start.isFinite, end.isFinite, start >= 0, abs(end - start - 300) < 0.000001,
              !explicitBreak else { return nil }
        let selected = bins.filter { $0.start >= start - 0.000001 && $0.end <= end + 0.000001 }.sorted { $0.start < $1.start }
        var previous = start, observed = 0.0, distance = 0.0, movements = 0.0
        for bin in selected {
            guard bin.start.isFinite, bin.end.isFinite, bin.end > bin.start,
                  abs(bin.start - previous) < 0.000001, bin.phase == .normal,
                  bin.distance.isFinite, bin.distance >= 0, bin.movementEvents >= 0 else { return nil }
            previous = bin.end; observed += bin.end - bin.start
            distance += bin.distance; movements += Double(bin.movementEvents)
        }
        guard abs(observed - 300) < 0.00001, abs(previous - end) < 0.000001 else { return nil }
        var values = Array(repeating: 0.0, count: names.count)
        for event in events {
            guard event.elapsed.isFinite else { return nil }
            guard event.elapsed >= start, event.elapsed < end else { continue }
            switch event.type {
            case "key_down": values[0] += 1
            case "delete_down": values[0] += 1; values[1] += 1
            case "left_click_down", "right_click_down", "other_click_down": values[2] += 1
            case "app_switch": values[3] += 1
            case "scroll": values[4] += 1
            default: break
            }
        }
        values[5] = distance; values[6] = movements
        let result = values.map { Double(Float($0 * 60 / observed)) }
        return result.allSatisfy(\.isFinite) ? result : nil
    }
}
nonisolated struct ExperimentalPolicyInput {
    let featureVersion: String
    let features: [Double]?
    let context: ActivityContext
    let screenUseReminders: Bool
    let paused: Bool
    let cooldownReady: Bool
    let nowUTC: Date
}
nonisolated enum ExperimentalPolicyResult: Equatable {
    case baseline(String)
    case descriptiveCluster(Int, modelVersion: String)
}
nonisolated protocol BreakPolicyProvider {
    var version: String { get }
    func result(for input: ExperimentalPolicyInput) -> ExperimentalPolicyResult
}
nonisolated struct FixedTimerPolicyProvider: BreakPolicyProvider {
    let version = "focusfix.fixed-context.v1"
    func result(for input: ExperimentalPolicyInput) -> ExperimentalPolicyResult { .baseline("Shipped fixed timer/idle policy") }
}
nonisolated struct ClusterPreviewModel: Codable {
    let feature_version: String
    let features: [String]
    let window_seconds: Int
    let model_version: String
    let synthetic: Bool
    let deployment_ready: Bool
    let mean: [Double]
    let scale: [Double]
    let centers: [[Double]]
}
nonisolated struct SyntheticClusterPreviewProvider: BreakPolicyProvider {
    let version = "focusfix.synthetic-cluster-preview.v1"
    let model: ClusterPreviewModel?
    let createdAtUTC: Date
    let maximumAgeSeconds: Double
    let maximumSquaredDistance: Double
    var explicitlyEnabled = false
    func result(for input: ExperimentalPolicyInput) -> ExperimentalPolicyResult {
        guard explicitlyEnabled else { return .baseline("Experimental policy disabled") }
        guard !input.paused, input.cooldownReady,
              ReminderEligibility.eligible(context: input.context, screenUseEnabled: input.screenUseReminders) else { return .baseline("Context, pause or cooldown ineligible") }
        guard let model, model.synthetic, !model.deployment_ready,
              model.feature_version == ActivityRateFeatures.version, input.featureVersion == ActivityRateFeatures.version,
              model.features == ActivityRateFeatures.names, model.window_seconds == 300,
              let values = input.features, values.count == ActivityRateFeatures.names.count, values.allSatisfy(\.isFinite),
              model.mean.count == values.count, model.scale.count == values.count,
              model.mean.allSatisfy(\.isFinite), model.scale.allSatisfy({ $0.isFinite && $0 > 0 }),
              !model.centers.isEmpty, model.centers.allSatisfy({ $0.count == values.count && $0.allSatisfy(\.isFinite) }),
              maximumAgeSeconds.isFinite, maximumAgeSeconds > 0,
              input.nowUTC >= createdAtUTC, input.nowUTC.timeIntervalSince(createdAtUTC) <= maximumAgeSeconds,
              maximumSquaredDistance.isFinite, maximumSquaredDistance >= 0 else { return .baseline("Missing, stale, incompatible model or insufficient coverage") }
        let normalized = values.indices.map { (values[$0] - model.mean[$0]) / model.scale[$0] }
        let distances = model.centers.map { center in normalized.indices.reduce(0.0) { $0 + pow(normalized[$1] - center[$1], 2) } }
        guard let minimum = distances.min(), minimum.isFinite, minimum <= maximumSquaredDistance,
              let cluster = distances.firstIndex(of: minimum) else { return .baseline("Unknown cluster") }
        return .descriptiveCluster(cluster, modelVersion: model.model_version)
    }
}
