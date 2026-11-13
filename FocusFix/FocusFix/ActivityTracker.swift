// MARK: - FF: TRACKING
// Coordinates consent-gated manual/automatic recording, work labels, breaks, check-ins and history.

import AppKit
import CoreGraphics
import Combine
import UserNotifications

@MainActor
final class ActivityTracker: ObservableObject {
    static let shared = ActivityTracker()
    @Published private(set) var recordingMode: RecordingMode = .manual
    @Published private(set) var captureState: CaptureState = .disabled
    @Published private(set) var captureReason: String?
    @Published private(set) var userContext: ActivityContext = .unknown
    var interventionPhase: InterventionPhase { breakPolicy.phase == .resting ? .explicitBreak : InterventionPhase(legacyPhase: activityPhase) }
    @Published private(set) var isRecording = false
    var recordingStatus: String { RecordingPresentation.status(state: captureState, mode: recordingMode, context: userContext, phase: interventionPhase) }
    @Published private(set) var declaredWorkSeconds: Double = 0
    @Published private(set) var elapsed: Double = 0
    @Published private(set) var eventCount = 0
    @Published private(set) var movementRows = 0
    @Published private(set) var sessionFolder: URL?
    @Published private(set) var sessionTags: [String] = []
    @Published private(set) var sessionTagColors: [String: String] = [:]
    @Published private(set) var message = "Ready when you are."
    @Published private(set) var needsPermission = false
    @Published private(set) var hasError = false
    @Published private(set) var sessions: [SavedSession] = []
    @Published private(set) var libraryError: String?
    @Published private(set) var libraryNotice: String?
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
    @Published private(set) var dailyProgress = DailyProgress()
    @Published private(set) var progressNotice: String?
    @Published private(set) var rechargeDate: Date?
    private var progressStore: ProgressStore?
    @Published private(set) var sessionWorkPlan = SessionWorkPlan()
    private var progressClock = ProgressClock()
    private var pendingWorkSlices: [CoverageSlice] = []
    private var segmentWorkDays: [String: Double] = [:]
    private var segmentWorkIntervals: [DeclaredWorkInterval] = []
    private var segmentWorkOwner: DeclaredWorkOwner?
    private var captureAccountKey: String?
    private var activeAccountKey: String? {
        guard let session = AccountController.shared.session else { return nil }
        return "\(AccountController.shared.api?.configuration.origin.absoluteString ?? "")|\(session.user.id)"
    }
    private var progressReconciliation: Task<Void, Never>?
    private var sessionRefresh: Task<Void, Never>?
    private var lastProgressSave: Double = 0
    private var progressDirty = false
    private var sessionCheckIn: CheckInPrompt?
    private var breakCheckIn: CheckInPrompt?
    private var timedCheckInSheet: CheckInPrompt?
    private var timedCheckInPolicy = TimedCheckInPolicy()
    private var sessionStudyConfiguration: StudyCheckInConfiguration?
    private var studyPrompt: StudyPromptSnapshot?
    private var studyBudget = StudyPromptBudget()
    var studyRecallDescription: String? {
        studyPrompt.map { "Think about the \(Int($0.recallEnd - $0.recallStart)) seconds before this prompt was requested. Context then: \($0.contextAtPrompt.rawValue)." }
    }
    // Whether a survey sheet is currently taking attention away from work.
    private var checkInOpen: Bool { breakCheckIn != nil || timedCheckInSheet != nil }
    // Keep survey interactions distinct from work and post-timer return waiting.
    private var activityPhase: String { checkInOpen ? "check_in" : breakPolicy.activityPhase }
    var openMainWindow: (() -> Void)?
    private var breakPolicy = BreakPolicy()
    let breakPolicyProvider: any BreakPolicyProvider = FixedTimerPolicyProvider()
    private let breakNotifications = BreakNotifications()
    private let notificationAccess = NotificationAccess(client: SystemNotificationPermissionClient())
    private var returnPoint: CGPoint = .zero
    private var returnDistance: Double = 0
    private var returnWindowStart: Double = 0
    private var suspendedBy: Set<String> = []
    private var researchConsent: ResearchConsent?
    private var developmentConsent: DevelopmentConsent?
    private var researchCaptureIdentity: ResearchCaptureIdentity? {
        ResearchSharingController.shared.capturedConsent.map { consent in
            ResearchCaptureIdentity(owner: consent.owner, origin: consent.origin, consentID: consent.id,
                studyVersion: consent.studyVersion, consentStartedAtUTC: consent.startedAt, scope: consent.archiveScope)
        }
    }
    private var capturedResearchIdentity: ResearchCaptureIdentity?
    private var writer: RecordingWriter?
    private var mouse = MouseAccumulator(initialPosition: .zero)
    private var keys = KeyTiming()
    private var startedAt = Date()
    private let clock = ContinuousClock()
    private var startInstant = ContinuousClock.now
    private var eventsRecorded = 0
    private var rowsRecorded = 0
    private var lastApplication: pid_t?
    private let inputMonitor = InputMonitor()
    private var timer: Timer?
    private var backgroundActivity: NSObjectProtocol?
    private var workspaceObservers: [NSObjectProtocol] = []
    private var quitObserver: NSObjectProtocol?
    private var lifecycle = RecordingLifecycle()
    private var lifecycleTimer: Timer?
    private var lifecycleObservers: [NSObjectProtocol] = []
    private var activationObserver: NSObjectProtocol?
    private var lastSamplingTick: Double = 0
    private var lastObservedTime: Double = 0
    private var recordingDay = ""
    private var quitting = false
    private var reminderEligibility = ReminderEligibility()
    private let reminderClockOrigin = ContinuousClock.now
    private var reminderMonotonic: Double {
        let value = reminderClockOrigin.duration(to: clock.now).components
        return Double(value.seconds) + Double(value.attoseconds) / 1e18
    }
    var screenUseReminders: Bool { UserDefaults.standard.bool(forKey: "focusfix.screenUseReminders") }

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
        loadProgress()
        do { _ = try SessionFiles.recoverPending(in: SessionFiles.root()) }
        catch { libraryError = "An interrupted recording could not be finalized; original files were kept." }
        refreshSessions()
        AutomaticRecordingPreferences.shared.onChange = { [weak self] in self?.automaticPreferencesChanged() }
        captureState = RecordingNotice().enabled ? .ready : .disabled
        quitObserver = NotificationCenter.default.addObserver(
            forName: NSApplication.willTerminateNotification, object: nil, queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated {
                guard let self else { return }
                self.quitting = true
                self.reconcileLifecycle()
                self.updateProgress(at: self.now, persist: true)
            }
        }
        studyBudget = SurveyPreferences.shared.loadBudget()
        SurveyPreferences.shared.onRevoke = { [weak self] in self?.revokeStudyCheckIns() }
        installLifecycleObservers()
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
    // Ask for Input Monitoring only after the user acknowledges local recording.
    func requestPermission() {
        guard RecordingNotice().enabled else {
            recordingNoticePresented = true
            return
        }
        hasError = false
        needsPermission = !InputMonitor.requestPermission()
        message = needsPermission
            ? "Turn on FocusFix in Input Monitoring to record activity across apps. If macOS asks, quit and reopen FocusFix."
            : "Input Monitoring is enabled. Press Start work when you are ready."
        if needsPermission { openInputSettings() }
    }
    private func openInputSettings() {
        guard let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_ListenEvent") else { return }
        if !NSWorkspace.shared.open(url) {
            message = "Open System Settings → Privacy & Security → Input Monitoring and turn on FocusFix."
        }
    }
    func refreshInputPermission() {
        guard needsPermission, InputMonitor.hasPermission else { return }
        needsPermission = false
        message = "Input Monitoring is enabled. Press Start work when you are ready."
    }
    // Start immediately; planning and its optional check-in are a separate action.
    func requestStart() {
        guard !sessionCheckInPresented, !recordingNoticePresented else { return }
        if isRecording {
            let beginsWork = userContext != .work
            setContext(.work)
            if isRecording, beginsWork { sessionWorkPlan = SessionWorkPlan() }
            return
        }
        guard !RecordingNotice().needsAcknowledgement else {
            recordingNoticePresented = true
            return
        }
        sessionSurveyOptions = SurveyPreferences.shared.snapshot
        let automatic = AutomaticRecordingPreferences.shared.enabled
        AutomaticRecordingPreferences.shared.setUserPaused(false, notify: false)
        lifecycle.failed = false
        start(fatigue: nil, prompt: nil, plan: SessionWorkPlan(),
              tags: sessionFolder == nil ? sessionTags : [],
              tagColors: sessionFolder == nil ? sessionTagColors : [:],
              mode: automatic ? .automatic : .manual)
        if automatic, isRecording { setContext(.work) }
    }
    func requestPlannedStart() {
        guard !(isRecording && userContext == .work), !sessionCheckInPresented,
              !recordingNoticePresented else { return }
        guard !RecordingNotice().needsAcknowledgement else {
            recordingNoticePresented = true
            return
        }
        // Use the recording's frozen survey choices when automatic capture is already running.
        if !isRecording { sessionSurveyOptions = SurveyPreferences.shared.snapshot }
        sessionCheckIn = sessionSurveyOptions.beforeSession ? CheckInPrompt(elapsed: elapsed) : nil
        sessionCheckInPresented = true
    }
    func endWork() {
        guard isRecording, userContext == .work else { return }
        if recordingMode == .automatic { setContext(.unknown) }
        else { stop(reason: "end_work") }
    }
    func setContext(_ context: ActivityContext, source: ContextSource = .userAction) {
        guard isRecording, let writer else { return }
        let time = now
        guard time - lastSamplingTick <= 5 else { stop(reason: "capture_gap", observedEnd: lastObservedTime); return }
        do {
            updateProgress(at: time)
            if breakPolicy.phase != .resting { append(mouse.stop(at: time)) }
            try writer.changeContext(context, at: time, effectiveAt: Date(), source: source)
            if userContext != writer.contract.currentContext {
                reminderEligibility.invalidate()
                breakNotifications.clearBreaks()
                breakPolicy.contextChanged(at: time, beginsWork: context == .work)
            }
            userContext = writer.contract.currentContext
            lastObservedTime = max(lastObservedTime, time)
            resetMouse(at: time, phase: activityPhase)
            updateProgress(at: time, persist: true)
        } catch { fail(error) }
    }
    func correctContext(_ context: ActivityContext, start: Double, end: Double, session: SavedSession) throws {
        try SessionFiles.correctContext(context, start: start, end: end, for: session,
            root: SessionFiles.root(), active: isRecording ? sessionFolder : nil,
            expectedRevision: session.recordingContract?.revisions.count ?? 0)
        refreshSessions()
    }
    // Close the starting check-in without recording a session or an answer.
    func cancelSessionCheckIn() { sessionCheckIn = nil }
    // Acknowledge local collection, then let the user press Start again after the notice closes.
    // Avoid stacking two SwiftUI sheets during the same dismissal animation.
    func acceptRecordingNotice() {
        RecordingNotice().acknowledge()
        captureState = .ready
        captureReason = nil
        recordingNoticePresented = false
    }
    func automaticPreferencesChanged() { reconcileLifecycle() }
    func prepareToQuit() { quitting = true; reconcileLifecycle() }
    private func installLifecycleObservers() {
        let center = NSWorkspace.shared.notificationCenter
        let pairs: [(Notification.Name, Notification.Name, String)] = [
            (NSWorkspace.willSleepNotification, NSWorkspace.didWakeNotification, "sleep"),
            (NSWorkspace.screensDidSleepNotification, NSWorkspace.screensDidWakeNotification, "display"),
            (NSWorkspace.sessionDidResignActiveNotification, NSWorkspace.sessionDidBecomeActiveNotification, "lock")
        ]
        for (pause, resume, reason) in pairs {
            lifecycleObservers.append(center.addObserver(forName: pause, object: nil, queue: .main) { [weak self] _ in
                MainActor.assumeIsolated { self?.lifecycle.blockers.insert(reason); self?.reconcileLifecycle() }
            })
            lifecycleObservers.append(center.addObserver(forName: resume, object: nil, queue: .main) { [weak self] _ in
                MainActor.assumeIsolated { self?.lifecycle.blockers.remove(reason); self?.reconcileLifecycle() }
            })
        }
        activationObserver = NotificationCenter.default.addObserver(forName: NSApplication.didBecomeActiveNotification, object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.reconcileLifecycle() }
        }
        lifecycleTimer = Timer(timeInterval: 1, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated {
                guard let self else { return }
                self.reconcileLifecycle()
                if self.isRecording { self.tick() }
            }
        }
        if let lifecycleTimer { RunLoop.main.add(lifecycleTimer, forMode: .common) }
        // Evaluates saved opt-in silently; never asks macOS for permission on launch.
        reconcileLifecycle()
    }
    private func reconcileLifecycle() {
        let preferences = AutomaticRecordingPreferences.shared
        lifecycle.recordingAllowed = RecordingNotice().enabled
        lifecycle.automaticEnabled = preferences.enabled
        lifecycle.userPaused = preferences.userPaused
        lifecycle.permissionAvailable = InputMonitor.hasPermission
        lifecycle.quitting = quitting
        let idle = SystemIdleTime.seconds()
        let effect = lifecycle.reconcile(recording: isRecording, mode: isRecording ? recordingMode : .automatic, idle: idle)
        switch effect {
        case .none: break
        case .stop(let reason): stop(reason: reason)
        case .start:
            sessionSurveyOptions = SurveyPreferences.shared.snapshot
            start(fatigue: nil, prompt: nil, plan: SessionWorkPlan(), tags: [], tagColors: [:], mode: .automatic)
        }
        captureState = isRecording ? .recording : lifecycle.state
        needsPermission = captureState == .permissionUnavailable
        if needsPermission { message = "Input Monitoring is needed. Enable it explicitly to set up capture; saved automatic consent never grants OS access." }
        captureReason = lifecycle.reason
    }
    func disableRecording() {
        AutomaticRecordingPreferences.shared.disable()
        if isRecording { stop() }
        sessionCheckInPresented = false
        sessionCheckIn = nil
        RecordingNotice().decline()
        captureState = .disabled
        captureReason = "recording_disabled"
        message = "Recording is off. Enable it in Settings → Privacy & Data Sharing when you are ready."
    }
    func declineRecordingNotice() {
        disableRecording()
        recordingNoticePresented = false
    }
    // Accept a selected fatigue score, or an explicit skip, then start the session.
    func completeSessionCheckIn(_ selection: SessionStartSelection) {
        guard sessionCheckInPresented,
              selection.fatigue.map({ (0...10).contains($0) }) ?? true else { return }
        let prompt = sessionCheckIn
        guard !sessionSurveyOptions.beforeSession || prompt != nil else { return }
        if isRecording {
            // Automatic capture continues while the user plans; label work only on confirmation.
            do {
                try updateCurrentTags(selection.tags, colors: selection.tagColors)
                if let prompt {
                    try writer?.logSurvey(SurveyEntry(id: prompt.id, context: .sessionStart,
                        status: selection.fatigue == nil ? .skipped : .answered, breakID: "",
                        shownAt: prompt.shownAt, answeredAt: Date(), shownElapsed: prompt.elapsed,
                        answeredElapsed: now, fatigue: selection.fatigue, productivity: nil))
                }
            } catch { fail(error); return }
            setContext(.work)
            if isRecording { sessionWorkPlan = selection.plan }
        } else {
            let automatic = AutomaticRecordingPreferences.shared.enabled
            AutomaticRecordingPreferences.shared.setUserPaused(false, notify: false)
            lifecycle.failed = false
            start(fatigue: sessionSurveyOptions.beforeSession ? selection.fatigue : nil,
                  prompt: prompt, plan: selection.plan, tags: selection.tags, tagColors: selection.tagColors,
                  mode: automatic ? .automatic : .manual)
            if automatic, isRecording { setContext(.work) }
        }
        sessionCheckIn = nil
        sessionCheckInPresented = false
    }
    // Create the local session files, snapshot the sharing choice, and start activity monitors and timers.
    private func start(fatigue: Int?, prompt: CheckInPrompt?, plan: SessionWorkPlan, tags: [String], tagColors: [String: String], mode: RecordingMode = .manual) {
        guard !isRecording, RecordingNotice().enabled else { return }
        guard InputMonitor.hasPermission else {
            needsPermission = true
            captureState = .permissionUnavailable
            captureReason = "input_monitoring_required"
            message = "Activity recording needs Input Monitoring access. Allow access, then start again."
            return
        }
        if mode == .automatic {
            guard AutomaticRecordingPreferences.shared.enabled,
                  !AutomaticRecordingPreferences.shared.userPaused, !quitting, lifecycle.blockers.isEmpty else { return }
        } else {
            lifecycle.failed = false
            // Deliberate manual Start may proceed after an earlier user pause.
            if AutomaticRecordingPreferences.shared.userPaused {
                AutomaticRecordingPreferences.shared.setUserPaused(false, notify: false)
            }
        }
        needsPermission = false
        hasError = false
        do {
            let root = try SessionFiles.root()
            startedAt = Date()
            pendingWorkSlices = []; segmentWorkDays = [:]; segmentWorkIntervals = []
            captureAccountKey = activeAccountKey
            segmentWorkOwner = SocialController.shared.declaredWorkScope.map { DeclaredWorkOwner(ownerID: $0.owner, origin: $0.origin) }
            sessionStudyConfiguration = SurveyPreferences.shared.activeConfiguration
            studyPrompt = nil
            researchConsent = ResearchSharingController.shared.capturedConsent
            developmentConsent = DevelopmentSharingController.shared.capturedConsent
            capturedResearchIdentity = researchCaptureIdentity
            let newWriter = try RecordingWriter(root: SessionFiles.pendingRoot(in: root), id: UUID().uuidString, startedAt: startedAt,
                mode: mode, researchIdentity: capturedResearchIdentity, studyConfiguration: sessionStudyConfiguration, surveyOptions: sessionSurveyOptions, tags: tags, tagColors: tagColors)
            writer = newWriter
            sessionFolder = newWriter.folder
            sessionTags = tags
            sessionTagColors = tagColors
            startInstant = clock.now
            lastSamplingTick = 0
            lastObservedTime = 0
            recordingDay = RecordingDay.key(at: startedAt)
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
            declaredWorkSeconds = 0
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
            sessionWorkPlan = plan
            isRecording = true
            recordingMode = mode
            captureState = .recording
            captureReason = nil
            userContext = mode == .manual ? .work : .unknown
            progressClock = ProgressClock()
            lastProgressSave = 0
            updateProgress(at: 0, persist: true)
            refreshSessions()
            // Avoid App Nap while collecting; do not prevent system sleep.
            backgroundActivity = ProcessInfo.processInfo.beginActivity(
                options: .userInitiatedAllowingIdleSystemSleep, reason: "Recording a FocusFix session")
            try record(type: "session_start", at: 0)
            try scheduleTimedCheckIn(at: 0)
            installMonitors()
            guard inputMonitor.isEnabled else {
                stop(reason: "monitor_unavailable")
                hasError = true
                message = "Could not attach input monitors. Check Input Monitoring access and relaunch FocusFix."
                return
            }
            message = "Recording locally. You can close this window and keep working."
            refreshNotificationPermission()
        } catch { fail(error) }
    }
    // Finish local files and any open break/check-in, remove monitors, then offer eligible data to the upload queue.
    func stop(reason: String = "user_stop", observedEnd: Double? = nil) {
        guard isRecording else { return }
        if reason == "user_stop", recordingMode == .automatic {
            AutomaticRecordingPreferences.shared.setUserPaused(true, notify: false)
        }
        let end = observedEnd ?? RecordingLifecycle.observedEnd(now: now, lastSamplingTick: lastSamplingTick, lastObserved: lastObservedTime)
        updateProgress(at: end)
        defer { updateProgress(at: end, persist: true) }
        // Close an abandoned break setup before finishing the recording.
        var checkInSaveError: Error?
        do { try finishBreakCheckIn(status: .cancelled, at: end) }
        catch { checkInSaveError = error }
        do { try finishTimedCheckIn(action: "session_stopped", at: end) }
        catch { checkInSaveError = error }
        isRecording = false
        if reason == "recording_error" || reason == "monitor_unavailable" || reason == "input_monitor_interrupted" { lifecycle.failed = true }
        captureState = reason == "permission_lost" ? .permissionUnavailable : (RecordingNotice().enabled ? .ready : .disabled)
        captureReason = reason
        userContext = .unknown
        removeMonitors()
        breakNotifications.clear()
        reminderEligibility.invalidate()
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
            try applyObservedWork()
            // Progress was credited independently above; retaining data never adds time again.
            if let folder = sessionFolder {
                writer = nil
                sessionFolder = try SessionFiles.retainRecording(folder, duration: end, root: SessionFiles.root())
            }
            if let sessionFolder, reason != "recording_error", reason != "monitor_unavailable" {
                ResearchSharingController.shared.finished(folder: sessionFolder, startedAt: startedAt, captured: researchConsent)
                DevelopmentSharingController.shared.finished(folder: sessionFolder, startedAt: startedAt, captured: developmentConsent)
            }
            researchConsent = nil
            developmentConsent = nil
            if sessionFolder == nil {
                message = "Recording stopped. Check Sessions for your saved recordings."
            } else {
                message = reason == "user_stop" ? "Session saved. Your CSV files are ready." : "Session saved and stopped (\(reason.replacingOccurrences(of: "_", with: " ")))."
            }
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
    // Update the clock, mouse summaries and reminder rules once per timer tick.
    private func tick() {
        guard isRecording else { return }
        guard InputMonitor.hasPermission else {
            stop(reason: "permission_lost")
            needsPermission = true
            return
        }
        guard inputMonitor.isEnabled else {
            inputInterrupted()
            return
        }
        do {
            elapsed = now
            // A stalled run loop has no continuously observed coverage. Do not backfill bins.
            guard elapsed - lastSamplingTick <= 5 else {
                stop(reason: "capture_gap", observedEnd: lastObservedTime)
                return
            }
            lastSamplingTick = elapsed
            if activeAccountKey != captureAccountKey || researchCaptureIdentity != capturedResearchIdentity {
                try rotateRecording(at: lastObservedTime, reason: "consent_or_account_boundary")
                resetMouse(at: elapsed, phase: activityPhase)
            }
            else if recordingMode == .automatic, RecordingDay.key(at: Date()) != recordingDay { try rotateRecording(at: elapsed) }
            lastObservedTime = max(lastObservedTime, elapsed)
            updateProgress(at: elapsed)
            if suspendedBy.isEmpty {
                if !checkInOpen { try advanceBreakClock(at: elapsed) }
                if let configuration = sessionStudyConfiguration,
                   studyBudget.eligible(at: Date(), configuration: configuration),
                   let item = timedCheckInPolicy.tick(at: elapsed,
                    canPrompt: breakPolicy.phase == .work && !checkInOpen) {
                    let requestDate = Date()
                    guard studyBudget.request(at: requestDate, configuration: configuration) else { return }
                    try SurveyPreferences.shared.saveBudget(studyBudget)
                    if let contract = writer?.contract {
                        studyPrompt = StudyPromptSnapshot(id: item.id, scheduleVersion: configuration.version,
                            configurationScope: configuration.scope, recordingID: contract.recordingID, contextAtPrompt: userContext,
                            requestedElapsed: elapsed, recallStart: max(contract.elapsedOrigin, elapsed - configuration.recallSeconds),
                            recallEnd: elapsed, requestedAtUTC: requestDate)
                        if let studyPrompt { try writer?.logStudyPrompt(StudyPromptLogEntry(prompt: studyPrompt,
                            action: "requested", elapsed: elapsed, recordedAtUTC: requestDate)) }
                    }
                    try writer?.logSurveyPrompt(SurveyPromptEntry(item: item, action: "requested", time: elapsed))
                    timedCheckInPending = true
                    breakNotifications.sendCheckIn(session: sessionFolder?.lastPathComponent ?? "", token: item.id)
                }
                if breakPolicy.phase != .resting { append(mouse.advance(to: elapsed)) }
            }
            try writer?.checkpoint(at: elapsed)
            try applyObservedWork()
            updateProgress(at: elapsed)
            eventCount = eventsRecorded
            movementRows = rowsRecorded
            updateBreakUI(at: elapsed)
        } catch { fail(error) }
    }
    // Listen for local/global input, app switches and sleep/login changes while recording.
    private func installMonitors() {
        let segment = writer?.contract.segmentID
        _ = inputMonitor.start(onInput: { [weak self] event in
            guard let self, self.writer?.contract.segmentID == segment else { return }
            self.receive(event, outsideApp: event.isOutsideApp(processID: ProcessInfo.processInfo.processIdentifier))
        }, onInterruption: { [weak self] in self?.inputInterrupted() })
        let center = NSWorkspace.shared.notificationCenter
        workspaceObservers.append(center.addObserver(forName: NSWorkspace.didActivateApplicationNotification,
            object: nil, queue: .main) { [weak self] notification in
                MainActor.assumeIsolated {
                    guard let self, self.isRecording, self.writer?.contract.segmentID == segment, self.suspendedBy.isEmpty,
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
    }
    private func rotateRecording(at time: Double, reason: String = "local_day_rotation") throws {
        guard let previous = writer, let context = previous.contract.intervals.last else { return }
        if breakPolicy.phase != .resting { append(mouse.stop(at: time)) }
        try previous.finish(startedAt: startedAt, duration: time, reason: reason)
        try applyObservedWork()
        let root = try SessionFiles.root()
        writer = nil
        let retained = try SessionFiles.retainRecording(previous.folder, duration: time - previous.contract.elapsedOrigin, root: root)
        if let retained {
            DevelopmentSharingController.shared.finished(folder: retained, startedAt: startedAt, captured: developmentConsent)
        }
        let nextStart = Date()
        let next = RecordingContract(recordingID: previous.contract.recordingID, mode: recordingMode,
            startedAt: nextStart, elapsedOrigin: time, continuing: context, scoringTimeZone: previous.contract.scoringTimeZone)
        capturedResearchIdentity = researchCaptureIdentity
        researchConsent = ResearchSharingController.shared.capturedConsent
        developmentConsent = DevelopmentSharingController.shared.capturedConsent
        let replacement = try RecordingWriter(root: SessionFiles.pendingRoot(in: root), id: UUID().uuidString,
            startedAt: nextStart, mode: recordingMode, continuingContract: next, researchIdentity: capturedResearchIdentity, studyConfiguration: sessionStudyConfiguration, surveyOptions: sessionSurveyOptions,
            tags: sessionTags, tagColors: sessionTagColors)
        writer = replacement; sessionFolder = replacement.folder
        segmentWorkDays = [:]; pendingWorkSlices = []; segmentWorkIntervals = []
        captureAccountKey = activeAccountKey
        segmentWorkOwner = SocialController.shared.declaredWorkScope.map { DeclaredWorkOwner(ownerID: $0.owner, origin: $0.origin) }
        if let activeBreak = breakPolicy.activeBreak {
            try replacement.logBreak(breakPolicy.entry(at: time, action: "segment_continued", record: activeBreak))
        }
        startedAt = nextStart; recordingDay = RecordingDay.key(at: nextStart)
        removeMonitors(); installMonitors()
        backgroundActivity = ProcessInfo.processInfo.beginActivity(
            options: .userInitiatedAllowingIdleSystemSleep, reason: "Recording a FocusFix session")
        guard inputMonitor.isEnabled else { throw CocoaError(.fileWriteUnknown) }
        resetMouse(at: time, phase: activityPhase)
        refreshSessions()
        // Break policy, work intent, cooldown, progress clock and monotonic origin continue.
    }
    // Turn an input event into a generic activity record; never store typed text or a cursor path.
    private func receive(_ event: ActivityInput, outsideApp: Bool) {
        guard isRecording, suspendedBy.isEmpty else { return }
        let time = now
        guard time - lastSamplingTick <= 5 else { stop(reason: "capture_gap", observedEnd: lastObservedTime); return }
        do {
            if activeAccountKey != captureAccountKey || researchCaptureIdentity != capturedResearchIdentity ||
                DevelopmentSharingController.shared.capturedConsent != developmentConsent {
                try rotateRecording(at: min(time, lastObservedTime), reason: "consent_or_account_boundary")
                resetMouse(at: time, phase: activityPhase) // The transition gap is unobserved.
            }
            lastObservedTime = max(lastObservedTime, time)
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
                append(mouse.move(to: event.location, at: time))
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
    private func isDelete(_ event: ActivityInput) -> Bool { event.keyCode == 51 || event.keyCode == 117 }
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
        if let contract = writer?.contract {
            for row in rows where row.activityPhase == "work" {
                for label in contract.intervals where label.context == .work {
                    let lower = max(row.start, label.start), upper = min(row.end, label.end ?? row.end)
                    if upper > lower { pendingWorkSlices.append(CoverageSlice(start: lower, end: upper, phase: .normal)) }
                }
            }
        }
        rowsRecorded += rows.count
    }
    // Show a recording error and stop safely instead of pretending data is still being saved.
    private func fail(_ error: Error) {
        lifecycle.failed = true
        stop(reason: "recording_error")
        writer = nil
        hasError = true
        message = "Recording stopped: \(error.localizedDescription). Existing files have been kept."
    }
    private func inputInterrupted() {
        guard isRecording else { return }
        stop(reason: "input_monitor_interrupted", observedEnd: lastObservedTime)
        hasError = true
        needsPermission = !InputMonitor.hasPermission
        message = needsPermission
            ? "Recording stopped because Input Monitoring access was lost. Allow access in System Settings, then start a new session."
            : "Input monitoring was interrupted. The session was saved through its last observation. Press Start work to start a new session."
    }
    // Remove input observers and timers, and release the app's recording activity assertion.
    private func removeMonitors() {
        if let backgroundActivity { ProcessInfo.processInfo.endActivity(backgroundActivity) }
        backgroundActivity = nil
        timer?.invalidate()
        timer = nil
        inputMonitor.stop()
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
    func reminderPreferenceChanged() {
        guard !ReminderEligibility.eligible(context: userContext, screenUseEnabled: screenUseReminders) else { return }
        reminderEligibility.invalidate()
        breakNotifications.clearBreaks()
        breakPolicy.contextChanged(at: now, beginsWork: false)
        updateBreakUI(at: now)
    }
    // Advance the break rules, record transitions and send a reminder when needed.
    private func advanceBreakClock(at time: Double, samplingStart: Double? = nil) throws {
        if breakPolicy.phase == .work {
            guard ReminderEligibility.eligible(context: userContext, screenUseEnabled: screenUseReminders),
                  reminderMonotonic >= reminderEligibility.cooldownUntil else { return }
        }
        guard let entry = breakPolicy.tick(at: time) else { return }
        try writer?.logBreak(entry)
        if entry.action == "timer_elapsed" {
            resetMouse(at: samplingStart ?? entry.time, phase: "awaiting_return")
            if let record = breakPolicy.activeBreak {
                breakNotifications.send(session: writer?.contract.recordingID.uuidString ?? "", token: record.id, finished: true)
            }
        } else if entry.action == "prompt" {
            if let contract = writer?.contract, let interval = contract.intervals.last,
               let request = reminderEligibility.schedule(token: entry.promptID, recordingID: contract.recordingID,
                    interval: interval, elapsed: time, monotonic: reminderMonotonic, date: Date(), screenUseEnabled: screenUseReminders) {
                try writer?.logReminder(ReminderLogEntry(request: request, action: "scheduled", effectiveElapsed: time, recordedAtUTC: Date()))
                try writer?.logReminder(ReminderLogEntry(request: request, action: "requested", effectiveElapsed: time, recordedAtUTC: Date()))
                breakNotifications.send(session: contract.recordingID.uuidString, token: entry.promptID, finished: false,
                    screenUse: request.screenUse, workPeriodID: request.workPeriodID?.uuidString ?? "")
            }
        }
        updateBreakUI(at: time)
    }
    // Open the pre-break ratings and setup; opening this sheet is not yet taking a break.
    func chooseBreak() {
        guard isRecording, breakPolicy.phase == .work, !checkInOpen else { return }
        reminderEligibility.invalidate()
        breakNotifications.clearBreaks()
        let time = now
        updateProgress(at: time)
        defer { updateProgress(at: time, persist: true) }
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
        updateProgress(at: time)
        defer { updateProgress(at: time, persist: true) }
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
        updateProgress(at: time)
        defer { updateProgress(at: time, persist: true) }
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
        if let pending = reminderEligibility.pending, let contract = writer?.contract,
           let interval = contract.intervals.last,
           let request = reminderEligibility.consume(token: pending.id, recordingID: contract.recordingID,
                contextID: interval.logicalID, active: isRecording, monotonic: reminderMonotonic, snooze: snooze) {
            do { try writer?.logReminder(ReminderLogEntry(request: request, action: snooze ? "snooze" : "skip", effectiveElapsed: now, recordedAtUTC: Date())) }
            catch { fail(error); return }
        }
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
        updateProgress(at: time)
        defer { updateProgress(at: time, persist: true) }
        if breakPolicy.phase == .awaitingReturn && suspendedBy.isEmpty { append(mouse.stop(at: time)) }
        guard let entry = breakPolicy.finish(at: time, reason: reason) else { return }
        if let record = entry.record,
           dailyProgress.completeBreak(id: record.id, seconds: record.actualSeconds ?? 0,
               reason: reason, at: Date(), calendar: DailyProgress.calendar()) {
            rechargeDate = Date()
            SocialController.shared.record(kind: "break", seconds: record.actualSeconds ?? 0,
                id: UUID(uuidString: record.id) ?? UUID())
            progressDirty = true
        }
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
            updateProgress(at: time)
            guard suspendedBy.insert(reason).inserted else { return }
            updateProgress(at: time, persist: true)
            try writer?.logBreak(breakPolicy.entry(at: time, action: "suspended_\(reason)", record: breakPolicy.activeBreak))
        } catch { fail(error) }
    }
    // Resume the break clock and sampling after wake/login, without assuming the user has returned to work.
    private func resumeAfterSuspension(_ reason: String) {
        guard isRecording, suspendedBy.remove(reason) != nil else { return }
        let time = now
        updateProgress(at: time, persist: true)
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
    private func isReturnInput(_ event: ActivityInput, at time: Double) -> Bool {
        switch event.type {
        case .keyDown: return !event.isARepeat
        case .leftMouseDown, .rightMouseDown, .otherMouseDown: return true
        case .scrollWheel:
            return !event.isMomentum && (event.scrollingDeltaX != 0 || event.scrollingDeltaY != 0)
        case .mouseMoved, .leftMouseDragged, .rightMouseDragged, .otherMouseDragged:
            let point = event.location
            if time - returnWindowStart > 1 { returnDistance = 0; returnWindowStart = time }
            returnDistance += hypot(point.x - returnPoint.x, point.y - returnPoint.y)
            returnPoint = point
            return returnDistance >= 20
        default: return false
        }
    }
    // Route a notification button to its action only if its session and prompt are still current.
    private func notificationAction(session: String, token: String, action: String) {
        guard isRecording, let contract = writer?.contract else { return }
        if timedCheckInPolicy.hasPending, token == timedCheckInPolicy.current?.id,
           sessionFolder?.lastPathComponent == session {
            if action == "answer_check_in" || action == UNNotificationDefaultActionIdentifier {
                openTimedCheckIn()
            } else if action == "skip_check_in" { skipTimedCheckIn() }
        } else if session == contract.recordingID.uuidString, let interval = contract.intervals.last,
                  reminderEligibility.accepts(token: token, recordingID: contract.recordingID, contextID: interval.logicalID, active: true) {
            if action == UNNotificationDefaultActionIdentifier { openMainWindow?(); return }
            guard ["take", "skip", "snooze", "not_working"].contains(action),
                  let request = reminderEligibility.consume(token: token, recordingID: contract.recordingID,
                    contextID: interval.logicalID, active: true, monotonic: reminderMonotonic, snooze: action == "snooze") else { return }
            do { try writer?.logReminder(ReminderLogEntry(request: request, action: action, effectiveElapsed: now, recordedAtUTC: Date())) }
            catch { fail(error); return }
            switch action {
            case "take": chooseBreak(); openMainWindow?()
            case "skip": deferBreak(snooze: false)
            case "snooze": deferBreak(snooze: true)
            case "not_working": setContext(.nonWork, source: .notification)
            default: break
            }
        } else if session == contract.recordingID.uuidString, token == breakPolicy.activeBreak?.id {
            if action == "back" { returnFromBreak(); openMainWindow?() }
            else if action == UNNotificationDefaultActionIdentifier { openMainWindow?() }
        }
    }
    // Schedule one ratings opportunity 10 minutes after session start or an actual break return.
    private func revokeStudyCheckIns() {
        sessionCheckInPresented = false; sessionCheckIn = nil
        if isRecording {
            do {
                try finishTimedCheckIn(action: "consent_withdrawn", at: now)
                try finishBreakCheckIn(status: .cancelled, at: now)
            } catch { fail(error) }
        }
        breakSetupPresented = false
        sessionSurveyOptions = SurveyOptions(beforeSession: false, beforeBreak: false, duringWork: false)
        sessionStudyConfiguration = nil; studyPrompt = nil
    }
    private func scheduleTimedCheckIn(at time: Double, afterBreak: String = "") throws {
        guard let configuration = sessionStudyConfiguration, sessionSurveyOptions.duringWork else { return }
        let item = timedCheckInPolicy.schedule(from: time, afterBreak: afterBreak, delay: configuration.minimumSpacingSeconds)
        try writer?.logSurveyPrompt(SurveyPromptEntry(item: item, action: "scheduled", time: time))
    }
    // Open the requested survey and mark its interaction time separately from work.
    func openTimedCheckIn() {
        guard isRecording, breakPolicy.phase == .work, !checkInOpen,
              let token = timedCheckInPolicy.current?.id,
              let item = timedCheckInPolicy.open(token: token, at: now) else { return }
        let time = item.openedAt!
        updateProgress(at: time)
        defer { updateProgress(at: time, persist: true) }
        do {
            append(mouse.stop(at: time))
            timedCheckInSheet = CheckInPrompt(elapsed: time)
            resetMouse(at: time, phase: "check_in")
            try record(type: "check_in_start", at: time)
            try writer?.logSurveyPrompt(SurveyPromptEntry(item: item, action: "opened", time: time))
            if let studyPrompt { try writer?.logStudyPrompt(StudyPromptLogEntry(prompt: studyPrompt, action: "opened", elapsed: time, recordedAtUTC: Date())) }
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
        updateProgress(at: time)
        defer { updateProgress(at: time, persist: true) }
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
        if let studyPrompt { try writer?.logStudyPrompt(StudyPromptLogEntry(prompt: studyPrompt, action: action, elapsed: time, recordedAtUTC: Date())) }
        studyPrompt = nil
        if ["answered", "skipped", "cancelled"].contains(action), isRecording, sessionStudyConfiguration != nil {
            try scheduleTimedCheckIn(at: time)
        }
    }
    private func loadProgress() {
        do {
            let store = try ProgressStore.local()
            do { dailyProgress = try store.load() }
            catch {
                // Recovery never reads or changes the session library.
                try store.preserveUnreadableFile()
                progressNotice = "Saved progress could not be read. A backup was kept; new progress starts today."
            }
            dailyProgress.reconcile(at: Date(), calendar: DailyProgress.calendar())
            progressStore = store
            progressDirty = true
            try store.save(dailyProgress)
            progressDirty = false
        } catch {
            progressNotice = "Progress is available for this launch, but its local file could not be opened."
        }
    }

    private var reconciledSocialScope: String?
    func reconcileProgress() {
        let scope = SocialController.shared.declaredWorkScope.map { "\($0.origin)|\($0.owner)" }
        if scope != reconciledSocialScope {
            reconciledSocialScope = scope
            reconcileSavedProgress()
        }
        // Restore the current owner's latest replacement totals after account switches;
        // corrections made while signed out never transfer to the next account.
        let previous = dailyProgress
        dailyProgress.reconcile(at: Date(), calendar: DailyProgress.calendar())
        progressDirty = progressDirty || previous != dailyProgress
        guard progressDirty, let store = progressStore else { return }
        do { try store.save(dailyProgress); progressDirty = false }
        catch { progressNotice = "Progress could not be saved. FocusFix will retry." }
    }

    func keepGoingAfterPlan() { sessionWorkPlan.keepGoing() }

    private func applyObservedWork() throws {
        guard let contract = writer?.contract else { return }
        let slices = pendingWorkSlices
        pendingWorkSlices = []
        let calendar = DailyProgress.calendar(timeZone: TimeZone(identifier: contract.scoringTimeZone) ?? .current)
        segmentWorkIntervals = DeclaredWorkInterval.merged(segmentWorkIntervals + DeclaredWorkInterval.observed(slices, startedAt: startedAt, origin: contract.elapsedOrigin))
        let allocation = DailyProgress.declaredAllocation(slices: slices, startedAt: startedAt, origin: contract.elapsedOrigin, calendar: calendar)
        for (day, seconds) in allocation { segmentWorkDays[day, default: 0] += seconds }
        try dailyProgress.replaceDeclaredWork(segmentID: contract.segmentID.uuidString, days: segmentWorkDays,
            owner: segmentWorkOwner)
        let seconds = slices.reduce(0) { $0 + $1.end - $1.start }
        declaredWorkSeconds += seconds; sessionWorkPlan.credit(seconds)
        progressDirty = true
        SocialController.shared.stageDeclaredWork(segmentID: contract.segmentID, days: segmentWorkDays,
            capturedOwner: segmentWorkOwner?.ownerID, capturedOrigin: segmentWorkOwner?.origin,
            startedAt: startedAt.timeIntervalSince1970,
            observedThrough: startedAt.timeIntervalSince1970 + contract.observedThrough - contract.elapsedOrigin,
            intervals: segmentWorkIntervals)
    }
    private func reconcileSavedProgress() {
        progressReconciliation?.cancel()
        let candidates = sessions.filter { session in
            guard let contract = session.recordingContract, contract.finalized else { return false }
            return dailyProgress.declaredSegments[contract.segmentID.uuidString] == nil
                || dailyProgress.declaredRevisions[contract.segmentID.uuidString] != contract.revisions.count
                || (dailyProgress.declaredOwners[contract.segmentID.uuidString]?.ownerID == SocialController.shared.userID
                    && SocialController.shared.needsDeclaredWorkDetails(contract.segmentID,
                        days: dailyProgress.declaredSegments[contract.segmentID.uuidString] ?? [:]))
        }
        progressReconciliation = Task { [weak self] in
            for session in candidates {
                guard !Task.isCancelled, let self, let contract = session.recordingContract else { return }
                do {
                    let coverage = try await Task.detached { try RecordingCoverage.load(session: session) }.value
                    guard !Task.isCancelled else { return }
                    let allocation = DailyProgress.declaredAllocation(slices: coverage.workSlices, startedAt: session.startedAt,
                        origin: contract.elapsedOrigin, calendar: DailyProgress.calendar(timeZone: TimeZone(identifier: contract.scoringTimeZone) ?? .current))
                    try self.dailyProgress.replaceDeclaredWork(segmentID: contract.segmentID.uuidString, days: allocation, revision: contract.revisions.count)
                    let owner = self.dailyProgress.declaredOwners[contract.segmentID.uuidString]
                    SocialController.shared.stageDeclaredWork(segmentID: contract.segmentID, days: allocation,
                        capturedOwner: owner?.ownerID, capturedOrigin: owner?.origin,
                        startedAt: session.startedAt.timeIntervalSince1970,
                        observedThrough: session.startedAt.timeIntervalSince1970 + contract.observedThrough - contract.elapsedOrigin,
                        intervals: DeclaredWorkInterval.observed(coverage.workSlices, startedAt: session.startedAt, origin: contract.elapsedOrigin))
                    self.progressDirty = true; self.reconcileProgress()
                } catch { self.progressNotice = "Declared-work coverage could not be reconciled. Existing progress was kept; refresh to retry." }
            }
        }
    }
    private func updateProgress(at time: Double, persist: Bool = false) {
        let previous = dailyProgress
        dailyProgress.reconcile(at: Date(), calendar: DailyProgress.calendar())
        progressDirty = progressDirty || previous != dailyProgress
        guard persist || time - lastProgressSave >= 15 else { return }
        lastProgressSave = time
        guard progressDirty, let store = progressStore else { return }
        do {
            try store.save(dailyProgress)
            progressDirty = false
            progressNotice = nil
        } catch {
            progressNotice = "Progress could not be saved. FocusFix will retry; recording can continue."
        }
    }

    // Reload saved session metadata so the library matches the local files.
    func refreshSessions() {
        sessionRefresh?.cancel()
        sessionRefresh = Task { [weak self] in
            do {
                // Large histories must never block input delivery or the sampling clock.
                let listing = try await Task.detached(priority: .utility) {
                    try SessionFiles.inspect(in: SessionFiles.root())
                }.value
                guard !Task.isCancelled, let self else { return }
                self.sessions = listing.sessions
                self.libraryNotice = listing.unreadable > 0 ? "\(listing.unreadable) unreadable or unsupported recordings were kept. Compatible history remains available; Export All is blocked until those files are reviewed." : nil
                self.libraryError = nil
                self.reconcileSavedProgress()
            } catch {
                guard !Task.isCancelled else { return }
                self?.libraryError = error.localizedDescription
            }
        }
    }
    // Check whether a library entry is the session currently being recorded.
    func isActive(_ session: SavedSession) -> Bool {
        isRecording && SessionFiles.sameFolder(session.folder, sessionFolder)
    }
    func updateTags(_ tags: [String], colors: [String: String] = [:], for session: SavedSession) throws {
        let valid = try SessionTags.validated(tags)
        let validColors = try SessionTags.colors(colors, for: valid)
        if isActive(session) {
            guard let writer else { throw CocoaError(.fileWriteUnknown) }
            try writer.updateTags(valid, colors: validColors)
        } else {
            try SessionFiles.updateTags(valid, colors: validColors, for: session, root: SessionFiles.root(),
                                        active: isRecording ? sessionFolder : nil)
        }
        if SessionFiles.sameFolder(session.folder, sessionFolder) {
            sessionTags = valid
            sessionTagColors = validColors
        }
        refreshSessions()
    }
    func updateCurrentTags(_ tags: [String], colors: [String: String]) throws {
        guard let sessionFolder else {
            // An idle timer can label the upcoming session before its start sheet opens.
            guard !isRecording else { throw CocoaError(.fileNoSuchFile) }
            let valid = try SessionTags.validated(tags)
            let validColors = try SessionTags.colors(colors, for: valid)
            sessionTags = valid; sessionTagColors = validColors
            return
        }
        try updateTags(tags, colors: colors, for: SavedSession(folder: sessionFolder))
    }
    // Move an inactive local session to Trash. Cloud research-data deletion is separate.
    func deleteSession(_ session: SavedSession) throws {
        try SessionFiles.validate(session.folder, in: SessionFiles.root(),
            active: isRecording ? sessionFolder : nil)
        try FileManager.default.trashItem(at: session.folder, resultingItemURL: nil)
        if SessionFiles.sameFolder(session.folder, sessionFolder) { sessionFolder = nil; sessionTags = []; sessionTagColors = [:] }
        refreshSessions()
    }
    // Keep destination access alive while the background copy runs.
    func exportAllSavedSessions() async throws -> (folder: URL, count: Int)? {
        try await exportSavedSessions(nil)
    }

    // A nil selection means Export All; an explicit selection exports exactly those folders.
    func exportSavedSessions(_ selected: [SavedSession]?) async throws -> (folder: URL, count: Int)? {
        let panel = NSOpenPanel()
        panel.title = selected == nil ? "Export all saved sessions" : "Export selected sessions"
        panel.message = selected.map { "Copies \($0.count) selected sessions into one folder." }
            ?? "Copies all saved sessions into one folder. The current recording is skipped."
        panel.prompt = "Export here"
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.canCreateDirectories = true
        panel.allowsMultipleSelection = false
        guard panel.runModal() == .OK, let destination = panel.url else { return nil }
        let scopedAccess = destination.startAccessingSecurityScopedResource()
        defer { if scopedAccess { destination.stopAccessingSecurityScopedResource() } }
        let root = try SessionFiles.root()
        let active = isRecording ? sessionFolder : nil
        return try await Task.detached(priority: .userInitiated) {
            if let selected {
                return try SessionFiles.exportSelected(selected, to: destination, root: root, active: active)
            }
            return try SessionFiles.exportAll(to: destination, root: root, active: active)
        }.value
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
        let scopedAccess = destination.startAccessingSecurityScopedResource()
        defer { if scopedAccess { destination.stopAccessingSecurityScopedResource() } }
        return try SessionFiles.export(session, to: destination, root: SessionFiles.root(),
            active: isRecording ? sessionFolder : nil)
    }
}
