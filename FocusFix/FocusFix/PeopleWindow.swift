import SwiftUI
import AppKit
import QuartzCore

enum PeopleWindowAnimation {
    static let duration: TimeInterval = 0.3
}

struct CollectorWindowResizeLock: ViewModifier {
    @ViewBuilder func body(content: Content) -> some View {
        if #available(macOS 15.0, *) {
            content.windowResizeBehavior(.disabled)
        } else {
            content
        }
    }
}

// The width change is deferred until SwiftUI has updated its content-size constraints.
struct PeopleWindowBridge: NSViewRepresentable {
    let expanded: Bool
    let reduceMotion: Bool
    let resolved: (NSWindow) -> Void
    func makeNSView(context: Context) -> WindowProbe {
        let view = WindowProbe()
        view.resolve = resolved
        view.reduceMotion = reduceMotion
        return view
    }
    func updateNSView(_ view: WindowProbe, context: Context) {
        view.resolve = resolved
        view.reduceMotion = reduceMotion
        DispatchQueue.main.async { [weak view] in view?.lockManualResizing() }
        guard view.expanded != expanded else { return }
        view.expanded = expanded
        view.resize()
    }
    final class WindowProbe: NSView {
        var resolve: ((NSWindow) -> Void)?
        var expanded: Bool?
        var reduceMotion = false
        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            guard let window else { return }
            lockManualResizing()
            DispatchQueue.main.async { [weak self, weak window] in
                guard let window else { return }
                self?.resolve?(window)
                self?.resize()
            }
        }
        func lockManualResizing() {
            // Older systems lack SwiftUI's windowResizeBehavior modifier.
            // Avoid changing native styles while modern SwiftUI is laying out.
            if #unavailable(macOS 15.0), let window, window.styleMask.contains(.resizable) {
                window.styleMask.remove(.resizable)
            }
        }
        func resize() {
            let desired = expanded ?? false
            DispatchQueue.main.async { [weak self] in
                guard let self, self.expanded == desired, let window = self.window, let screen = window.screen else { return }
                self.lockManualResizing()
                let target = PeopleWindowLayout.clampedFrame(current: window.frame, expanded: desired, visible: screen.visibleFrame)
                if abs(window.frame.width - target.width) > 0.5 || window.frame.origin != target.origin {
                    if self.reduceMotion || !window.isVisible {
                        window.setFrame(target, display: true, animate: false)
                    } else {
                        NSAnimationContext.runAnimationGroup { context in
                            context.duration = PeopleWindowAnimation.duration
                            context.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
                            window.animator().setFrame(target, display: true)
                        } completionHandler: { [weak self] in
                            self?.lockManualResizing()
                        }
                    }
                }
            }
        }
    }
}

struct CollectorHeightKey: PreferenceKey {
    static let defaultValue: CGFloat = 0
    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) { value = max(value, nextValue()) }
}
