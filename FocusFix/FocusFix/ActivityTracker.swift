// MARK: - FF: TRACKING
// Coordinates recording, breaks, check-ins and the session library. Nothing starts recording until the user chooses Start.

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
    @Published var recordingNoticePresented = false
    @Published private(set) var sessionSurveyOptions = SurveyOptions()
    @Published var timedCheckInPresented = false
    @Published private(set) var timedCheckInPending = false
    private var sessionCheckIn: CheckInPrompt?
    private var breakCheckIn: CheckInPrompt?
    private var timedCheckInSheet: CheckInPrompt?
    private var timedCheckInPolicy = TimedCheckInPolicy()
    // Whether a survey sheet is currently taking attention away from work.
    private var checkInOpen: Bool { breakCheckIn != nil || timedCheckInSheet != nil }
    // Keep survey interactions distinct from work and post-timer return waiting.
    private var activityPhase: String { checkInOpen ? "check_in" : breakPolicy.activityPhase }
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

    // Format the session's elapsed time for the main timer.
    var formattedTime: String {
        let s = Int(elapsed)
        return String(format: "%02d:%02d:%02d", s / 3600, s / 60 % 60, s % 60)
    }
    // Use a monotonic clock for elapsed time, so wall-clock edits do not change durations.
    private var now: Double {
        let duration = startInstant.duration(to: clock.now).components
        return max(0, Double(duration.seconds) + Double(duration.attoseconds) / 1e18)
    }
    // Load the saved-session list and arrange to finish a recording when the app quits.
    private init() {
        refreshSessions()
        quitObserver = NotificationCenter.default.addObserver(
            forName: NSApplication.willTerminateNotification, object: nil, queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated { self?.stop(reason: "app_quit") }
        }
    }
    // Connect macOS notification actions to the same controls used by the app.
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
    // Check the current notification setting without asking for permission again.
    func refreshNotificationPermission() {
        Task { await notificationAccess.refresh() }
    }
    // Ask macOS for notification permission after the user chooses to enable it.
    func enableNotifications() {
        Task { await notificationAccess.enable() }
    }
    // Open the system notification settings so the user can change banner permissions.
    func openNotificationSettings() {
        // Opens settings only; FocusFix never changes system permissions itself.
        guard let url = URL(string: "x-apple.systempreferences:com.apple.preference.notifications") else { return }
        if !NSWorkspace.shared.open(url) {
            notificationNotice = "Open System Settings → Notifications → FocusFix and turn on Allow Notifications and Banners."
        }
    }
    // Ask for Accessibility access, which is needed to observe activity outside FocusFix.
    func requestPermission() {
        guard !RecordingNotice().needsAcknowledgement else {
            recordingNoticePresented = true
            return
        }
        let key = kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String
        _ = AXIsProcessTrustedWithOptions([key: true] as CFDictionary)
        needsPermission = !AXIsProcessTrusted()
        message = "Enable FocusFix in System Settings → Privacy & Security → Accessibility, then press Start."
    }
    // Check permission and open the fatigue check-in before starting a new session.
    func requestStart() {
        guard !isRecording, !sessionCheckInPresented, !recordingNoticePresented else { return }
        guard !RecordingNotice().needsAcknowledgement else {
            recordingNoticePresented = true
            return
        }
        guard AXIsProcessTrusted() else {
            needsPermission = true
            message = "Keyboard recording needs Accessibility access. Allow access, then start again."
            return
        }
        needsPermission = false
        // Freeze the choices before any survey opens; changes during a session wait until the next one.
        sessionSurveyOptions = SurveyPreferences.shared.snapshot
        guard sessionSurveyOptions.beforeSession else {
            start(fatigue: nil, prompt: nil)
            return
        }
        sessionCheckIn = CheckInPrompt(elapsed: 0)
        sessionCheckInPresented = true
    }
    // Close the starting check-in without recording a session or an answer.
    func cancelSessionCheckIn() { sessionCheckIn = nil }
    // Acknowledge local collection, then let the user press Start again after the notice closes.
    // Avoid stacking two SwiftUI sheets during the same dismissal animation.
    func acceptRecordingNotice() {
        RecordingNotice().acknowledge()
        recordingNoticePresented = false
    }
    // Accept a selected fatigue score, or an explicit skip, then start the session.
    func completeSessionCheckIn(fatigue: Int?) {
        guard let prompt = sessionCheckIn, fatigue.map({ (0...10).contains($0) }) ?? true else { return }
        sessionCheckIn = nil
        sessionCheckInPresented = false
        start(fatigue: fatigue, prompt: prompt)
    }
    // Create the local session files, snapshot the sharing choice, and start activity monitors and timers.
    private func start(fatigue: Int?, prompt: CheckInPrompt?) {
        guard !isRecording, !RecordingNotice().needsAcknowledgement else { return }
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
            let sharing = SharingController.shared
            let newWriter = try RecordingWriter(root: root, id: UUID().uuidString, startedAt: startedAt,
                participantID: sharing.participantID.isEmpty ? nil : sharing.participantID,
                sharingConsentID: sharing.consentID, surveyOptions: sessionSurveyOptions)
            writer = newWriter
            sessionFolder = newWriter.folder
            startInstant = clock.now
            if let prompt, sessionSurveyOptions.beforeSession {
                let beforeStart = prompt.instant.duration(to: startInstant).components
                let checkInDuration = Double(beforeStart.seconds) + Double(beforeStart.attoseconds) / 1e18
                try newWriter.logSurvey(SurveyEntry(id: prompt.id, context: .sessionStart,
                    status: fatigue == nil ? .skipped : .answered, breakID: "", shownAt: prompt.shownAt,
                    answeredAt: startedAt, shownElapsed: -checkInDuration, answeredElapsed: 0,
                    fatigue: fatigue, productivity: nil))
            }
            suspendedBy = []
            elapsed = 0
            eventsRecorded = 0
            rowsRecorded = 0
            eventCount = 0
            movementRows = 0
            keys = KeyTiming()
            breakPolicy = BreakPolicy()
            timedCheckInPolicy = TimedCheckInPolicy()
            timedCheckInSheet = nil
            timedCheckInPending = false
            timedCheckInPresented = false
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
            try scheduleTimedCheckIn(at: 0)
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
    // Finish local files and any open break/check-in, remove monitors, then offer eligible data to the upload queue.
    func stop(reason: String = "user_stop") {
        guard isRecording else { return }
        let end = now
        // Close an abandoned break setup before finishing the recording.
        var checkInSaveError: Error?
        do { try finishBreakCheckIn(status: .cancelled, at: end) }
        catch { checkInSaveError = error }
        do { try finishTimedCheckIn(action: "session_stopped", at: end) }
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
        SharingController.shared.retryPending()
    }
    // Update the clock, mouse summaries and reminder rules once per timer tick.
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
                if !checkInOpen { try advanceBreakClock(at: elapsed) }
                if let item = timedCheckInPolicy.tick(at: elapsed,
                    canPrompt: breakPolicy.phase == .work && !checkInOpen) {
                    try writer?.logSurveyPrompt(SurveyPromptEntry(item: item, action: "requested", time: elapsed))
                    timedCheckInPending = true
                    breakNotifications.sendCheckIn(session: sessionFolder?.lastPathComponent ?? "", token: item.id)
                }
                if breakPolicy.phase != .resting { append(mouse.advance(to: elapsed)) }
            }
            try writer?.flush()
            eventCount = eventsRecorded
            movementRows = rowsRecorded
            updateBreakUI(at: elapsed)
        } catch { fail(error) }
    }
    // Listen for local/global input, app switches and sleep/login changes while recording.
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
    // Turn an input event into a generic activity record; never store typed text or a cursor path.
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
    // Recognize backspace and forward-delete keys without saving other key identities.
    private func isDelete(_ event: NSEvent) -> Bool { event.keyCode == 51 || event.keyCode == 117 }
    // Add one activity event with its elapsed time and work/check-in/break-return phase.
    private func record(type: String, at time: Double, repeated: Bool? = nil, hold: Double? = nil) throws {
        try writer?.event(time: time, type: type, repeated: repeated, hold: hold,
            activityPhase: activityPhase,
            secondsSinceLastBreak: breakPolicy.phase == .work ? breakPolicy.sinceLastBreak(at: time) : nil)
        eventsRecorded += 1
    }
    // Pass completed mouse summaries to the file writer and update the test counter.
    private func append(_ rows: [MouseSummary]) {
        writer?.append(rows)
        rowsRecorded += rows.count
    }
    // Show a recording error and stop safely instead of pretending data is still being saved.
    private func fail(_ error: Error) {
        stop(reason: "recording_error")
        writer = nil
        hasError = true
        message = "Recording stopped: \(error.localizedDescription). Existing files have been kept."
    }
    // Remove input observers and timers, and release the app's recording activity assertion.
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

    // Copy the current break state and times into values the screen can display.
    private func updateBreakUI(at time: Double) {
        breakPhase = breakPolicy.phase
        breakPromptPending = isRecording && breakPolicy.promptID != nil
        currentBreak = breakPolicy.activeBreak
        latestBreak = breakPolicy.lastBreak
        secondsSinceBreak = breakPolicy.sinceLastBreak(at: time)
    }
    // Start a fresh mouse summary when the activity phase changes so phases are not mixed.
    private func resetMouse(at time: Double, phase: String) {
        let point = CGEvent(source: nil)?.location ?? .zero
        mouse = MouseAccumulator(initialPosition: point, start: time, activityPhase: phase,
            workReference: phase == "work" ? breakPolicy.lastBreakEnd : nil)
        returnPoint = point
        returnDistance = 0
        returnWindowStart = time
        keys = KeyTiming() // Never match a key press across a paused interval.
    }
    // Advance the break rules, record transitions and send a reminder when needed.
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
    // Open the pre-break ratings and setup; opening this sheet is not yet taking a break.
    func chooseBreak() {
        guard isRecording, breakPolicy.phase == .work, !checkInOpen else { return }
        let time = now
        do {
            // Don't stack a due work check-in on top of the pre-break ratings.
            if timedCheckInPolicy.hasPending { try finishTimedCheckIn(action: "break_setup", at: time) }
            append(mouse.stop(at: time))
            breakCheckIn = CheckInPrompt(elapsed: time)
            resetMouse(at: time, phase: "check_in")
            try record(type: "check_in_start", at: time)
            breakSetupPresented = true
        } catch { fail(error) }
    }
    // Record that the break setup was cancelled and return to normal tracking.
    func cancelBreakCheckIn() {
        guard isRecording else { breakCheckIn = nil; return }
        do { try finishBreakCheckIn(status: .cancelled, at: now) }
        catch { fail(error) }
    }
    // Save or skip the pre-break ratings and end the check-in activity phase.
    private func finishBreakCheckIn(status: CheckInStatus, at time: Double,
                                    breakID: String = "", fatigue: Int? = nil, productivity: Int? = nil) throws {
        guard let prompt = breakCheckIn else { return }
        append(mouse.stop(at: time))
        // Clear before writing so an I/O failure cannot recursively try the same check-in.
        breakCheckIn = nil
        if sessionSurveyOptions.beforeBreak {
            try writer?.logSurvey(SurveyEntry(id: prompt.id, context: .beforeBreak, status: status,
                breakID: breakID, shownAt: prompt.shownAt, answeredAt: Date(),
                shownElapsed: prompt.elapsed, answeredElapsed: time, fatigue: fatigue, productivity: productivity))
        }
        try record(type: "check_in_end", at: time)
        if breakPolicy.phase == .work {
            resetMouse(at: time, phase: "work")
            breakPolicy.input(at: time)
        }
    }
    // Validate the chosen duration/activity, save ratings and pause detailed tracking for the break.
    func beginBreak(minutes: Double, activity: String, fatigue: Int?, productivity: Int?) {
        // Break duration/activity still work when the pre-break survey is disabled.
        let fatigue = sessionSurveyOptions.beforeBreak ? fatigue : nil
        let productivity = sessionSurveyOptions.beforeBreak ? productivity : nil
        guard isRecording, breakCheckIn != nil,
              (fatigue == nil && productivity == nil) ||
                (fatigue.map({ (0...10).contains($0) }) == true && productivity.map({ (0...10).contains($0) }) == true)
        else { return }
        let label = String(activity.trimmingCharacters(in: .whitespacesAndNewlines).prefix(120))
        let time = now
        guard let entry = breakPolicy.begin(at: time, seconds: minutes * 60, activity: label) else { return }
        do {
            try finishBreakCheckIn(status: fatigue == nil ? .skipped : .answered, at: time,
                breakID: entry.record?.id ?? "", fatigue: fatigue, productivity: productivity)
            try writer?.logBreak(entry)
            try finishTimedCheckIn(action: "break_started", at: time)
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
    // Delay the next reminder by 10 or 25 minutes without changing the last actual break time.
    func deferBreak(snooze: Bool) {
        guard isRecording, let entry = breakPolicy.deferPrompt(at: now, snooze: snooze) else { return }
        do {
            try finishBreakCheckIn(status: .cancelled, at: now)
            try writer?.logBreak(entry)
            breakNotifications.clearBreaks()
            breakSetupPresented = false
            updateBreakUI(at: now)
        } catch { fail(error) }
    }
    // End the break immediately when the user presses I'm back.
    func returnFromBreak() {
        guard isRecording, breakPolicy.activeBreak != nil else { return }
        do {
            try advanceBreakClock(at: now)
            try finishBreak(at: now, reason: "explicit_return")
        } catch { fail(error) }
    }
    // Save the actual break end, resume work and schedule the next during-work check-in.
    private func finishBreak(at time: Double, reason: String) throws {
        if breakPolicy.phase == .awaitingReturn && suspendedBy.isEmpty { append(mouse.stop(at: time)) }
        guard let entry = breakPolicy.finish(at: time, reason: reason) else { return }
        try writer?.logBreak(entry)
        resetMouse(at: time, phase: "work")
        breakNotifications.clear()
        try scheduleTimedCheckIn(at: time, afterBreak: entry.record?.id ?? "")
        elapsed = time
        updateBreakUI(at: time)
    }
    // Handle sleep or an inactive login without inventing activity during the missing time.
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
    // Resume the break clock and sampling after wake/login, without assuming the user has returned to work.
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
    // Save a correction to what the user actually did during their most recent break.
    func confirmBreakActivity(_ activity: String) {
        guard isRecording else { return }
        let label = String(activity.trimmingCharacters(in: .whitespacesAndNewlines).prefix(120))
        guard let entry = breakPolicy.updateActivity(label, at: now) else { return }
        do { try writer?.logBreak(entry); updateBreakUI(at: now) }
        catch { fail(error) }
    }
    // Require meaningful input to end a break automatically; ignore tiny drift and key repeats.
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
    // Route a notification button to its action only if its session and prompt are still current.
    private func notificationAction(session: String, token: String, action: String) {
        guard isRecording, sessionFolder?.lastPathComponent == session else { return }
        if timedCheckInPolicy.hasPending, token == timedCheckInPolicy.current?.id {
            if action == "answer_check_in" || action == UNNotificationDefaultActionIdentifier {
                openTimedCheckIn()
            } else if action == "skip_check_in" { skipTimedCheckIn() }
        } else if token == breakPolicy.promptID {
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
    // Schedule one ratings opportunity 10 minutes after session start or an actual break return.
    private func scheduleTimedCheckIn(at time: Double, afterBreak: String = "") throws {
        guard let item = timedCheckInPolicy.scheduleIfEnabled(from: time, afterBreak: afterBreak,
            options: sessionSurveyOptions) else { return }
        try writer?.logSurveyPrompt(SurveyPromptEntry(item: item, action: "scheduled", time: time))
    }
    // Open the requested survey and mark its interaction time separately from work.
    func openTimedCheckIn() {
        guard isRecording, breakPolicy.phase == .work, !checkInOpen,
              let token = timedCheckInPolicy.current?.id,
              let item = timedCheckInPolicy.open(token: token, at: now) else { return }
        let time = item.openedAt!
        do {
            append(mouse.stop(at: time))
            timedCheckInSheet = CheckInPrompt(elapsed: time)
            resetMouse(at: time, phase: "check_in")
            try record(type: "check_in_start", at: time)
            try writer?.logSurveyPrompt(SurveyPromptEntry(item: item, action: "opened", time: time))
            breakNotifications.clearCheckIn()
            timedCheckInPresented = true
            openMainWindow?()
        } catch { fail(error) }
    }
    // Validate both selected ratings and save the during-work answer.
    func completeTimedCheckIn(fatigue: Int, productivity: Int) {
        guard isRecording, timedCheckInSheet != nil,
              (0...10).contains(fatigue), (0...10).contains(productivity) else { return }
        do { try finishTimedCheckIn(action: "answered", at: now, fatigue: fatigue, productivity: productivity) }
        catch { fail(error) }
    }
    // Record a deliberate skip without inventing fatigue or productivity scores.
    func skipTimedCheckIn() {
        guard isRecording, timedCheckInPolicy.hasPending else { return }
        do { try finishTimedCheckIn(action: "skipped", at: now) }
        catch { fail(error) }
    }
    // Record dismissal of an open survey without counting it as an answer.
    func cancelTimedCheckIn() {
        guard isRecording, timedCheckInSheet != nil else { return }
        do { try finishTimedCheckIn(action: "cancelled", at: now) }
        catch { fail(error) }
    }
    // Close the opportunity, log its outcome and restore the work activity phase.
    private func finishTimedCheckIn(action: String, at time: Double, fatigue: Int? = nil, productivity: Int? = nil) throws {
        guard let item = timedCheckInPolicy.finish() else { return }
        let sheet = timedCheckInSheet
        // Clear the state first so I/O errors and late notification clicks cannot resubmit it.
        timedCheckInSheet = nil
        timedCheckInPending = false
        timedCheckInPresented = false
        breakNotifications.clearCheckIn()
        if let sheet {
            append(mouse.stop(at: time))
            let status: CheckInStatus = action == "answered" ? .answered : action == "skipped" ? .skipped : .cancelled
            try writer?.logSurvey(SurveyEntry(id: item.id, context: .duringWork, status: status,
                breakID: "", shownAt: sheet.shownAt, answeredAt: Date(), shownElapsed: sheet.elapsed,
                answeredElapsed: time, fatigue: fatigue, productivity: productivity))
            try record(type: "check_in_end", at: time)
            if breakPolicy.phase == .work {
                resetMouse(at: time, phase: "work")
                breakPolicy.input(at: time)
            }
        }
        try writer?.logSurveyPrompt(SurveyPromptEntry(item: item, action: action, time: time))
    }
    // Reload saved session metadata so the library matches the local files.
    func refreshSessions() {
        do {
            sessions = try SessionFiles.list(in: SessionFiles.root())
            libraryError = nil
        } catch { libraryError = error.localizedDescription }
    }
    // Check whether a library entry is the session currently being recorded.
    func isActive(_ session: SavedSession) -> Bool {
        isRecording && session.folder == sessionFolder
    }
    // Move an inactive local session to Trash and cancel any pending upload for it.
    func deleteSession(_ session: SavedSession) throws {
        try SessionFiles.validate(session.folder, in: SessionFiles.root(),
            active: isRecording ? sessionFolder : nil)
        try FileManager.default.trashItem(at: session.folder, resultingItemURL: nil)
        SharingController.shared.cancelSession(session.id)
        if sessionFolder == session.folder { sessionFolder = nil }
        refreshSessions()
    }
    // Ask for an export destination and copy an inactive session without moving its originals.
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
