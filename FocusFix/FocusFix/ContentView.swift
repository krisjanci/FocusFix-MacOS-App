// MARK: - FF: UI
// Builds the main recording screen, appearance controls and sheets; recording logic stays in ActivityTracker.

import SwiftUI
import AppKit

struct ContentView: View {
    @ObservedObject var tracker: ActivityTracker
    var launchReady = true
    @ObservedObject private var dailySurvey = StartOfDayController.shared
    @ObservedObject private var profile = ProfileController.shared
    @ObservedObject private var account = AccountController.shared
    @ObservedObject private var tour = QuickTourController.shared
    @Environment(\.openWindow) private var openWindow
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @AppStorage("appearance") private var appearance = "system"
    @State private var sharingPresented = false
    @State private var showingProjects = false
    @ObservedObject private var projects = ProjectStore.shared
    @State private var editingConditions = false
    @State private var editingActivity = false
    @ObservedObject var social = SocialController.shared
    @State private var panels = CollectorPanelSelection()
    @ObservedObject private var badges = BadgeController.shared
    @State private var collectorWindow: NSWindow?
    @State private var collectorHeight: CGFloat = 620
    private let teal = Color(red: 0.02, green: 0.60, blue: 0.54)
    // Choose the break appearance only while recording a break or waiting for return.
    private var onBreak: Bool { tracker.isRecording && tracker.breakPhase != .work }

    // Arrange the main UI and route buttons/sheets to the tracker rather than duplicating recording logic.
    var body: some View {
        HStack(alignment: .top, spacing: 0) {
            collectorContent
                .fixedSize(horizontal: false, vertical: true)
                .background(GeometryReader { geometry in
                    Color.clear.preference(key: CollectorHeightKey.self, value: geometry.size.height)
                })
                .background(Color(nsColor: .windowBackgroundColor))
            if let panel = panels.expanded {
                HStack(spacing: 0) {
                    Rectangle().fill(Color.primary.opacity(0.08)).frame(width: 1)
                    sidePanel(panel, close: { panels.close() })
                        .frame(width: PeopleWindowLayout.panelWidth)
                }
                // Panels scroll within the collector's height; opening one only adds width.
                .frame(height: collectorHeight)
                .transition(.opacity)
            }
        }
        // Keep the minimum width compact so SwiftUI doesn't force the window to
        // its expanded size before AppKit can animate the frame.
        .frame(minWidth: PeopleWindowLayout.compactWidth, maxWidth: .infinity, alignment: .leading)
        .fixedSize(horizontal: false, vertical: true)
        .background(Color(nsColor: .windowBackgroundColor))
        .clipped()
        .modifier(BadgeCelebrationHost(badges: badges, showsCelebration: dailySurvey.presented == nil && !dailySurvey.isDue() && panels.sheet == nil &&
            !sharingPresented && !editingConditions && !editingActivity &&
            !tracker.recordingNoticePresented && !tracker.breakSetupPresented &&
            !tracker.sessionCheckInPresented && !tracker.timedCheckInPresented))
        .blur(radius: dailySurvey.presented == nil ? 0 : 8)
        .disabled(dailySurvey.presented != nil)
        .accessibilityHidden(dailySurvey.presented != nil)
        .overlay {
            if dailySurvey.presented != nil {
                StartOfDaySurveyView(survey: dailySurvey)
            }
        }
        .task(id: "\(launchReady)-\(dailySurvey.enabled)-\(surveyCanAppear)") { showDailySurveyIfReady() }
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in
            showDailySurveyIfReady()
        }
        .onReceive(NotificationCenter.default.publisher(for: NSWindow.didBecomeKeyNotification)) { note in
            if let window = note.object as? NSWindow, window === collectorWindow { showDailySurveyIfReady() }
        }
        .onChange(of: badges.collectionRequest) { _, _ in showBadgeCollection() }
        .onAppear { if badges.collectionRequested { showBadgeCollection() } }
        .animation(reduceMotion ? nil : .easeInOut(duration: PeopleWindowAnimation.duration), value: panels.expanded)
        .modifier(CollectorWindowResizeLock())
        .onPreferenceChange(CollectorHeightKey.self) { if $0 > 0 { collectorHeight = $0 } }
        .background(PeopleWindowBridge(expanded: panels.expanded != nil, reduceMotion: reduceMotion, resolved: { collectorWindow = $0; showDailySurveyIfReady() }))
        .sheet(item: $panels.sheet) { panel in
            sidePanel(panel, close: { panels.close() }).frame(width: 380, height: 580)
                .modifier(BadgeCelebrationHost(badges: badges))
        }
        .onChange(of: tour.isPresented) { _, shown in
            if shown { panels.close(); showingProjects = false }
        }
        .onReceive(NotificationCenter.default.publisher(for: NSWindow.didChangeScreenNotification)) { note in
            guard let window = note.object as? NSWindow, window === collectorWindow,
                  let screen = window.screen else { return }
            panels.adapt(canExpand: PeopleWindowLayout.canExpand(in: screen.visibleFrame))
        }
    }

    private var surveyCanAppear: Bool {
        launchReady && !tour.isPresented && !RecordingNotice().needsFirstLaunchChoice &&
        panels.sheet == nil && !sharingPresented && !editingConditions && !editingActivity &&
        !tracker.recordingNoticePresented && !tracker.breakSetupPresented &&
        !tracker.sessionCheckInPresented && !tracker.timedCheckInPresented
    }

    private func showDailySurveyIfReady() {
        // Prepare the overlay on automatic launches even if another app has focus.
        guard surveyCanAppear, collectorWindow?.isVisible == true else { return }
        dailySurvey.showIfDue()
    }

    private func showBadgeCollection() {
        if panels.expanded != .analytics && panels.sheet != .analytics {
            togglePanel(.analytics)
        }
    }

    private func togglePanel(_ panel: CollectorPanel) {
        let canExpand = collectorWindow?.screen.map { PeopleWindowLayout.canExpand(in: $0.visibleFrame) } ?? false
        panels.toggle(panel, canExpand: canExpand)
    }

    @ViewBuilder private func sidePanel(_ panel: CollectorPanel, close: @escaping () -> Void) -> some View {
        switch panel {
        case .groups: PeoplePanel(social: social, close: close)
        case .analytics: AnalyticsPanel(close: close, anchorsCelebration: panels.sheet == .analytics)
        }
    }

    private var appearanceSymbol: String {
        switch appearance {
        case "light": "sun.max"
        case "dark": "moon"
        default: "circle.lefthalf.filled"
        }
    }

    private var nextAppearance: String {
        appearance == "light" ? "dark" : appearance == "dark" ? "system" : "light"
    }

    private var appearanceButton: some View {
        Button { appearance = nextAppearance } label: {
            Image(systemName: appearanceSymbol).frame(width: 28, height: 24)
        }.buttonPressFeedback()
        .buttonStyle(.plain)
        .accessibilityLabel("Appearance")
        .accessibilityValue(appearance.capitalized)
        .accessibilityHint("Switch to \(nextAppearance.capitalized)")
        .help("Appearance: \(appearance.capitalized). Click to switch to \(nextAppearance.capitalized).")
    }

    private var collectorContent: some View {
        VStack(alignment: .leading, spacing: 20) {
            VStack(alignment: .leading, spacing: 20) {
            HStack(spacing: 14) {
                Button { sharingPresented = true } label: {
                    ProfileAvatar(profile: account.session == nil ? profile.profile : account.profile, size: 30)
                }.buttonPressFeedback().buttonStyle(.plain).foregroundStyle(.secondary)
                    .help("Your profile")
                    .accessibilityLabel((account.session == nil ? profile.profile : account.profile).map { "Profile for \($0.name), your profile" } ?? "Your profile")
                Image(nsImage: NSApplication.shared.applicationIconImage)
                    .resizable().scaledToFit().frame(width: 36, height: 36)
                    .accessibilityHidden(true)
                VStack(alignment: .leading, spacing: 4) {
                    Text("FocusFix").font(.system(size: 25, weight: .semibold, design: .rounded))
                    Text("FOCUS · REST · REPEAT").font(.system(size: 10, weight: .semibold))
                        .tracking(2).foregroundStyle(.secondary)
                }
                Spacer()
                WorkStreakBadge(tracker: tracker)
            }
            HStack(alignment: .top) {
                RecordingStatusPanel(state: tracker.captureState, mode: tracker.recordingMode, context: tracker.userContext, phase: tracker.interventionPhase)
                appearanceButton
            }
            VStack(spacing: 20) {
            VStack(spacing: 16) {
                if onBreak, let record = tracker.currentBreak {
                    Image(systemName: "leaf").font(.system(size: 28, weight: .light)).foregroundStyle(teal)
                    Text(tracker.breakPhase == .resting ? "TIME TO UNWIND" : "TAKE YOUR TIME")
                        .font(.caption2.weight(.medium)).tracking(2).foregroundStyle(.secondary)
                    Text(durationText(max(0, record.deadline - tracker.elapsed)))
                        .font(.system(size: 46, weight: .light, design: .rounded)).monospacedDigit()
                    Text(record.plannedActivity).font(.headline)
                    if tracker.breakPhase != .resting {
                        Text("Tracking resumed · waiting for your return")
                            .font(.caption).foregroundStyle(.secondary)
                    }
                } else {
                    SessionClockFace(time: durationText(floor(tracker.declaredWorkSeconds)))
                        .help("Time recorded while you declared work; other activity and breaks are excluded.")
                }
                if tracker.isRecording, tracker.sessionWorkPlan.targetMinutes != nil {
                    Text(tracker.sessionWorkPlan.summary)
                        .font(.caption).monospacedDigit().foregroundStyle(.secondary)
                    if tracker.sessionWorkPlan.isComplete {
                        HStack {
                            Label("Plan complete", systemImage: "checkmark.circle.fill")
                                .font(.callout.weight(.medium)).foregroundStyle(teal)
                            if tracker.sessionWorkPlan.reminderPending {
                                Spacer()
                                Button("End work") { tracker.endWork() }.buttonPressFeedback()
                                Button("Keep going") { tracker.keepGoingAfterPlan() }.buttonPressFeedback()
                            }
                        }
                    }
                }
                ConditionChipLayout(spacing: 8) {
                    Button { showingProjects = true } label: {
                        Label("Task", systemImage: "doc.text")
                            .font(.caption).padding(.horizontal, 8).padding(.vertical, 4)
                            .background(Color.primary.opacity(0.06), in: Capsule())
                    }.buttonPressFeedback().buttonStyle(.plain).help("Projects and tasks")
                    Button { tracker.requestWorkTarget() } label: {
                        Label(tracker.timerTargetMinutes.map { "Work target · \($0) min" } ?? "Work target", systemImage: "scope")
                            .font(.caption).lineLimit(1).padding(.horizontal, 8).padding(.vertical, 4)
                            .background(Color.primary.opacity(0.06), in: Capsule())
                    }.buttonPressFeedback().buttonStyle(.plain).help("Choose a work target")
                    Button {
                        if tracker.canOpenWorkSetup() { editingConditions = true }
                    } label: {
                        Label("Conditions", systemImage: "plus")
                            .font(.caption).padding(.horizontal, 8).padding(.vertical, 4)
                            .background(Color.primary.opacity(0.06), in: Capsule())
                    }.buttonPressFeedback().buttonStyle(.plain)
                        .help("Choose session conditions such as location, music, or work setting")
                        .accessibilityLabel("Add Conditions")
                    if tracker.isRecording && !tracker.completedBreaks.isEmpty {
                        Button { editingActivity = true } label: {
                            Label("Edit activity", systemImage: "square.and.pencil")
                                .font(.caption).lineLimit(1).padding(.horizontal, 8).padding(.vertical, 4)
                                .background(Color.primary.opacity(0.06), in: Capsule())
                        }.buttonPressFeedback().buttonStyle(.plain)
                            .help("Edit activities for all completed breaks in this session")
                    }
                }.frame(maxWidth: .infinity, alignment: .leading)
                if tracker.isWorking, tracker.workAssignment.projectID != nil {
                    HStack(spacing: 8) {
                        Button { showingProjects = true } label: {
                            Text(tracker.workAssignment.summary).font(.caption).lineLimit(2)
                                .frame(maxWidth: .infinity, alignment: .leading)
                        }.buttonStyle(.plain).help("Change project or task")
                        if !onBreak, tracker.workAssignment.taskID != nil {
                            Button { tracker.finishCurrentTask() } label: {
                                Label("Finished task", systemImage: "checkmark")
                                    .font(.caption).lineLimit(1).padding(.horizontal, 8).padding(.vertical, 4)
                                    .foregroundStyle(.green)
                                    .background(Color.green.opacity(0.06), in: Capsule())
                                    .overlay { Capsule().stroke(Color.green.opacity(0.75), lineWidth: 1) }
                            }.buttonPressFeedback().buttonStyle(.plain)
                                .help("Check off this task, save its time, and continue work without a project")
                        }
                    }.frame(maxWidth: .infinity, alignment: .leading)
                }
                if !tracker.timerConditions.isEmpty {
                    Button { if tracker.canOpenWorkSetup() { editingConditions = true } } label: {
                        SessionConditionSummary(conditions: tracker.timerConditions)
                    }.buttonStyle(.plain).buttonPressFeedback().help("Edit session conditions")
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
            }
            .frame(maxWidth: .infinity).padding(26)
            .background {
                TagTintBackground(colors: tracker.isWorking ? [tracker.workAssignment.projectColor].compactMap { $0 } : [],
                                  opacity: onBreak ? 0.2 : 0.15)
                    .clipShape(RoundedRectangle(cornerRadius: 16))
            }

            DailyProgressCard(tracker: tracker)
            }


            HStack(spacing: 12) {
                Button {
                    if tracker.isWorking { tracker.endWork() } else { tracker.requestStart() }
                } label: {
                    Label(tracker.isWorking ? "End work" : "Start work",
                          systemImage: tracker.isWorking ? "stop.fill" : "play.fill")
                        .frame(maxWidth: .infinity, minHeight: 36)
                }.buttonPressFeedback().buttonStyle(.borderedProminent).tint(teal).controlSize(.large)
                if onBreak {
                    Button { tracker.returnFromBreak() } label: {
                        Label("I'm back", systemImage: "arrow.uturn.backward")
                            .frame(maxWidth: .infinity, minHeight: 36)
                    }.buttonPressFeedback().buttonStyle(.borderedProminent).tint(teal).controlSize(.large)
                } else if tracker.isWorking {
                    Button { tracker.chooseBreak() } label: {
                        Label("Take a break", systemImage: "leaf")
                            .frame(maxWidth: .infinity, minHeight: 36)
                    }.buttonPressFeedback().buttonStyle(.borderedProminent).tint(teal).controlSize(.large)
                }
            }

            if tracker.timedCheckInPending && !onBreak {
                VStack(alignment: .leading, spacing: 8) {
                    Text(CheckInPromptCopy.title).font(.callout.weight(.medium))
                    Text(CheckInPromptCopy.question).font(.callout).foregroundStyle(.secondary)
                    HStack {
                        Button("Answer") { tracker.openTimedCheckIn() }.buttonPressFeedback()
                        Button("Skip") { tracker.skipTimedCheckIn() }.buttonPressFeedback()
                    }
                }
            }

            if tracker.isRecording && !onBreak &&
                (tracker.breakPromptPending || tracker.notificationNotice != nil) {
                BreakControls(tracker: tracker, showsTakeBreak: false).tint(teal)
            }


            if tracker.notificationPermission.needsAttention && !onBreak {
                VStack(alignment: .leading, spacing: 8) {
                    Label("Turn on notifications", systemImage: "bell.badge")
                        .font(.callout.weight(.medium))
                    Text(tracker.notificationPermission.opensSettings
                         ? "In System Settings → Notifications → FocusFix, allow notifications and choose Banners or Alerts."
                         : "Get reminders for breaks and check-ins. You can still use FocusFix without notifications.")
                        .font(.caption).foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                    Button(tracker.notificationPermission.opensSettings ? "Open notification settings" : "Enable notifications") {
                        if tracker.notificationPermission.opensSettings { tracker.openNotificationSettings() }
                        else { tracker.enableNotifications() }
                    }.buttonPressFeedback().disabled(tracker.notificationPermissionBusy)
                    if let notice = tracker.notificationNotice {
                        Text(notice).font(.caption).foregroundStyle(.secondary)
                    }
                }.padding(14).frame(maxWidth: .infinity, alignment: .leading)
                    .background(teal.opacity(0.06), in: RoundedRectangle(cornerRadius: 12))
            }

            // Only actionable problems belong on the main recording screen.
            if tracker.hasError {
                Text(tracker.message).font(.callout)
                    .fixedSize(horizontal: false, vertical: true)
                    .foregroundStyle(Color.red)
            }
            if tracker.needsPermission {
                VStack(alignment: .leading, spacing: 8) {
                    Label("Input Monitoring", systemImage: "keyboard")
                        .font(.callout.weight(.medium))
                    Text(tracker.message)
                        .font(.caption).foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                    Button("Enable Input Monitoring") { tracker.requestPermission() }.buttonPressFeedback()
                        .buttonStyle(.borderedProminent).tint(teal)
                }.padding(14).frame(maxWidth: .infinity, alignment: .leading)
                    .background(teal.opacity(0.06), in: RoundedRectangle(cornerRadius: 12))
            }
            }
            // Keep the original layout as the size reference while tasks use all of its space.
            .opacity(showingProjects ? 0 : 1)
            .allowsHitTesting(!showingProjects)
            .accessibilityHidden(showingProjects)
            .overlay {
                ProjectsView(store: projects, tracker: tracker, close: { showingProjects = false })
                    .opacity(showingProjects ? 1 : 0)
                    .allowsHitTesting(showingProjects)
                    .accessibilityHidden(!showingProjects)
            }

            HStack {
                Button { togglePanel(.groups) } label: {
                    HStack(spacing: 6) {
                        Label(panels.expanded == .groups ? "Hide people" : "Groups", systemImage: "person.2")
                        if !social.invitations.isEmpty {
                            Circle().fill(.red).frame(width: 7, height: 7)
                                .accessibilityLabel("\(social.invitations.count) pending invitations")
                        }
                    }
                }.buttonPressFeedback().buttonStyle(.plain).foregroundStyle(.secondary)
                    .accessibilityLabel((panels.expanded == .groups ? "Collapse People panel" : "Expand group People panel") + (social.invitations.isEmpty ? "" : ", \(social.invitations.count) pending group invitations"))
                    .help("Show people in your selected group")
                    .frame(maxWidth: .infinity, alignment: .leading)
                Button { openWindow(id: "sessions") } label: {
                    Image(systemName: "folder").accessibilityLabel("Sessions")
                }.buttonPressFeedback().controlSize(.large)
                Button { togglePanel(.analytics) } label: {
                    HStack(spacing: 6) {
                        Label("Analytics", systemImage: "chart.bar.xaxis")
                        if badges.hasUnread { BadgeUnreadDot() }
                    }
                    .anchorPreference(key: AnalyticsBadgeAnchor.self, value: .bounds) { $0 }
                }.buttonPressFeedback()
                .buttonStyle(.plain)
                .foregroundStyle(panels.expanded == .analytics ? teal : Color.secondary)
                .accessibilityLabel((panels.expanded == .analytics ? "Collapse Analytics panel" : "Expand Analytics panel") + (badges.hasUnread ? ", new badges" : ""))
                .help("Analytics")
                .frame(maxWidth: .infinity, alignment: .trailing)
            }
        }
        .padding(30).frame(width: 490)
        .background(Color(nsColor: .windowBackgroundColor))
        .onChange(of: tour.isPresented) { _, shown in if shown { sharingPresented = false } }
        .sheet(isPresented: $sharingPresented) { SharingView() }
        .sheet(isPresented: $editingActivity) { BreakActivityEditor(tracker: tracker) }
        .sheet(isPresented: $editingConditions) {
            SessionConditionEditor(conditions: tracker.timerConditions,
                confirmationTitle: tracker.isWorking ? "Done" : "Start work") { conditions in
                try tracker.saveTimerConditions(conditions)
            }
        }
        .sheet(isPresented: $tracker.recordingNoticePresented) { RecordingNoticeView(tracker: tracker).tint(teal).interactiveDismissDisabled() }
        .sheet(isPresented: $tracker.breakSetupPresented, onDismiss: { tracker.cancelBreakCheckIn() }) {
            BreakSetupView(tracker: tracker).tint(teal)
        }
        .sheet(isPresented: $tracker.sessionCheckInPresented, onDismiss: { tracker.cancelSessionCheckIn() }) {
            SessionCheckInView(tracker: tracker).tint(teal)
        }
        .sheet(isPresented: $tracker.timedCheckInPresented, onDismiss: { tracker.cancelTimedCheckIn() }) {
            WorkCheckInView(tracker: tracker).tint(teal)
        }
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in
            tracker.reconcileProgress()
            Task { await SocialController.shared.refresh() }
            tracker.refreshNotificationPermission()
            tracker.refreshInputPermission()
        }
    }
}
