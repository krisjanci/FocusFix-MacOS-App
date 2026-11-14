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

// The collector has two sizes. Only the explicit mode button changes its size;
// native dragging, zooming, tiling and full-screen entry are disabled.
struct PeopleWindowBridge: NSViewRepresentable {
    let fullScreen: Bool
    let resolved: (NSWindow, CGSize) -> Void

    func makeNSView(context: Context) -> WindowProbe {
        let view = WindowProbe()
        view.resolve = resolved
        view.fullScreen = fullScreen
        return view
    }

    func updateNSView(_ view: WindowProbe, context: Context) {
        view.resolve = resolved
        let changed = view.fullScreen != fullScreen
        view.fullScreen = fullScreen
        DispatchQueue.main.async { [weak view] in view?.applyMode(changed: changed) }
    }

    final class WindowProbe: NSView {
        var resolve: ((NSWindow, CGSize) -> Void)?
        var fullScreen = false
        private var compactFrame: CGRect?
        private var observers: [NSObjectProtocol] = []

        deinit { observers.forEach(NotificationCenter.default.removeObserver) }

        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            observers.forEach(NotificationCenter.default.removeObserver)
            observers.removeAll()
            guard let window else { return }
            for name in [NSWindow.didChangeScreenNotification, NSWindow.didChangeScreenProfileNotification] {
                observers.append(NotificationCenter.default.addObserver(forName: name, object: window, queue: .main) { [weak self] _ in
                    self?.applyMode(changed: false)
                })
            }
            observers.append(NotificationCenter.default.addObserver(forName: NSApplication.didChangeScreenParametersNotification, object: nil, queue: .main) { [weak self] _ in
                self?.applyMode(changed: false)
            })
            DispatchQueue.main.async { [weak self] in self?.applyMode(changed: false) }
        }

        func applyMode(changed: Bool) {
            guard let window, let screen = window.screen else { return }
            window.styleMask.remove(.resizable)
            window.collectionBehavior.remove(.fullScreenPrimary)
            window.collectionBehavior.insert(.fullScreenNone)
            window.standardWindowButton(.zoomButton)?.isEnabled = false
            let size = window.contentRect(forFrameRect: screen.visibleFrame).size
            resolve?(window, size)
            if fullScreen {
                if compactFrame == nil { compactFrame = window.frame }
                window.setFrame(screen.visibleFrame, display: true)
            } else if changed, let saved = compactFrame {
                let visible = screen.visibleFrame
                let restored = CGRect(x: min(max(saved.minX, visible.minX), visible.maxX - saved.width),
                                      y: min(max(saved.minY, visible.minY), visible.maxY - saved.height),
                                      width: saved.width, height: saved.height)
                window.setFrame(restored, display: true)
                compactFrame = nil
            }
        }
    }
}

struct CollectorHeightKey: PreferenceKey {
    static let defaultValue: CGFloat = 0
    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) { value = max(value, nextValue()) }
}
