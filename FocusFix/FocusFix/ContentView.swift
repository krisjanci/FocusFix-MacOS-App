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
    @State private var peopleExpanded = false
    @State private var peopleSheet = false
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
                .frame(height: peopleExpanded ? expandedPanelHeight : nil, alignment: .top)
                .background(Color(nsColor: .windowBackgroundColor))
            if peopleExpanded {
                HStack(spacing: 0) {
                    Rectangle().fill(Color.primary.opacity(0.08)).frame(width: 1)
                    PeoplePanel(social: social, close: { peopleExpanded = false })
                        .frame(width: PeopleWindowLayout.panelWidth)
                }
                .frame(height: expandedPanelHeight)
                .transition(.opacity)
            }
        }
        // Keep the minimum width compact so SwiftUI doesn't force the window to
        // its expanded size before AppKit can animate the frame.
        .frame(minWidth: PeopleWindowLayout.compactWidth, maxWidth: .infinity, alignment: .leading)
        .fixedSize(horizontal: false, vertical: true)
        .background(Color(nsColor: .windowBackgroundColor))
        .clipped()
        .animation(reduceMotion ? nil : .easeInOut(duration: PeopleWindowAnimation.duration), value: peopleExpanded)
        .modifier(CollectorWindowResizeLock())
        .onPreferenceChange(CollectorHeightKey.self) { if $0 > 0 { collectorHeight = $0 } }
        .background(PeopleWindowBridge(expanded: peopleExpanded, reduceMotion: reduceMotion, resolved: { collectorWindow = $0 }))
        .sheet(isPresented: $peopleSheet) {
            PeoplePanel(social: social, close: { peopleSheet = false }).frame(width: 380, height: 580)
        }
        .onChange(of: tour.isPresented) { _, shown in
            if shown { peopleExpanded = false; peopleSheet = false }
        }
        .onReceive(NotificationCenter.default.publisher(for: NSWindow.didChangeScreenNotification)) { note in
            guard let window = note.object as? NSWindow, window === collectorWindow,
                  peopleExpanded, let screen = window.screen,
                  !PeopleWindowLayout.canExpand(in: screen.visibleFrame) else { return }
            peopleExpanded = false; peopleSheet = true
        }
    }

    private var expandedPanelHeight: CGFloat {
        let chrome = collectorWindow.map { $0.frame.height - ($0.contentView?.frame.height ?? $0.frame.height) } ?? 28
        let available = (collectorWindow?.screen?.visibleFrame.height ?? 900) - chrome
        return max(collectorHeight, min(620, available))
    }

    private func togglePeople() {
        if peopleExpanded { peopleExpanded = false; return }
        if let screen = collectorWindow?.screen, PeopleWindowLayout.canExpand(in: screen.visibleFrame) {
            peopleExpanded = true
        } else { peopleSheet = true }
    }

    private var collectorContent: some View {
        VStack(alignment: .leading, spacing: 20) {
            HStack(spacing: 14) {
                Button { sharingPresented = true } label: {
                    ProfileAvatar(profile: account.session == nil ? profile.profile : account.profile, size: 30)
                }.buttonStyle(.plain).foregroundStyle(.secondary)
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
                Menu("Context") {
                    Button("Work") { tracker.setContext(.work) }
                    Button("Not working") { tracker.setContext(.nonWork) }
                    Button("Unknown") { tracker.setContext(.unknown) }
                }.disabled(!tracker.isRecording).accessibilityLabel("Change activity context")
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
                    SessionClockFace(time: tracker.formattedTime)
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
                                Button("End work") { tracker.endWork() }
                                Button("Keep going") { tracker.keepGoingAfterPlan() }
                            }
                        }
                    }
                }
                SessionTagButton(tags: tracker.sessionTags,
                    colors: tagLibrary.resolvedColors(for: tracker.sessionTags, saved: tracker.sessionTagColors)) {
                        editingSessionTags = true
                    }.frame(maxWidth: .infinity, alignment: .leading)
            }
            .frame(maxWidth: .infinity).padding(26)
            .background {
                TagTintBackground(colors: tracker.sessionTags.map { tagLibrary.color(for: $0, saved: tracker.sessionTagColors) },
                                  opacity: onBreak ? 0.2 : 0.15)
                    .clipShape(RoundedRectangle(cornerRadius: 16))
            }

            DailyProgressCard(tracker: tracker)

            if tracker.isRecording && !onBreak { BreakControls(tracker: tracker).tint(teal) }

            if tracker.timedCheckInPending && !onBreak {
                HStack {
                    Text("Check-in available").font(.callout)
                    Spacer()
                    Button("Answer") { tracker.openTimedCheckIn() }
                    Button("Skip") { tracker.skipTimedCheckIn() }
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
                    }.disabled(tracker.notificationPermissionBusy)
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
                    Button("Enable Input Monitoring") { tracker.requestPermission() }
                        .buttonStyle(.borderedProminent).tint(teal)
                }.padding(14).frame(maxWidth: .infinity, alignment: .leading)
                    .background(teal.opacity(0.06), in: RoundedRectangle(cornerRadius: 12))
            }
            HStack(spacing: 12) {
                if onBreak {
                    Button("I'm back") { tracker.returnFromBreak() }
                        .buttonStyle(.borderedProminent).tint(teal).controlSize(.large)
                }
                Button {
                    if tracker.isRecording && tracker.userContext == .work { tracker.endWork() } else { tracker.requestStart() }
                } label: {
                    Label(tracker.isRecording && tracker.userContext == .work ? "End work" : "Start work",
                          systemImage: tracker.isRecording && tracker.userContext == .work ? "stop.fill" : "play.fill")
                        .frame(minWidth: 124)
                }.buttonStyle(.borderedProminent).tint(teal).controlSize(.large)
                if !(tracker.isRecording && tracker.userContext == .work) {
                    Button("Plan session…") { tracker.requestPlannedStart() }
                        .controlSize(.large)
                        .help("Choose a work target and tags before starting")
                }
                Button { openWindow(id: "sessions") } label: {
                    Image(systemName: "folder").accessibilityLabel("Sessions")
                }.controlSize(.large)
                Spacer()
            }
            HStack {
                Button(action: togglePeople) {
                    Label(peopleExpanded ? "Hide people" : "Groups", systemImage: "person.2")
                }.buttonStyle(.plain).foregroundStyle(.secondary)
                    .accessibilityLabel(peopleExpanded ? "Collapse People panel" : "Expand group People panel")
                    .help("Show people in your selected group")
                Spacer()
                Picker("Appearance", selection: $appearance) {
                    Label("System", systemImage: "circle.lefthalf.filled").tag("system")
                    Label("Light", systemImage: "sun.max").tag("light")
                    Label("Dark", systemImage: "moon").tag("dark")
                }.labelsHidden().frame(width: 120).help("Appearance")
            }
        }
        .padding(30).frame(width: 490)
        .background(Color(nsColor: .windowBackgroundColor))
        .onChange(of: tour.isPresented) { _, shown in if shown { sharingPresented = false } }
        .sheet(isPresented: $sharingPresented) { SharingView() }
        .sheet(isPresented: $editingSessionTags) {
            SessionTagEditor(tags: tracker.sessionTags, colors: tracker.sessionTagColors, library: tagLibrary) { tags, colors in
                try tracker.updateCurrentTags(tags, colors: colors)
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
