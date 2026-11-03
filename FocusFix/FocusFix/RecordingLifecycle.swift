import Foundation

// One decision point for every automatic start/stop. Pure inputs make races testable.
nonisolated struct RecordingLifecycle {
    enum Effect: Equatable { case none, start, stop(String) }
    var recordingAllowed = false
    var automaticEnabled = false
    var userPaused = false
    var permissionAvailable = false
    var blockers: Set<String> = []
    var quitting = false
    var failed = false
    var idleCutoff: Double = 300
    private(set) var idlePaused = false
    private(set) var state: CaptureState = .disabled
    private(set) var reason: String?

    static func observedEnd(now: Double, lastSamplingTick: Double, lastObserved: Double) -> Double {
        guard now.isFinite, lastSamplingTick.isFinite, lastObserved.isFinite,
              now >= 0, lastSamplingTick >= 0, lastObserved >= 0 else { return max(0, lastObserved.isFinite ? lastObserved : 0) }
        return now - lastSamplingTick > 5 ? lastObserved : max(now, lastObserved)
    }

    mutating func reconcile(recording: Bool, mode: RecordingMode, idle: Double) -> Effect {
        guard idle.isFinite, idle >= 0 else {
            state = .ready; reason = "idle_status_unavailable"
            return recording && mode == .automatic ? .stop("idle_status_unavailable") : .none
        }
        let shouldStop: String?
        if quitting { shouldStop = "app_quit"; state = .disabled }
        else if !recordingAllowed { shouldStop = "recording_disabled"; state = .disabled }
        else if userPaused { shouldStop = "user_pause"; state = .userPaused }
        else if !permissionAvailable { shouldStop = "permission_lost"; state = .permissionUnavailable }
        else if !blockers.isEmpty { shouldStop = "lifecycle_" + blockers.sorted().joined(separator: "_"); state = .ready }
        else if failed { shouldStop = "recording_error"; state = .ready }
        else if mode == .automatic && recording && !automaticEnabled { shouldStop = "automatic_disabled"; state = .ready }
        else if automaticEnabled && mode == .automatic && idle >= idleCutoff {
            shouldStop = "idle_cutoff"; state = .idlePaused; idlePaused = true
        } else { shouldStop = nil; state = recording ? .recording : .ready }
        reason = shouldStop
        if recording, let shouldStop { return .stop(shouldStop) }
        guard shouldStop == nil, !recording, automaticEnabled else { return .none }
        guard idle < idleCutoff else { state = .idlePaused; idlePaused = true; return .none }
        idlePaused = false
        return .start
    }
}

nonisolated enum RecordingDay {
    static func key(at date: Date, timeZone: TimeZone = .current) -> String {
        var calendar = Calendar(identifier: .gregorian); calendar.timeZone = timeZone
        let parts = calendar.dateComponents([.year, .month, .day], from: date)
        return "\(timeZone.identifier):\(parts.year ?? 0)-\(parts.month ?? 0)-\(parts.day ?? 0)"
    }
}
