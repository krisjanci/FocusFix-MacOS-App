import AppKit
import ApplicationServices
import Combine

@MainActor
final class ActivityTracker: ObservableObject {
    static let shared = ActivityTracker()
    @Published private(set) var isRecording = false
    @Published private(set) var elapsed: Double = 0
    @Published private(set) var eventCount = 0
    @Published private(set) var movementRows = 0
    @Published private(set) var sessionFolder: URL?
    @Published private(set) var message = "Ready when you are."
    @Published private(set) var needsPermission = false
    @Published private(set) var hasError = false
    private var writer: RecordingWriter?
    private var mouse = MouseAccumulator(initialPosition: .zero)
    private var keys = KeyTiming()
    private var startedAt = Date()
    private var startUptime: Double = 0
    private var eventsRecorded = 0
    private var rowsRecorded = 0
    private var lastApplication: pid_t?
    private var globalMonitor: Any?
    private var localMonitor: Any?
    private var timer: Timer?
    private var backgroundActivity: NSObjectProtocol?
    private var workspaceObservers: [NSObjectProtocol] = []
    private var quitObserver: NSObjectProtocol?

    var formattedTime: String {
        let s = Int(elapsed)
        return String(format: "%02d:%02d:%02d", s / 3600, s / 60 % 60, s % 60)
    }
    private var now: Double { max(0, ProcessInfo.processInfo.systemUptime - startUptime) }
    private init() {
        quitObserver = NotificationCenter.default.addObserver(
            forName: NSApplication.willTerminateNotification, object: nil, queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated { self?.stop(reason: "app_quit") }
        }
    }
    func requestPermission() {
        let key = kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String
        _ = AXIsProcessTrustedWithOptions([key: true] as CFDictionary)
        needsPermission = !AXIsProcessTrusted()
        message = "Enable FocusFix in System Settings → Privacy & Security → Accessibility, then press Start."
    }
    func start() {
        guard !isRecording else { return }
        guard AXIsProcessTrusted() else {
            needsPermission = true
            message = "Keyboard recording needs Accessibility access. Allow access, then start again."
            return
        }
        needsPermission = false
        hasError = false
        do {
            let support = try FileManager.default.url(for: .applicationSupportDirectory,
                in: .userDomainMask, appropriateFor: nil, create: true)
            let root = support.appendingPathComponent("FocusFix/Sessions", isDirectory: true)
            startedAt = Date()
            let newWriter = try RecordingWriter(root: root, id: UUID().uuidString, startedAt: startedAt)
            writer = newWriter
            sessionFolder = newWriter.folder
            startUptime = ProcessInfo.processInfo.systemUptime
            elapsed = 0
            eventsRecorded = 0
            rowsRecorded = 0
            eventCount = 0
            movementRows = 0
            keys = KeyTiming()
            mouse = MouseAccumulator(initialPosition: CGEvent(source: nil)?.location ?? .zero)
            lastApplication = NSWorkspace.shared.frontmostApplication?.processIdentifier
            isRecording = true
            // Avoid App Nap while collecting; do not prevent system sleep.
            backgroundActivity = ProcessInfo.processInfo.beginActivity(
                options: .userInitiatedAllowingIdleSystemSleep, reason: "Recording a FocusFix session")
            try record(type: "session_start", at: 0)
            installMonitors()
            guard globalMonitor != nil, localMonitor != nil else {
                stop(reason: "monitor_unavailable")
                hasError = true
                message = "Could not attach input monitors. Check Accessibility access and relaunch FocusFix."
                return
            }
            let clock = Timer(timeInterval: 1, repeats: true) { [weak self] _ in
                MainActor.assumeIsolated { self?.tick() }
            }
            timer = clock
            RunLoop.main.add(clock, forMode: .common)
            message = "Recording locally. You can close this window and keep working."
        } catch { fail(error) }
    }
    func stop(reason: String = "user_stop") {
        guard isRecording else { return }
        let end = now
        isRecording = false
        removeMonitors()
        do {
            append(mouse.stop(at: end))
            try record(type: "session_stop", at: end)
            try writer?.finish(startedAt: startedAt, duration: end, reason: reason)
            message = reason == "user_stop" ? "Session saved. Your CSV files are ready." : "Session saved and stopped (\(reason.replacingOccurrences(of: "_", with: " ")))."
        } catch {
            hasError = true
            message = "Saving failed: \(error.localizedDescription). Existing files have been kept."
        }
        elapsed = end
        eventCount = eventsRecorded
        movementRows = rowsRecorded
        writer = nil
    }
    private func tick() {
        guard isRecording else { return }
        guard AXIsProcessTrusted() else {
            stop(reason: "permission_lost")
            needsPermission = true
            return
        }
        do {
            elapsed = now
            append(mouse.advance(to: elapsed))
            try writer?.flush()
            eventCount = eventsRecorded
            movementRows = rowsRecorded
        } catch { fail(error) }
    }
    private func installMonitors() {
        let mask: NSEvent.EventTypeMask = [.keyDown, .keyUp, .flagsChanged,
            .leftMouseDown, .leftMouseUp, .rightMouseDown, .rightMouseUp,
            .otherMouseDown, .otherMouseUp, .scrollWheel, .mouseMoved,
            .leftMouseDragged, .rightMouseDragged, .otherMouseDragged]
        // Global sees other apps; local sees FocusFix. Return input unchanged.
        globalMonitor = NSEvent.addGlobalMonitorForEvents(matching: mask) { [weak self] event in
            MainActor.assumeIsolated { self?.receive(event) }
        }
        localMonitor = NSEvent.addLocalMonitorForEvents(matching: mask) { [weak self] event in
            MainActor.assumeIsolated { self?.receive(event) }
            return event
        }
        let center = NSWorkspace.shared.notificationCenter
        workspaceObservers.append(center.addObserver(forName: NSWorkspace.didActivateApplicationNotification,
            object: nil, queue: .main) { [weak self] notification in
                MainActor.assumeIsolated {
                    guard let self, self.isRecording,
                          let app = notification.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication,
                          app.processIdentifier != self.lastApplication else { return }
                    self.lastApplication = app.processIdentifier
                    do { try self.record(type: "app_switch", at: self.now) }
                    catch { self.fail(error) }
                }
            })
        for name in [NSWorkspace.willSleepNotification, NSWorkspace.screensDidSleepNotification,
                     NSWorkspace.sessionDidResignActiveNotification] {
            workspaceObservers.append(center.addObserver(forName: name, object: nil, queue: .main) { [weak self] _ in
                MainActor.assumeIsolated { self?.stop(reason: "sleep_or_inactive_session") }
            })
        }
    }
    private func receive(_ event: NSEvent) {
        guard isRecording else { return }
        let time = now
        do {
            switch event.type {
            case .mouseMoved, .leftMouseDragged, .rightMouseDragged, .otherMouseDragged:
                if let point = event.cgEvent?.location { append(mouse.move(to: point, at: time)) }
            case .keyDown:
                keys.down(code: event.keyCode, at: time, repeated: event.isARepeat)
                try record(type: isDelete(event) ? "delete_down" : "key_down", at: time, repeated: event.isARepeat)
            case .keyUp:
                let held = keys.up(code: event.keyCode, at: time)
                try record(type: isDelete(event) ? "delete_up" : "key_up", at: time, hold: held)
            case .flagsChanged: try record(type: "modifier_change", at: time)
            case .leftMouseDown: try record(type: "left_click_down", at: time)
            case .leftMouseUp: try record(type: "left_click_up", at: time)
            case .rightMouseDown: try record(type: "right_click_down", at: time)
            case .rightMouseUp: try record(type: "right_click_up", at: time)
            case .otherMouseDown: try record(type: "other_click_down", at: time)
            case .otherMouseUp: try record(type: "other_click_up", at: time)
            case .scrollWheel:
                try writer?.event(time: time, type: "scroll", scrollX: event.scrollingDeltaX,
                    scrollY: event.scrollingDeltaY, precise: event.hasPreciseScrollingDeltas)
                eventsRecorded += 1
            default: break
            }
        } catch { fail(error) }
    }
    private func isDelete(_ event: NSEvent) -> Bool { event.keyCode == 51 || event.keyCode == 117 }
    private func record(type: String, at time: Double, repeated: Bool? = nil, hold: Double? = nil) throws {
        try writer?.event(time: time, type: type, repeated: repeated, hold: hold)
        eventsRecorded += 1
    }
    private func append(_ rows: [MouseSummary]) {
        writer?.append(rows)
        rowsRecorded += rows.count
    }
    private func fail(_ error: Error) {
        stop(reason: "recording_error")
        writer = nil
        hasError = true
        message = "Recording stopped: \(error.localizedDescription). Existing files have been kept."
    }
    private func removeMonitors() {
        if let backgroundActivity { ProcessInfo.processInfo.endActivity(backgroundActivity) }
        backgroundActivity = nil
        timer?.invalidate()
        timer = nil
        if let globalMonitor { NSEvent.removeMonitor(globalMonitor) }
        if let localMonitor { NSEvent.removeMonitor(localMonitor) }
        globalMonitor = nil
        localMonitor = nil
        workspaceObservers.forEach { NSWorkspace.shared.notificationCenter.removeObserver($0) }
        workspaceObservers.removeAll()
    }
    func showFiles() {
        if let sessionFolder { NSWorkspace.shared.open(sessionFolder) }
    }
    func exportSession() {
        guard !isRecording, let sessionFolder else { return }
        let panel = NSOpenPanel()
        panel.title = "Export session CSV files"
        panel.prompt = "Export here"
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.canCreateDirectories = true
        panel.allowsMultipleSelection = false
        guard panel.runModal() == .OK, let destination = panel.url else { return }
        do {
            let copy = destination.appendingPathComponent("FocusFix-\(sessionFolder.lastPathComponent)")
            try FileManager.default.copyItem(at: sessionFolder, to: copy)
            hasError = false
            message = "Session exported. The original local recording is also kept."
        } catch {
            hasError = true
            message = "Export failed: \(error.localizedDescription). Your original recording is safe."
        }
    }
}
