import SwiftUI
import AppKit
import QuartzCore

enum PeopleWindowAnimation {
    static let duration: TimeInterval = 0.3
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
        view.lockManualResizing()
        guard view.expanded != expanded else { return }
        view.expanded = expanded
        view.resize()
    }
    final class WindowProbe: NSView {
        var resolve: ((NSWindow) -> Void)?
        var expanded: Bool?
        var reduceMotion = false
        private var styleObservation: NSKeyValueObservation?
        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            styleObservation = nil
            guard let window else { return }
            // SwiftUI may restore .resizable when content-size limits change.
            // Keep the native window locked throughout those layout updates.
            styleObservation = window.observe(\.styleMask, options: [.new]) { window, _ in
                if window.styleMask.contains(.resizable) {
                    window.styleMask.remove(.resizable)
                }
            }
            lockManualResizing()
            DispatchQueue.main.async { [weak self, weak window] in
                guard let window else { return }
                self?.resolve?(window)
                self?.resize()
            }
        }
        func lockManualResizing() {
            // The hosting view stays flexible during animations, but only the app
            // controls window size. Removing this style still permits setFrame.
            window?.styleMask.remove(.resizable)
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
