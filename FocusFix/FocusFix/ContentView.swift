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
    @AppStorage("appearance") private var appearance = "system"
    @AppStorage("focusfix.research.invitationDeclined") private var invitationDeclined = false
    @State private var sharingPresented = false
    private let teal = Color(red: 0.02, green: 0.60, blue: 0.54)
    // Choose the break appearance only while recording a break or waiting for return.
    private var onBreak: Bool { tracker.isRecording && tracker.breakPhase != .work }

    // Arrange the main UI and route buttons/sheets to the tracker rather than duplicating recording logic.
    var body: some View {
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
                Label(onBreak ? "On break" : tracker.isRecording ? "Recording" : "Idle", systemImage: onBreak ? "leaf.fill" : "circle.fill")
                    .font(.caption.weight(.medium))
                    .foregroundStyle(tracker.isRecording ? teal : Color.secondary)
                    .padding(.horizontal, 12).padding(.vertical, 7)
                    .background(teal.opacity(0.08), in: Capsule())
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
                                Button("Stop & save") { tracker.stop() }
                                Button("Keep going") { tracker.keepGoingAfterPlan() }
                            }
                        }
                    }
                }
            }
            .frame(maxWidth: .infinity).padding(26)
            .background(teal.opacity(onBreak ? 0.10 : 0.04), in: RoundedRectangle(cornerRadius: 16))

            DailyProgressCard(tracker: tracker)
            if !invitationDeclined, account.researchAvailable, account.session != nil,
               account.study?.recruitment_enabled == true, account.study?.complete == true,
               account.researchInterest == nil {
                VStack(alignment: .leading, spacing: 8) {
                    Text("Would you like to contribute to FocusFix research?").font(.callout.weight(.medium))
                    Text("Review the study and request to join. Participation is optional; recordings stay local until you are approved and explicitly enable sharing.")
                        .font(.caption).foregroundStyle(.secondary)
                    HStack {
                        SettingsLink { Text("Review study") }
                        Button("No thanks") { invitationDeclined = true }
                    }
                }
            }

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
                    if tracker.isRecording { tracker.stop() } else { tracker.requestStart() }
                } label: {
                    Label(tracker.isRecording ? "Stop & save" : "Start session",
                          systemImage: tracker.isRecording ? "stop.fill" : "record.circle")
                        .frame(minWidth: 124)
                }.buttonStyle(.bordered).tint(teal).controlSize(.large)
                Button { openWindow(id: "sessions") } label: {
                    Label("Sessions", systemImage: "folder")
                }.controlSize(.large)
                Spacer()
            }
            HStack {
                Button { openWindow(id: "groups") } label: { Label("Groups", systemImage: "person.2") }
                    .buttonStyle(.plain).foregroundStyle(.secondary)
                Menu {
                    Button("Test tracking") { openWindow(id: "tracking") }
                    QuickTourButton()
                } label: { Image(systemName: "ellipsis.circle") }.menuStyle(.borderlessButton).frame(width: 24)
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
