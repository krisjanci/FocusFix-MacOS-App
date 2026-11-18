// Compile with BadgeTestSupport.swift and the badge/analytics view sources, never the real tracker.
import SwiftUI
import AppKit

@MainActor private enum PreviewState {
    static let badges = BadgeController(defaults: .standard, deliverNotification: { _ in })
}

private struct PreviewContent: View {
    @ObservedObject var badges = PreviewState.badges
    @State private var expanded = false
    @State private var nextDays = 10
    @State private var dark = CommandLine.arguments.contains("--dark")
    let narrow = CommandLine.arguments.contains("--narrow")
    var body: some View {
        HStack(spacing: 0) {
            VStack(alignment: .leading, spacing: 22) {
                HStack {
                    Text("FocusFix").font(.largeTitle.weight(.semibold))
                    Spacer()
                    Button("Appearance") { dark.toggle() }
                    Button("Earn next") { earnNext() }
                }
                Text("Synthetic preview · no recording or account access").font(.caption).foregroundStyle(.secondary)
                VStack(spacing: 24) {
                    Image(systemName: "scope").font(.system(size: 72, weight: .ultraLight)).foregroundStyle(.teal)
                    Text("Ready to focus").font(.title)
                    Text("00:00").font(.system(size: 48, weight: .light, design: .rounded))
                    Button("Start work") { }.buttonStyle(.borderedProminent).tint(.teal)
                }.frame(maxWidth: .infinity).padding(30).background(.teal.opacity(0.06), in: RoundedRectangle(cornerRadius: 20))
                Spacer()
                HStack {
                    Text("Groups").foregroundStyle(.secondary)
                    Spacer()
                    Button { expanded.toggle() } label: {
                        HStack(spacing: 6) {
                            Label("Analytics", systemImage: "chart.bar.xaxis")
                            if badges.hasUnread { BadgeUnreadDot() }
                        }.anchorPreference(key: AnalyticsBadgeAnchor.self, value: .bounds) { $0 }
                    }.buttonStyle(.plain)
                }
            }.padding(30).frame(width: 490)
            if expanded && !narrow {
                Divider()
                AnalyticsPanel(close: { expanded = false }, badges: badges).frame(width: 359)
            }
        }.frame(height: 620)
        .background(Color(nsColor: .windowBackgroundColor))
        .modifier(BadgeCelebrationHost(badges: badges, reduceMotionOverride: CommandLine.arguments.contains("--reduce-motion"), showsCelebration: !expanded || !narrow))
        .sheet(isPresented: Binding(get: { expanded && narrow }, set: { expanded = $0 })) {
            VStack(spacing: 0) {
                AnalyticsPanel(close: { expanded = false }, anchorsCelebration: true, badges: badges).frame(width: 380, height: 580)
                Button("Earn next badge (synthetic)") { earnNext() }.padding(8)
            }
            .modifier(BadgeCelebrationHost(badges: badges, reduceMotionOverride: CommandLine.arguments.contains("--reduce-motion")))
            .environment(\.colorScheme, dark ? .dark : .light)
        }
        .onAppear { badges.start(tracker: ActivityTracker.shared) }
        .environment(\.colorScheme, dark ? .dark : .light)
    }
    private func earnNext() {
        let calendar = DailyProgress.calendar()
        let today = calendar.date(bySettingHour: 14, minute: 0, second: 0, of: Date())!
        var progress = DailyProgress()
        progress.reconcile(at: calendar.date(byAdding: .day, value: 1 - nextDays, to: today)!, calendar: calendar)
        for offset in (1 - nextDays)...0 {
            progress.addWork(seconds: 3600, endingAt: calendar.date(byAdding: .day, value: offset, to: today)!, calendar: calendar)
        }
        ActivityTracker.shared.dailyProgress = progress
        nextDays = FocusBadge.all.first { $0.days > nextDays }?.days ?? 100
    }
}

@main struct BadgePreview {
    static var window: NSWindow?
    @MainActor static func main() throws {
        let app = NSApplication.shared
        app.setActivationPolicy(.regular)
        let account = AccountController.shared
        let user = UUID(uuidString: "00000000-0000-0000-0000-000000000001")!
        account.session = .init(user: .init(id: user))
        var awards = BadgeAwards()
        let rank = CommandLine.arguments.contains("--legendary") ? 7 : 1
        _ = awards.award(streak: FocusBadge.all[rank].days, joinedKey: "joined|https://badges.invalid|\(user)", historical: true)
        awards.pending = [FocusBadge.all[rank].id]
        // The dedicated preview bundle owns these preferences, separate from FocusFix.
        UserDefaults.standard.set(try JSONEncoder().encode(awards), forKey: "focusfix.badges.v1")
        let view = NSHostingView(rootView: PreviewContent())
        let window = NSWindow(contentRect: NSRect(x: 100, y: 100, width: 490, height: 620),
                              styleMask: [.titled, .closable, .miniaturizable], backing: .buffered, defer: false)
        window.title = "FocusFix Badge Preview"
        window.contentView = view
        window.center(); window.makeKeyAndOrderFront(nil)
        self.window = window
        app.activate(ignoringOtherApps: true)
        app.run()
    }
}
