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

// A dedicated run loop keeps history loading, menus and file panels out of the tap.
// One idle thread is shared across starts; each tap's context lives until teardown
// has run on this loop, after any in-flight callback has returned.
nonisolated enum InputMonitorRunLoop {
    private final class Ready: @unchecked Sendable {
        let condition = NSCondition()
        var loop: CFRunLoop?
        func publish(_ value: CFRunLoop) {
            condition.lock()
            loop = value
            condition.signal()
            condition.unlock()
        }
        func wait() -> CFRunLoop {
            condition.lock()
            defer { condition.unlock() }
            while loop == nil { condition.wait() }
            return loop!
        }
    }
    static let shared: CFRunLoop = {
        let ready = Ready()
        let thread = Thread {
            let loop = CFRunLoopGetCurrent()!
            var context = CFRunLoopSourceContext()
            let keepAlive = CFRunLoopSourceCreate(kCFAllocatorDefault, 0, &context)!
            CFRunLoopAddSource(loop, keepAlive, .commonModes)
            ready.publish(loop)
            CFRunLoopRun()
        }
        thread.name = "FocusFix input monitor"
        thread.qualityOfService = .userInitiated
        thread.start()
        return ready.wait()
    }()
}

nonisolated final class InputTapContext: @unchecked Sendable {
    let deliver: @Sendable (ActivityInput?) -> Void
    init(deliver: @escaping @Sendable (ActivityInput?) -> Void) { self.deliver = deliver }
    func receive(type: CGEventType, event: CGEvent) {
        if type == .tapDisabledByTimeout || type == .tapDisabledByUserInput {
            deliver(nil)
        } else {
            autoreleasepool {
                if let input = ActivityInput(event: event) { deliver(input) }
            }
        }
    }
}

@MainActor
final class InputMonitor {
    private var port: CFMachPort?
    private var source: CFRunLoopSource?
    private var gate = InputDeliveryGate()
    private var context: InputTapContext?
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
        gate.start()
        let token = gate.generation
        let context = InputTapContext { [weak self] input in
            // Only immutable metrics cross threads. UI and file I/O stay on main.
            DispatchQueue.main.async {
                guard let self, self.gate.accepts(token) else { return }
                if let input { self.onInput?(input) }
                else { self.onInterruption?() }
            }
        }
        guard let tap = CGEvent.tapCreate(tap: .cgAnnotatedSessionEventTap,
            place: .tailAppendEventTap, options: .listenOnly, eventsOfInterest: mask,
            callback: { _, type, event, context in
                if let context {
                    Unmanaged<InputTapContext>.fromOpaque(context).takeUnretainedValue()
                        .receive(type: type, event: event)
                }
                return Unmanaged.passUnretained(event)
            }, userInfo: Unmanaged.passUnretained(context).toOpaque()) else { gate.stop(); return false }
        guard let runLoopSource = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, tap, 0) else {
            CFMachPortInvalidate(tap)
            gate.stop()
            return false
        }
        self.onInput = onInput
        self.onInterruption = onInterruption
        port = tap
        source = runLoopSource
        self.context = context
        CFRunLoopAddSource(InputMonitorRunLoop.shared, runLoopSource, .commonModes)
        CFRunLoopWakeUp(InputMonitorRunLoop.shared)
        CGEvent.tapEnable(tap: tap, enable: true)
        if !isEnabled { stop(); return false }
        return true
    }

    func stop() {
        gate.stop()
        if let port, let source, let context {
            let loop = InputMonitorRunLoop.shared
            CFRunLoopPerformBlock(loop, CFRunLoopMode.commonModes.rawValue) {
                // Retain the callback context until the worker has removed this tap.
                withExtendedLifetime(context) {
                    CGEvent.tapEnable(tap: port, enable: false)
                    CFRunLoopRemoveSource(loop, source, .commonModes)
                    CFMachPortInvalidate(port)
                }
            }
            CFRunLoopWakeUp(loop)
        }
        context = nil
        source = nil
        port = nil
        onInput = nil
        onInterruption = nil
    }
}
