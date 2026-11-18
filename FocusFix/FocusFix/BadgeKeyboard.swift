import AppKit
import SwiftUI

// Handle Escape inside native sheets too, where SwiftUI cancel shortcuts may not reach an unfocused overlay.
struct BadgeEscapeHandler: NSViewRepresentable {
    let enabled: Bool
    let action: () -> Void
    func makeCoordinator() -> Coordinator { Coordinator() }
    func makeNSView(context: Context) -> NSView {
        let view = NSView()
        context.coordinator.view = view
        context.coordinator.install()
        return view
    }
    func updateNSView(_ nsView: NSView, context: Context) {
        context.coordinator.enabled = enabled
        context.coordinator.action = action
    }
    static func dismantleNSView(_ nsView: NSView, coordinator: Coordinator) { coordinator.remove() }
    @MainActor final class Coordinator {
        weak var view: NSView?
        var enabled = false
        var action: () -> Void = {}
        private var monitor: Any?
        func install() {
            monitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
                guard let self, self.enabled, event.keyCode == 53,
                      event.modifierFlags.intersection([.command, .option, .control, .shift]).isEmpty,
                      let window = self.view?.window, window === event.window else { return event }
                self.action()
                return nil
            }
        }
        func remove() {
            if let monitor { NSEvent.removeMonitor(monitor) }
            monitor = nil
        }
    }
}
