import CoreGraphics

nonisolated enum SystemIdleTime {
    // kCGAnyInputEventType is ~0 in Apple's CGEventTypes.h. .null is a different query.
    static let anyInputEventType = CGEventType(rawValue: UInt32.max)!
    static func seconds() -> Double {
        CGEventSource.secondsSinceLastEventType(.combinedSessionState, eventType: anyInputEventType)
    }
}
