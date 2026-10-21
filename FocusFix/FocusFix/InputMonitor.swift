// MARK: - FF: TRACKING
// A passive, sandbox-compatible event tap. Never posts, blocks or changes input.
import AppKit
import CoreGraphics
import IOKit.hid

// Only values needed for activity metrics cross the callback boundary. No typed text.
nonisolated struct ActivityInput {
    let type: NSEvent.EventType
    let keyCode: UInt16
    let isARepeat: Bool
    let location: CGPoint
    let deltaX: Double
    let deltaY: Double
    let scrollingDeltaX: Double
    let scrollingDeltaY: Double
    let hasPreciseScrollingDeltas: Bool
    let isMomentum: Bool
    let targetPID: pid_t

    init?(event: CGEvent) {
        guard let input = NSEvent(cgEvent: event) else { return nil }
        type = input.type
        let isKey = type == .keyDown || type == .keyUp || type == .flagsChanged
        keyCode = isKey ? UInt16(truncatingIfNeeded: event.getIntegerValueField(.keyboardEventKeycode)) : 0
        isARepeat = type == .keyDown && event.getIntegerValueField(.keyboardEventAutorepeat) != 0
        location = event.location
        let isMouse = [.mouseMoved, .leftMouseDragged, .rightMouseDragged, .otherMouseDragged].contains(type)
        deltaX = isMouse ? Double(event.getIntegerValueField(.mouseEventDeltaX)) : 0
        deltaY = isMouse ? Double(event.getIntegerValueField(.mouseEventDeltaY)) : 0
        scrollingDeltaX = type == .scrollWheel ? Double(input.scrollingDeltaX) : 0
        scrollingDeltaY = type == .scrollWheel ? Double(input.scrollingDeltaY) : 0
        hasPreciseScrollingDeltas = type == .scrollWheel && input.hasPreciseScrollingDeltas
        isMomentum = type == .scrollWheel && !input.momentumPhase.isEmpty
        targetPID = pid_t(truncatingIfNeeded: event.getIntegerValueField(.eventTargetUnixProcessID))
    }

    // Annotated taps normally identify the target. Unknown targets cannot end a break.
    func isOutsideApp(processID: pid_t) -> Bool { targetPID > 0 && targetPID != processID }
}

// Prevent queued callbacks from an old session leaking into a newly started session.
nonisolated struct InputDeliveryGate {
    private(set) var generation: UInt64 = 0
    private(set) var active = false
    mutating func start() { generation &+= 1; active = true }
    mutating func stop() { generation &+= 1; active = false }
    func accepts(_ token: UInt64) -> Bool { active && token == generation }
}

@MainActor
final class InputMonitor {
    private var port: CFMachPort?
    private var source: CFRunLoopSource?
    private var gate = InputDeliveryGate()
    private var onInput: ((ActivityInput) -> Void)?
    private var onInterruption: (() -> Void)?

    static var hasPermission: Bool { CGPreflightListenEventAccess() }
    static func requestPermission(
        preflight: () -> Bool = { CGPreflightListenEventAccess() },
        requestAccess: () -> Void = { _ = IOHIDRequestAccess(kIOHIDRequestTypeListenEvent) }
    ) -> Bool {
        // IOHID explicitly requests the Input Monitoring list entry. CGPreflight remains
        // the authority for whether our CoreGraphics event tap can actually listen.
        if preflight() { return true }
        requestAccess()
        return preflight()
    }
    var isEnabled: Bool { port.map { CGEvent.tapIsEnabled(tap: $0) } ?? false }

    func start(onInput: @escaping (ActivityInput) -> Void, onInterruption: @escaping () -> Void) -> Bool {
        stop()
        guard Self.hasPermission else { return false }
        let types: [CGEventType] = [.keyDown, .keyUp, .flagsChanged,
            .leftMouseDown, .leftMouseUp, .rightMouseDown, .rightMouseUp,
            .otherMouseDown, .otherMouseUp, .scrollWheel, .mouseMoved,
            .leftMouseDragged, .rightMouseDragged, .otherMouseDragged]
        let mask = types.reduce(CGEventMask(0)) { $0 | (CGEventMask(1) << $1.rawValue) }
        guard let tap = CGEvent.tapCreate(tap: .cgAnnotatedSessionEventTap,
            place: .tailAppendEventTap, options: .listenOnly, eventsOfInterest: mask,
            callback: { _, type, event, context in
                if let context {
                    // The source is installed exclusively on the main run loop.
                    MainActor.assumeIsolated {
                        Unmanaged<InputMonitor>.fromOpaque(context).takeUnretainedValue()
                            .receive(type: type, event: event)
                    }
                }
                return Unmanaged.passUnretained(event)
            }, userInfo: Unmanaged.passUnretained(self).toOpaque()) else { return false }
        guard let runLoopSource = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, tap, 0) else {
            CFMachPortInvalidate(tap)
            return false
        }
        self.onInput = onInput
        self.onInterruption = onInterruption
        port = tap
        source = runLoopSource
        gate.start()
        CFRunLoopAddSource(CFRunLoopGetMain(), runLoopSource, .commonModes)
        CGEvent.tapEnable(tap: tap, enable: true)
        if !isEnabled { stop(); return false }
        return true
    }

    private func receive(type: CGEventType, event: CGEvent) {
        let token = gate.generation
        if type == .tapDisabledByTimeout || type == .tapDisabledByUserInput {
            // Do not silently resume after lost observations. End the session explicitly.
            DispatchQueue.main.async { [weak self] in
                guard let self, self.gate.accepts(token) else { return }
                self.onInterruption?()
            }
            return
        }
        guard let input = ActivityInput(event: event) else { return }
        // Return from the tap before any CSV I/O or UI work; preserve main-queue ordering.
        DispatchQueue.main.async { [weak self] in
            guard let self, self.gate.accepts(token) else { return }
            self.onInput?(input)
        }
    }

    func stop() {
        gate.stop()
        if let port { CGEvent.tapEnable(tap: port, enable: false); CFMachPortInvalidate(port) }
        if let source { CFRunLoopRemoveSource(CFRunLoopGetMain(), source, .commonModes) }
        source = nil
        port = nil
        onInput = nil
        onInterruption = nil
    }
}
