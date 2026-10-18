import AppKit
import ApplicationServices
import Combine
import UserNotifications

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
    @Published private(set) var sessions: [SavedSession] = []
    @Published private(set) var libraryError: String?
    @Published private(set) var breakPhase: BreakPolicy.Phase = .work
    @Published private(set) var breakPromptPending = false
    @Published private(set) var currentBreak: BreakRecord?
    @Published private(set) var latestBreak: BreakRecord?
    @Published private(set) var secondsSinceBreak: Double = 0
    @Published private(set) var notificationNotice: String?
    @Published private(set) var notificationPermission: NotificationPermission = .checking
    @Published private(set) var notificationPermissionBusy = false
    @Published var breakSetupPresented = false
    @Published var sessionCheckInPresented = false
    private var sessionCheckIn: CheckInPrompt?
    private var breakCheckIn: CheckInPrompt?
    private var activityPhase: String { breakCheckIn == nil ? breakPolicy.activityPhase : "check_in" }
    var openMainWindow: (() -> Void)?
    private var breakPolicy = BreakPolicy()
    private let breakNotifications = BreakNotifications()
    private let notificationAccess = NotificationAccess(client: SystemNotificationPermissionClient())
    private var returnPoint: CGPoint = .zero
    private var returnDistance: Double = 0
    private var returnWindowStart: Double = 0
    private var suspendedBy: Set<String> = []
    private var writer: RecordingWriter?
    private var mouse = MouseAccumulator(initialPosition: .zero)
    private var keys = KeyTiming()
    private var startedAt = Date()
    private let clock = ContinuousClock()
    private var startInstant = ContinuousClock.now
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
    private var now: Double {
        let duration = startInstant.duration(to: clock.now).components
        return max(0, Double(duration.seconds) + Double(duration.attoseconds) / 1e18)
    }
    private init() {
        refreshSessions()
        quitObserver = NotificationCenter.default.addObserver(
            forName: NSApplication.willTerminateNotification, object: nil, queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated { self?.stop(reason: "app_quit") }
        }
    }
    func configureNotifications() {
        notificationAccess.onChange = { [weak self] state, busy in
            self?.notificationPermission = state
            self?.notificationPermissionBusy = busy
        }
        breakNotifications.onStatus = { [weak self] in self?.notificationNotice = $0 }
        breakNotifications.onAction = { [weak self] session, token, action in
            self?.notificationAction(session: session, token: token, action: action)
        }
        breakNotifications.configure()
        refreshNotificationPermission()
    }
    func refreshNotificationPermission() {
        Task { await notificationAccess.refresh() }
    }
    func enableNotifications() {
        Task { await notificationAccess.enable() }
    }
    func openNotificationSettings() {
        // Opens settings only; FocusFix never changes system permissions itself.
        guard let url = URL(string: "x-apple.systempreferences:com.apple.preference.notifications") else { return }
        if !NSWorkspace.shared.open(url) {
            notificationNotice = "Open System Settings → Notifications → FocusFix and turn on Allow Notifications and Banners."
        }
    }
    func requestPermission() {
        let key = kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String
        _ = AXIsProcessTrustedWithOptions([key: true] as CFDictionary)
        needsPermission = !AXIsProcessTrusted()
        message = "Enable FocusFix in System Settings → Privacy & Security → Accessibility, then press Start."
    }
    func requestStart() {
        guard !isRecording, !sessionCheckInPresented else { return }
        guard AXIsProcessTrusted() else {
            needsPermission = true
            message = "Keyboard recording needs Accessibility access. Allow access, then start again."
            return
        }
        needsPermission = false
        sessionCheckIn = CheckInPrompt(elapsed: 0)
        sessionCheckInPresented = true
    }
    func cancelSessionCheckIn() { sessionCheckIn = nil }
    func completeSessionCheckIn(fatigue: Int?) {
        guard let prompt = sessionCheckIn, fatigue.map({ (0...10).contains($0) }) ?? true else { return }
        sessionCheckIn = nil
        sessionCheckInPresented = false
        start(fatigue: fatigue, prompt: prompt)
    }
    private func start(fatigue: Int?, prompt: CheckInPrompt) {
        guard !isRecording else { return }
        guard AXIsProcessTrusted() else {
            needsPermission = true
            message = "Keyboard recording needs Accessibility access. Allow access, then start again."
            return
        }
        needsPermission = false
        hasError = false
        do {
            let root = try SessionFiles.root()
            startedAt = Date()
            let newWriter = try RecordingWriter(root: root, id: UUID().uuidString, startedAt: startedAt)
            writer = newWriter
            sessionFolder = newWriter.folder
            startInstant = clock.now
            let beforeStart = prompt.instant.duration(to: startInstant).components
            let checkInDuration = Double(beforeStart.seconds) + Double(beforeStart.attoseconds) / 1e18
            try newWriter.logSurvey(SurveyEntry(id: prompt.id, context: .sessionStart,
                status: fatigue == nil ? .skipped : .answered, breakID: "", shownAt: prompt.shownAt,
                answeredAt: startedAt, shownElapsed: -checkInDuration, answeredElapsed: 0,
                fatigue: fatigue, workload: nil))
            suspendedBy = []
            elapsed = 0
            eventsRecorded = 0
            rowsRecorded = 0
            eventCount = 0
            movementRows = 0
            keys = KeyTiming()
            breakPolicy = BreakPolicy()
            breakSetupPresented = false
            breakNotifications.clear()
            updateBreakUI(at: 0)
            mouse = MouseAccumulator(initialPosition: CGEvent(source: nil)?.location ?? .zero)
            lastApplication = NSWorkspace.shared.frontmostApplication?.processIdentifier
            isRecording = true
            refreshSessions()
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
            refreshNotificationPermission()
        } catch { fail(error) }
    }
    func stop(reason: String = "user_stop") {
        guard isRecording else { return }
        let end = now
        // Close an abandoned break setup before finishing the recording.
        var checkInSaveError: Error?
        do { try finishBreakCheckIn(status: .cancelled, at: end) }
        catch { checkInSaveError = error }
        isRecording = false
        removeMonitors()
        breakNotifications.clear()
        breakSetupPresented = false
        do {
            if breakPolicy.phase != .resting && suspendedBy.isEmpty { append(mouse.stop(at: end)) }
            if let entry = breakPolicy.finish(at: end, reason: "session_\(reason)") {
                try writer?.logBreak(entry)
            } else if breakPolicy.promptID != nil {
                try writer?.logBreak(breakPolicy.entry(at: end, action: "prompt_cancelled_session_end"))
            }
            try record(type: "session_stop", at: end)
            try writer?.finish(startedAt: startedAt, duration: end, reason: reason)
            message = reason == "user_stop" ? "Session saved. Your CSV files are ready." : "Session saved and stopped (\(reason.replacingOccurrences(of: "_", with: " ")))."
            if let checkInSaveError {
                hasError = true
                message = "Session stopped, but the check-in could not be saved: \(checkInSaveError.localizedDescription)"
            }
        } catch {
            hasError = true
            message = "Saving failed: \(error.localizedDescription). Existing files have been kept."
        }
        elapsed = end
        eventCount = eventsRecorded
        movementRows = rowsRecorded
        writer = nil
        updateBreakUI(at: end)
        suspendedBy = []
        refreshSessions()
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
            if suspendedBy.isEmpty {
                if breakCheckIn == nil { try advanceBreakClock(at: elapsed) }
                if breakPolicy.phase != .resting { append(mouse.advance(to: elapsed)) }
            }
            try writer?.flush()
            eventCount = eventsRecorded
            movementRows = rowsRecorded
            updateBreakUI(at: elapsed)
        } catch { fail(error) }
    }
    private func installMonitors() {
        let mask: NSEvent.EventTypeMask = [.keyDown, .keyUp, .flagsChanged,
            .leftMouseDown, .leftMouseUp, .rightMouseDown, .rightMouseUp,
            .otherMouseDown, .otherMouseUp, .scrollWheel, .mouseMoved,
            .leftMouseDragged, .rightMouseDragged, .otherMouseDragged]
        // Global sees other apps; local sees FocusFix. Return input unchanged.
        globalMonitor = NSEvent.addGlobalMonitorForEvents(matching: mask) { [weak self] event in
            MainActor.assumeIsolated { self?.receive(event, outsideApp: true) }
        }
        localMonitor = NSEvent.addLocalMonitorForEvents(matching: mask) { [weak self] event in
            MainActor.assumeIsolated { self?.receive(event, outsideApp: false) }
            return event
        }
        let center = NSWorkspace.shared.notificationCenter
        workspaceObservers.append(center.addObserver(forName: NSWorkspace.didActivateApplicationNotification,
            object: nil, queue: .main) { [weak self] notification in
                MainActor.assumeIsolated {
                    guard let self, self.isRecording, self.suspendedBy.isEmpty,
                          let app = notification.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication,
                          app.processIdentifier != self.lastApplication else { return }
                    self.lastApplication = app.processIdentifier
                    do {
                        let time = self.now
                        if self.breakPolicy.phase != .work { try self.advanceBreakClock(at: time) }
                        // App activation alone is not proof of a person's return.
                        if self.breakPolicy.phase != .resting {
                            try self.record(type: "app_switch", at: time)
                        }
                    }
                    catch { self.fail(error) }
                }
            })
        let suspensions: [(Notification.Name, Notification.Name, String)] = [
            (NSWorkspace.willSleepNotification, NSWorkspace.didWakeNotification, "system"),
            (NSWorkspace.screensDidSleepNotification, NSWorkspace.screensDidWakeNotification, "screen"),
            (NSWorkspace.sessionDidResignActiveNotification, NSWorkspace.sessionDidBecomeActiveNotification, "login")
        ]
        for (name, wake, reason) in suspensions {
            workspaceObservers.append(center.addObserver(forName: name, object: nil, queue: .main) { [weak self] _ in
                MainActor.assumeIsolated { self?.suspendForBreak(reason) }
            })
            workspaceObservers.append(center.addObserver(forName: wake, object: nil, queue: .main) { [weak self] _ in
                MainActor.assumeIsolated { self?.resumeAfterSuspension(reason) }
            })
        }
    }
    private func receive(_ event: NSEvent, outsideApp: Bool) {
        guard isRecording, suspendedBy.isEmpty else { return }
        let time = now
        do {
            if breakPolicy.phase != .work { try advanceBreakClock(at: time) }
            if breakPolicy.phase != .work {
                if outsideApp && isReturnInput(event, at: time) {
                    try finishBreak(at: time, reason: "outside_app_input")
                } else if breakPolicy.phase == .resting {
                    return // No detailed activity is written during the planned break.
                }
            }
            // A press/release, scroll or actual pointer movement resets work-idle timing.
            if event.type != .mouseMoved || event.deltaX != 0 || event.deltaY != 0 {
                breakPolicy.input(at: time)
            }
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
                    scrollY: event.scrollingDeltaY, precise: event.hasPreciseScrollingDeltas,
                    activityPhase: activityPhase,
                    secondsSinceLastBreak: breakPolicy.phase == .work ? breakPolicy.sinceLastBreak(at: time) : nil)
                eventsRecorded += 1
            default: break
            }
        } catch { fail(error) }
    }
    private func isDelete(_ event: NSEvent) -> Bool { event.keyCode == 51 || event.keyCode == 117 }
    private func record(type: String, at time: Double, repeated: Bool? = nil, hold: Double? = nil) throws {
        try writer?.event(time: time, type: type, repeated: repeated, hold: hold,
            activityPhase: activityPhase,
            secondsSinceLastBreak: breakPolicy.phase == .work ? breakPolicy.sinceLastBreak(at: time) : nil)
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

    private func updateBreakUI(at time: Double) {
        breakPhase = breakPolicy.phase
        breakPromptPending = isRecording && breakPolicy.promptID != nil
        currentBreak = breakPolicy.activeBreak
        latestBreak = breakPolicy.lastBreak
        secondsSinceBreak = breakPolicy.sinceLastBreak(at: time)
    }
    private func resetMouse(at time: Double, phase: String) {
        let point = CGEvent(source: nil)?.location ?? .zero
        mouse = MouseAccumulator(initialPosition: point, start: time, activityPhase: phase,
            workReference: phase == "work" ? breakPolicy.lastBreakEnd : nil)
        returnPoint = point
        returnDistance = 0
        returnWindowStart = time
        keys = KeyTiming() // Never match a key press across a paused interval.
    }
    private func advanceBreakClock(at time: Double, samplingStart: Double? = nil) throws {
        guard let entry = breakPolicy.tick(at: time) else { return }
        try writer?.logBreak(entry)
        if entry.action == "timer_elapsed" {
            resetMouse(at: samplingStart ?? entry.time, phase: "awaiting_return")
            if let record = breakPolicy.activeBreak {
                breakNotifications.send(session: sessionFolder?.lastPathComponent ?? "", token: record.id, finished: true)
            }
        } else if entry.action == "prompt" {
            breakNotifications.send(session: sessionFolder?.lastPathComponent ?? "", token: entry.promptID, finished: false)
        }
        updateBreakUI(at: time)
    }
    func chooseBreak() {
        guard isRecording, breakPolicy.phase == .work, breakCheckIn == nil else { return }
        let time = now
        do {
            append(mouse.stop(at: time))
            breakCheckIn = CheckInPrompt(elapsed: time)
            resetMouse(at: time, phase: "check_in")
            try record(type: "check_in_start", at: time)
            breakSetupPresented = true
        } catch { fail(error) }
    }
    func cancelBreakCheckIn() {
        guard isRecording else { breakCheckIn = nil; return }
        do { try finishBreakCheckIn(status: .cancelled, at: now) }
        catch { fail(error) }
    }
    private func finishBreakCheckIn(status: CheckInStatus, at time: Double,
                                    breakID: String = "", fatigue: Int? = nil, workload: Int? = nil) throws {
        guard let prompt = breakCheckIn else { return }
        append(mouse.stop(at: time))
        // Clear before writing so an I/O failure cannot recursively try the same check-in.
        breakCheckIn = nil
        try writer?.logSurvey(SurveyEntry(id: prompt.id, context: .beforeBreak, status: status,
            breakID: breakID, shownAt: prompt.shownAt, answeredAt: Date(),
            shownElapsed: prompt.elapsed, answeredElapsed: time, fatigue: fatigue, workload: workload))
        try record(type: "check_in_end", at: time)
        if breakPolicy.phase == .work {
            resetMouse(at: time, phase: "work")
            breakPolicy.input(at: time)
        }
    }
    func beginBreak(minutes: Double, activity: String, fatigue: Int?, workload: Int?) {
        guard isRecording, breakCheckIn != nil,
              (fatigue == nil && workload == nil) ||
                (fatigue.map({ (0...10).contains($0) }) == true && workload.map({ (0...10).contains($0) }) == true)
        else { return }
        let label = String(activity.trimmingCharacters(in: .whitespacesAndNewlines).prefix(120))
        let time = now
        guard let entry = breakPolicy.begin(at: time, seconds: minutes * 60, activity: label) else { return }
        do {
            try finishBreakCheckIn(status: fatigue == nil ? .skipped : .answered, at: time,
                breakID: entry.record?.id ?? "", fatigue: fatigue, workload: workload)
            try writer?.logBreak(entry)
            keys = KeyTiming()
            returnPoint = CGEvent(source: nil)?.location ?? .zero
            returnWindowStart = time
            returnDistance = 0
            breakSetupPresented = false
            breakNotifications.clear()
            elapsed = time
            updateBreakUI(at: time)
        } catch { fail(error) }
    }
    func deferBreak(snooze: Bool) {
        guard isRecording, let entry = breakPolicy.deferPrompt(at: now, snooze: snooze) else { return }
        do {
            try finishBreakCheckIn(status: .cancelled, at: now)
            try writer?.logBreak(entry)
            breakNotifications.clear()
            breakSetupPresented = false
            updateBreakUI(at: now)
        } catch { fail(error) }
    }
    func returnFromBreak() {
        guard isRecording, breakPolicy.activeBreak != nil else { return }
        do {
            try advanceBreakClock(at: now)
            try finishBreak(at: now, reason: "explicit_return")
        } catch { fail(error) }
    }
    private func finishBreak(at time: Double, reason: String) throws {
        if breakPolicy.phase == .awaitingReturn && suspendedBy.isEmpty { append(mouse.stop(at: time)) }
        guard let entry = breakPolicy.finish(at: time, reason: reason) else { return }
        try writer?.logBreak(entry)
        resetMouse(at: time, phase: "work")
        breakNotifications.clear()
        elapsed = time
        updateBreakUI(at: time)
    }
    private func suspendForBreak(_ reason: String) {
        guard isRecording else { return }
        guard breakPolicy.phase != .work else {
            stop(reason: "sleep_or_inactive_session")
            return
        }
        let time = now
        do {
            if suspendedBy.isEmpty && breakPolicy.phase == .awaitingReturn { append(mouse.stop(at: time)) }
            guard suspendedBy.insert(reason).inserted else { return }
            try writer?.logBreak(breakPolicy.entry(at: time, action: "suspended_\(reason)", record: breakPolicy.activeBreak))
        } catch { fail(error) }
    }
    private func resumeAfterSuspension(_ reason: String) {
        guard isRecording, suspendedBy.remove(reason) != nil else { return }
        let time = now
        do {
            try writer?.logBreak(breakPolicy.entry(at: time, action: "resumed_\(reason)", record: breakPolicy.activeBreak))
            guard suspendedBy.isEmpty else { return }
            // ContinuousClock includes sleep. Do not manufacture mouse intervals
            // for time when the session/display/system was unavailable.
            try advanceBreakClock(at: time, samplingStart: time)
            resetMouse(at: time, phase: breakPolicy.activityPhase)
            elapsed = time
            updateBreakUI(at: time)
        } catch { fail(error) }
    }
    func confirmBreakActivity(_ activity: String) {
        guard isRecording else { return }
        let label = String(activity.trimmingCharacters(in: .whitespacesAndNewlines).prefix(120))
        guard let entry = breakPolicy.updateActivity(label, at: now) else { return }
        do { try writer?.logBreak(entry); updateBreakUI(at: now) }
        catch { fail(error) }
    }
    private func isReturnInput(_ event: NSEvent, at time: Double) -> Bool {
        switch event.type {
        case .keyDown: return !event.isARepeat
        case .leftMouseDown, .rightMouseDown, .otherMouseDown: return true
        case .scrollWheel:
            return event.momentumPhase.isEmpty && (event.scrollingDeltaX != 0 || event.scrollingDeltaY != 0)
        case .mouseMoved, .leftMouseDragged, .rightMouseDragged, .otherMouseDragged:
            guard let point = event.cgEvent?.location else { return false }
            if time - returnWindowStart > 1 { returnDistance = 0; returnWindowStart = time }
            returnDistance += hypot(point.x - returnPoint.x, point.y - returnPoint.y)
            returnPoint = point
            return returnDistance >= 20
        default: return false
        }
    }
    private func notificationAction(session: String, token: String, action: String) {
        guard isRecording, sessionFolder?.lastPathComponent == session else { return }
        if token == breakPolicy.promptID {
            switch action {
            case "take": chooseBreak(); openMainWindow?()
            case "skip": deferBreak(snooze: false)
            case "snooze": deferBreak(snooze: true)
            case UNNotificationDefaultActionIdentifier: openMainWindow?()
            default: break // Dismissing a banner isn't a skip or a new prompt.
            }
        } else if token == breakPolicy.activeBreak?.id {
            if action == "back" { returnFromBreak(); openMainWindow?() }
            else if action == UNNotificationDefaultActionIdentifier { openMainWindow?() }
        }
    }
    func refreshSessions() {
        do {
            sessions = try SessionFiles.list(in: SessionFiles.root())
            libraryError = nil
        } catch { libraryError = error.localizedDescription }
    }
    func isActive(_ session: SavedSession) -> Bool {
        isRecording && session.folder == sessionFolder
    }
    func deleteSession(_ session: SavedSession) throws {
        try SessionFiles.validate(session.folder, in: SessionFiles.root(),
            active: isRecording ? sessionFolder : nil)
        try FileManager.default.trashItem(at: session.folder, resultingItemURL: nil)
        if sessionFolder == session.folder { sessionFolder = nil }
        refreshSessions()
    }
    func exportSavedSession(_ session: SavedSession) throws -> URL? {
        try SessionFiles.validate(session.folder, in: SessionFiles.root(),
            active: isRecording ? sessionFolder : nil)
        let panel = NSOpenPanel()
        panel.title = "Export session CSV files"
        panel.prompt = "Export here"
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.canCreateDirectories = true
        panel.allowsMultipleSelection = false
        guard panel.runModal() == .OK, let destination = panel.url else { return nil }
        return try SessionFiles.export(session, to: destination, root: SessionFiles.root(),
            active: isRecording ? sessionFolder : nil)
    }
}
