import SwiftUI
import AppKit

// FF: SOCIAL SYNC VISIBILITY. Track actual windows, including close, hide, minimize
// and occlusion. SwiftUI onAppear alone can remain active after a window closes.
struct GroupSyncVisibility: NSViewRepresentable {
    func makeNSView(context: Context) -> ObserverView { ObserverView() }
    func updateNSView(_ view: ObserverView, context: Context) { view.reportVisibility() }
    static func dismantleNSView(_ view: ObserverView, coordinator: ()) { view.stop() }

    final class ObserverView: NSView {
        private let readerID = UUID()
        private var observers: [NSObjectProtocol] = []

        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            stop()
            guard let window else { return }
            for name in [NSWindow.didChangeOcclusionStateNotification, NSWindow.didMiniaturizeNotification,
                         NSWindow.didDeminiaturizeNotification, NSApplication.didHideNotification,
                         NSApplication.didUnhideNotification] {
                let object: AnyObject? = name == NSApplication.didHideNotification || name == NSApplication.didUnhideNotification ? nil : window
                observers.append(NotificationCenter.default.addObserver(forName: name, object: object, queue: .main) { [weak self] _ in
                    Task { @MainActor [weak self] in self?.reportVisibility() }
                })
            }
            observers.append(NotificationCenter.default.addObserver(forName: NSWindow.willCloseNotification, object: window, queue: .main) { [weak self] _ in
                // A closed SwiftUI Window can reuse the same NSView on reopen. Keep
                // observing its next visible transition until the view is dismantled.
                Task { @MainActor [weak self] in self?.markHidden() }
            })
            reportVisibility()
        }

        func reportVisibility() {
            let visible = window.map { $0.isVisible && !$0.isMiniaturized && $0.occlusionState.contains(.visible) } ?? false
            SocialController.shared.setGroupViewVisible(readerID, visible: visible && !NSApp.isHidden && !isHiddenOrHasHiddenAncestor)
        }

        private func markHidden() {
            SocialController.shared.setGroupViewVisible(readerID, visible: false)
        }

        func stop() {
            for observer in observers { NotificationCenter.default.removeObserver(observer) }
            observers.removeAll()
            markHidden()
        }
    }
}
