import SwiftUI
import AppKit

// The width change is deferred until SwiftUI has updated its content-size constraints.
struct PeopleWindowBridge: NSViewRepresentable {
    let expanded: Bool
    let resolved: (NSWindow) -> Void
    func makeNSView(context: Context) -> WindowProbe {
        let view = WindowProbe()
        view.resolve = resolved
        return view
    }
    func updateNSView(_ view: WindowProbe, context: Context) {
        view.resolve = resolved
        guard view.expanded != expanded else { return }
        view.expanded = expanded
        view.resize()
    }
    final class WindowProbe: NSView {
        var resolve: ((NSWindow) -> Void)?
        var expanded: Bool?
        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            guard let window else { return }
            DispatchQueue.main.async { [weak self, weak window] in
                guard let window else { return }
                self?.resolve?(window)
                self?.resize()
            }
        }
        func resize() {
            let desired = expanded ?? false
            DispatchQueue.main.async { [weak self] in
                guard let self, self.expanded == desired, let window = self.window, let screen = window.screen else { return }
                let target = PeopleWindowLayout.clampedFrame(current: window.frame, expanded: desired, visible: screen.visibleFrame)
                if abs(window.frame.width - target.width) > 0.5 || window.frame.origin != target.origin {
                    window.setFrame(target, display: true, animate: false)
                }
            }
        }
    }
}

struct CollectorHeightKey: PreferenceKey {
    static let defaultValue: CGFloat = 0
    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) { value = max(value, nextValue()) }
}
