import Foundation

nonisolated enum RecordingPresentation {
    static func status(state: CaptureState, mode: RecordingMode, context: ActivityContext, phase: InterventionPhase) -> String {
        switch state {
        case .disabled: return "Recording off"
        case .ready: return "Ready"
        case .userPaused: return "Paused"
        case .idlePaused: return "Idle"
        case .permissionUnavailable: return "Permission needed"
        case .recording:
            if phase == .explicitBreak { return "On an explicit break · detailed capture paused" }
            if phase == .awaitingReturn { return "Awaiting return" }
            if phase == .checkIn { return "Check-in" }
            switch context {
            case .work: return "Working · user declared"
            case .nonWork: return "Not working"
            case .unknown: return mode == .automatic ? "Recording automatically · Unknown activity" : "Recording · Unknown activity"
            }
        }
    }
}
