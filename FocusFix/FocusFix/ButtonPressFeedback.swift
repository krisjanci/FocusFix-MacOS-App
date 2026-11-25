import SwiftUI
import AppKit

// Observe only this app's mouse events and return them untouched. Native buttons
// retain their action timing, keyboard shortcuts, roles, focus and visual styles.
@MainActor private final class ButtonPressCoordinator {
    static let shared = ButtonPressCoordinator()
    private final class WeakMarker {
        weak var value: ButtonPressMarker?
        init(_ value: ButtonPressMarker) { self.value = value }
    }
    private var markers: [ObjectIdentifier: WeakMarker] = [:]
    private weak var active: ButtonPressMarker?
    private var monitor: Any?
    private var releaseTimer: Timer?
    private var observers: [NSObjectProtocol] = []

    func register(_ marker: ButtonPressMarker) {
        markers[ObjectIdentifier(marker)] = WeakMarker(marker)
        guard monitor == nil else { return }
        monitor = NSEvent.addLocalMonitorForEvents(matching: [.leftMouseDown, .leftMouseDragged, .leftMouseUp]) { [weak self] event in
            MainActor.assumeIsolated { self?.receive(event) }
            return event
        }
        for name in [NSApplication.didResignActiveNotification, NSWindow.didResignKeyNotification, NSMenu.didEndTrackingNotification] {
            observers.append(NotificationCenter.default.addObserver(forName: name, object: nil, queue: .main) { [weak self] _ in
                MainActor.assumeIsolated { self?.release() }
            })
        }
    }

    func unregister(_ marker: ButtonPressMarker) {
        markers.removeValue(forKey: ObjectIdentifier(marker))
        if active === marker {
            active = nil; stopReleaseTimer()
            // Reparenting a native view need not dismiss its SwiftUI view. Clear
            // that press after layout, unless a fresh press has already begun.
            DispatchQueue.main.async { [weak self, weak marker] in
                guard let self, let marker, self.active !== marker else { return }
                marker.pressed?(false)
            }
        }
        markers = markers.filter { $0.value.value != nil }
        guard markers.isEmpty else { return }
        if let monitor { NSEvent.removeMonitor(monitor) }
        monitor = nil
        observers.forEach(NotificationCenter.default.removeObserver)
        observers.removeAll()
    }

    private func contains(_ event: NSEvent, in marker: ButtonPressMarker) -> Bool {
        guard marker.enabled, let window = marker.window, event.window === window,
              !marker.isHiddenOrHasHiddenAncestor else { return false }
        let point = marker.convert(event.locationInWindow, from: nil)
        // AppKit's visibleRect can extend beyond an unclipped view's bounds.
        // Test both so nearby controls never react to another button's click.
        return ButtonPressGeometry.contains(point, bounds: marker.bounds, visibleRect: marker.visibleRect)
    }

    private func receive(_ event: NSEvent) {
        switch event.type {
        case .leftMouseDown:
            release()
            let candidates = markers.values.compactMap(\.value).filter { contains(event, in: $0) }
            // If a control contains another control, only the innermost reacts.
            active = candidates.min { $0.bounds.width * $0.bounds.height < $1.bounds.width * $1.bounds.height }
            active?.pressed?(true)
            guard active != nil else { return }
            // Native AppKit controls can consume mouse-up in their tracking loop.
            // A common-mode timer observes release without intercepting that loop.
            let timer = Timer(timeInterval: 1.0 / 60, repeats: true) { [weak self] _ in
                MainActor.assumeIsolated {
                    if NSEvent.pressedMouseButtons & 1 == 0 { self?.release() }
                }
            }
            releaseTimer = timer
            RunLoop.main.add(timer, forMode: .common)
        case .leftMouseDragged:
            if let active { active.pressed?(active.holdsOutsideBounds || contains(event, in: active)) }
        case .leftMouseUp: release()
        default: break
        }
    }

    private func stopReleaseTimer() { releaseTimer?.invalidate(); releaseTimer = nil }
    private func release() {
        active?.pressed?(false)
        active = nil
        stopReleaseTimer()
    }
}

@MainActor private final class ButtonPressMarker: NSView {
    var enabled = true
    var holdsOutsideBounds = false
    var pressed: ((Bool) -> Void)?
    override func hitTest(_ point: NSPoint) -> NSView? { nil }
    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        if window != nil { ButtonPressCoordinator.shared.register(self) }
        else { ButtonPressCoordinator.shared.unregister(self) }
    }
}

private struct ButtonPressProbe: NSViewRepresentable {
    let enabled: Bool
    var holdsOutsideBounds = false
    let pressed: (Bool) -> Void
    func makeNSView(context: Context) -> ButtonPressMarker {
        let marker = ButtonPressMarker()
        marker.enabled = enabled; marker.holdsOutsideBounds = holdsOutsideBounds; marker.pressed = pressed
        return marker
    }
    func updateNSView(_ marker: ButtonPressMarker, context: Context) {
        marker.enabled = enabled; marker.holdsOutsideBounds = holdsOutsideBounds; marker.pressed = pressed
    }
    static func dismantleNSView(_ marker: ButtonPressMarker, coordinator: ()) {
        ButtonPressCoordinator.shared.unregister(marker)
        marker.pressed = nil
    }
}

private struct ButtonPressFeedback: ViewModifier {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.isEnabled) private var enabled
    @State private var pressed = false
    @State private var pressedAt = ContinuousClock.now
    @State private var releaseTask: Task<Void, Never>?

    func body(content: Content) -> some View {
        content
            .scaleEffect(pressed && enabled && !reduceMotion ? 0.97 : 1)
            // The probe never receives a hit and keeps the unscaled hit area.
            .background(ButtonPressProbe(enabled: enabled && !reduceMotion, pressed: updatePress).accessibilityHidden(true))
            .onDisappear { reset() }
            .onChange(of: enabled) { _, value in if !value { reset() } }
            .onChange(of: reduceMotion) { _, value in if value { reset() } }
    }

    private func updatePress(_ value: Bool) {
        guard enabled, !reduceMotion else { reset(); return }
        if value {
            releaseTask?.cancel()
            guard !pressed else { return }
            pressedAt = .now
            withAnimation(.easeOut(duration: 0.06)) { pressed = true }
        } else {
            guard pressed else { return }
            releaseTask?.cancel()
            // Make a quick click visible without delaying the button's action.
            let remaining = max(Duration.zero, .milliseconds(70) - pressedAt.duration(to: .now))
            releaseTask = Task { @MainActor in
                do { try await Task.sleep(for: remaining) } catch { return }
                guard !Task.isCancelled else { return }
                withAnimation(.spring(response: 0.24, dampingFraction: 0.72)) { pressed = false }
            }
        }
    }

    private func reset() {
        releaseTask?.cancel(); releaseTask = nil
        var transaction = Transaction()
        transaction.disablesAnimations = true
        withTransaction(transaction) { pressed = false }
    }
}

extension View {
    func buttonPressFeedback() -> some View { modifier(ButtonPressFeedback()) }
    func checklistPressFeedback(dragging: Bool, released: @escaping () -> Void) -> some View {
        modifier(ChecklistPressFeedback(dragging: dragging, released: released))
    }
}

private struct ChecklistPressFeedback: ViewModifier {
    let dragging: Bool
    let released: () -> Void
    @State private var pressed = false

    func body(content: Content) -> some View {
        content
            .background(Color.primary.opacity(pressed || dragging ? 0.09 : 0), in: RoundedRectangle(cornerRadius: 8))
            .background(ButtonPressProbe(enabled: true, holdsOutsideBounds: true) { value in
                pressed = value
                if !value { released() }
            }.accessibilityHidden(true))
            .onDisappear { pressed = false; released() }
    }
}
