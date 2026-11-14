// MARK: - FF: UI
// Builds the main recording screen, appearance controls and sheets; recording logic stays in ActivityTracker.

import SwiftUI
import AppKit

struct ContentView: View {
    @ObservedObject var tracker: ActivityTracker
    @ObservedObject private var profile = ProfileController.shared
    @ObservedObject private var account = AccountController.shared
    @ObservedObject private var tour = QuickTourController.shared
    @Environment(\.openWindow) private var openWindow
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @AppStorage("appearance") private var appearance = "system"
    @State private var sharingPresented = false
    @State private var editingSessionTags = false
    @ObservedObject private var tagLibrary = SessionTagLibrary.shared
    @ObservedObject var social = SocialController.shared
    @State private var panelSheet: CollectorPanel?
    @State private var selectedPanel: CollectorPanel = .groups
    @State private var fullScreen = false
    @State private var screenContentSize = CGSize(width: 1200, height: 800)
    @Namespace private var panelSwitch
    @State private var collectorHeight: CGFloat = 620
    private let teal = Color(red: 0.02, green: 0.60, blue: 0.54)
    // Choose the break appearance only while recording a break or waiting for return.
    private var onBreak: Bool { tracker.isRecording && tracker.breakPhase != .work }

    // Arrange the main UI and route buttons/sheets to the tracker rather than duplicating recording logic.
    var body: some View {
        Group {
            if fullScreen {
                let scale = CollectorWindowLayout.fullScreenScale(contentHeight: collectorHeight, available: screenContentSize)
                HStack(spacing: 0) {
                    measuredCollector
                        .scaleEffect(scale, anchor: .topLeading)
                        .frame(width: CollectorWindowLayout.compactWidth * scale, height: screenContentSize.height, alignment: .topLeading)
                    Divider()
                    VStack(spacing: 0) {
                        sidePanel(selectedPanel, permanent: true, close: {})
                        panelPicker.padding(20)
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                }
                .frame(width: screenContentSize.width, height: screenContentSize.height)
            } else {
                measuredCollector
            }
        }
        .background(Color(nsColor: .windowBackgroundColor))
        .clipped()
        .modifier(CollectorWindowResizeLock())
        .onPreferenceChange(CollectorHeightKey.self) { if $0 > 0 { collectorHeight = $0 } }
        .background(PeopleWindowBridge(fullScreen: fullScreen, resolved: { size in
            if screenContentSize != size { screenContentSize = size }
        }))
        .sheet(item: $panelSheet) { panel in
            sidePanel(panel, close: { panelSheet = nil }).frame(width: 380, height: 580)
        }
        .onChange(of: tour.isPresented) { _, shown in
            if shown { panelSheet = nil }
        }
    }

    private var measuredCollector: some View {
        collectorContent
            .fixedSize(horizontal: false, vertical: true)
            .background(GeometryReader { geometry in
                Color.clear.preference(key: CollectorHeightKey.self, value: geometry.size.height)
            })
    }

    private func togglePanel(_ panel: CollectorPanel) {
        if fullScreen { selectedPanel = panel } else { panelSheet = panel }
    }

    @ViewBuilder private func sidePanel(_ panel: CollectorPanel, permanent: Bool = false, close: @escaping () -> Void) -> some View {
        switch panel {
        case .groups: PeoplePanel(social: social, close: close, allowsCollapsing: !permanent)
        case .analytics: AnalyticsPanel(close: close, allowsCollapsing: !permanent)
        }
    }

    private var panelPicker: some View {
        HStack(spacing: 0) {
            panelTab(.groups, title: "Groups", symbol: "person.2")
            panelTab(.analytics, title: "Analytics", symbol: "chart.bar.xaxis")
        }
        .padding(5)
        .background(Color.primary.opacity(0.07), in: Capsule())
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Right panel")
    }

    private func panelTab(_ panel: CollectorPanel, title: String, symbol: String) -> some View {
        Button {
            withAnimation(reduceMotion ? nil : .easeInOut(duration: 0.25)) { selectedPanel = panel }
        } label: {
            Label(title, systemImage: symbol)
                .font(.headline)
                .foregroundStyle(selectedPanel == panel ? teal : Color.secondary)
                .frame(maxWidth: .infinity).padding(.vertical, 14)
                .background {
                    if selectedPanel == panel {
                        Capsule().fill(Color(nsColor: .windowBackgroundColor))
                            .matchedGeometryEffect(id: "selection", in: panelSwitch)
                            .shadow(color: .black.opacity(0.08), radius: 3, y: 1)
                    }
                }
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(selectedPanel == panel ? .isSelected : [])
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
                Button {
                    panelSheet = nil
                    fullScreen.toggle()
                } label: {
                    Image(systemName: fullScreen ? "arrow.down.right.and.arrow.up.left" : "arrow.up.left.and.arrow.down.right")
                        .frame(width: 26, height: 26)
                }.buttonStyle(.plain).buttonPressFeedback()
                    .help(fullScreen ? "Use compact window" : "Use full screen")
                    .accessibilityLabel(fullScreen ? "Use compact window" : "Use full screen")
            }
            HStack(alignment: .top) {
                RecordingStatusPanel(state: tracker.captureState, mode: tracker.recordingMode, context: tracker.userContext, phase: tracker.interventionPhase)
                appearanceButton
            }
            VStack(spacing: 16) {
                if onBreak, let record = tracker.currentBreak {
                    Image(systemName: "leaf").font(.system(size: 28, weight: .light)).foregroundStyle(teal)
                    Text(tracker.breakPhase == .resting ? "TIME TO UNWIND" : "TAKE YOUR TIME")
                        .font(.caption2.weight(.medium)).tracking(2).foregroundStyle(.secondary)
                    Text(durationText(max(0, record.deadline - tracker.elapsed)))
                        .font(.system(size: 46, weight: .light, design: .rounded)).monospacedDigit()
                    Text(record.plannedActivity).font(.headline)
                    Text("Break time · \(durationText(tracker.elapsed - record.start))")
                        .font(.caption).monospacedDigit().foregroundStyle(.secondary)
                    Text(tracker.breakPhase == .resting ? "Activity logging paused" : "Tracking resumed · waiting for your return")
                        .font(.caption).foregroundStyle(.secondary)
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
                HStack(spacing: 8) {
                    SessionTagButton(tags: tracker.timerTags,
                        colors: tagLibrary.resolvedColors(for: tracker.timerTags, saved: tracker.timerTagColors)) {
                            if tracker.canOpenWorkSetup() { editingSessionTags = true }
                        }
                    Button { tracker.requestWorkTarget() } label: {
                        Label(tracker.timerTargetMinutes.map { "Work target · \($0) min" } ?? "Work target", systemImage: "scope")
                            .font(.caption).lineLimit(1).padding(.horizontal, 8).padding(.vertical, 4)
                            .background(Color.primary.opacity(0.06), in: Capsule())
                    }.buttonPressFeedback().buttonStyle(.plain).help("Choose a work target")
                    Spacer(minLength: 0)
                }
            }
            .frame(maxWidth: .infinity).padding(26)
            .background {
                TagTintBackground(colors: tracker.timerTags.map { tagLibrary.color(for: $0, saved: tracker.timerTagColors) },
                                  opacity: onBreak ? 0.2 : 0.15)
                    .clipShape(RoundedRectangle(cornerRadius: 16))
            }

            DailyProgressCard(tracker: tracker)

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

            if tracker.isRecording && !onBreak &&
                (!tracker.isWorking || tracker.breakPromptPending || tracker.latestBreak != nil || tracker.notificationNotice != nil) {
                BreakControls(tracker: tracker, showsTakeBreak: !tracker.isWorking).tint(teal)
            }

            if tracker.timedCheckInPending && !onBreak {
                HStack {
                    Text("Check-in available").font(.callout)
                    Spacer()
                    Button("Answer") { tracker.openTimedCheckIn() }.buttonPressFeedback()
                    Button("Skip") { tracker.skipTimedCheckIn() }.buttonPressFeedback()
                }
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
            HStack {
                Button { togglePanel(.groups) } label: {
                    HStack(spacing: 6) {
                        Label("Groups", systemImage: "person.2")
                        if !social.invitations.isEmpty {
                            Circle().fill(.red).frame(width: 7, height: 7)
                                .accessibilityLabel("\(social.invitations.count) pending invitations")
                        }
                    }
                }.buttonPressFeedback().buttonStyle(.plain).foregroundStyle(.secondary)
                    .accessibilityLabel("Show Groups" + (social.invitations.isEmpty ? "" : ", \(social.invitations.count) pending group invitations"))
                    .help("Show people in your selected group")
                    .frame(maxWidth: .infinity, alignment: .leading)
                Button { openWindow(id: "sessions") } label: {
                    Label("Sessions", systemImage: "folder")
                        .frame(width: fullScreen ? 180 : nil, height: fullScreen ? 28 : nil)
                }.buttonPressFeedback().controlSize(.large)
                    .labelStyle(CollectorSessionsLabelStyle(showTitle: fullScreen))
                    .accessibilityLabel("Sessions")
                Button { togglePanel(.analytics) } label: {
                    Label("Analytics", systemImage: "chart.bar.xaxis")
                }.buttonPressFeedback()
                .buttonStyle(.plain)
                .foregroundStyle(fullScreen && selectedPanel == .analytics ? teal : Color.secondary)
                .accessibilityLabel("Show Analytics")
                .help("Analytics")
                .frame(maxWidth: .infinity, alignment: .trailing)
            }
        }
        .padding(30).frame(width: CollectorWindowLayout.compactWidth)
        .background(Color(nsColor: .windowBackgroundColor))
        .onChange(of: tour.isPresented) { _, shown in if shown { sharingPresented = false } }
        .sheet(isPresented: $sharingPresented) { SharingView() }
        .sheet(isPresented: $editingSessionTags) {
            SessionTagEditor(tags: tracker.timerTags, colors: tracker.timerTagColors, library: tagLibrary,
                             confirmationTitle: tracker.isWorking ? "Done" : "Start work") { tags, colors in
                try tracker.saveTimerTags(tags, colors: colors)
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

private struct CollectorSessionsLabelStyle: LabelStyle {
    let showTitle: Bool
    func makeBody(configuration: Configuration) -> some View {
        HStack {
            configuration.icon
            if showTitle { configuration.title }
        }.accessibilityLabel("Sessions")
    }
}
