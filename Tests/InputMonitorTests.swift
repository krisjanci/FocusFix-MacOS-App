import AppKit
import CoreGraphics

@main struct InputMonitorTests {
    @MainActor static func main() {
        var requests = 0
        var permission = false
        precondition(!InputMonitor.requestPermission(preflight: { permission }, requestAccess: { requests += 1 }))
        precondition(requests == 1) // Requesting is not the same as granting.
        precondition(InputMonitor.requestPermission(preflight: { permission }, requestAccess: {
            requests += 1; permission = true
        }))
        precondition(requests == 2)
        precondition(InputMonitor.requestPermission(preflight: { permission }, requestAccess: { requests += 1 }))
        precondition(requests == 2) // Already granted never prompts again.

        // Synthetic events only: never install a tap, request permission or post input.
        let key = CGEvent(keyboardEventSource: nil, virtualKey: 51, keyDown: true)!
        key.setIntegerValueField(.keyboardEventAutorepeat, value: 1)
        key.setIntegerValueField(.eventTargetUnixProcessID, value: 4321)
        let down = ActivityInput(event: key)!
        precondition(down.type == .keyDown && down.keyCode == 51 && down.isARepeat)
        precondition(down.isOutsideApp(processID: 1234))
        precondition(!down.isOutsideApp(processID: 4321))
        precondition(down.scrollingDeltaX == 0 && !down.hasPreciseScrollingDeltas)
        let up = CGEvent(keyboardEventSource: nil, virtualKey: 117, keyDown: false)!
        precondition(ActivityInput(event: up)!.type == .keyUp)
        precondition(ActivityInput(event: up)!.keyCode == 117)
        precondition(!ActivityInput(event: up)!.isARepeat)
        key.setIntegerValueField(.eventTargetUnixProcessID, value: 0)
        precondition(!ActivityInput(event: key)!.isOutsideApp(processID: 1234))
        let mouseTypes: [CGEventType] = [.mouseMoved, .leftMouseDown, .leftMouseUp,
            .rightMouseDown, .rightMouseUp, .otherMouseDown, .otherMouseUp,
            .leftMouseDragged, .rightMouseDragged, .otherMouseDragged]
        for type in mouseTypes {
            let event = CGEvent(mouseEventSource: nil, mouseType: type,
                mouseCursorPosition: CGPoint(x: 90, y: 130), mouseButton: .left)!
            event.setIntegerValueField(.mouseEventDeltaX, value: 7)
            event.setIntegerValueField(.mouseEventDeltaY, value: -3)
            let input = ActivityInput(event: event)!
            precondition(input.location == CGPoint(x: 90, y: 130))
            precondition(input.keyCode == 0 && !input.isARepeat)
            if type == .mouseMoved { precondition(input.deltaX == 7 && input.deltaY == -3) }
        }
        let scroll = CGEvent(scrollWheelEvent2Source: nil, units: .pixel, wheelCount: 2,
            wheel1: 12, wheel2: -4, wheel3: 0)!
        let input = ActivityInput(event: scroll)!
        precondition(input.type == .scrollWheel && input.hasPreciseScrollingDeltas)
        precondition(input.scrollingDeltaY == 12 && input.scrollingDeltaX == -4)
        precondition(!input.isMomentum)
        var gate = InputDeliveryGate()
        precondition(!gate.accepts(gate.generation))
        gate.start()
        let old = gate.generation
        precondition(gate.accepts(old))
        gate.stop()
        precondition(!gate.accepts(old))
        gate.start()
        precondition(!gate.accepts(old) && gate.accepts(gate.generation))
        print("Input monitoring: key/repeat/delete, pointer, scroll, target routing and stale-session isolation passed.")
    }
}
