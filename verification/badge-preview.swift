// Compile with BadgeTestSupport.swift and the badge/analytics view sources, never the real tracker.
import SwiftUI
import AppKit

private struct PreviewContent: View {
    @ObservedObject var badges = BadgeController.shared
    @State private var expanded = false
    @State private var dark = CommandLine.arguments.contains("--dark")
    let narrow = CommandLine.arguments.contains("--narrow")
    var body: some View {
        HStack(spacing: 0) {
            VStack(alignment: .leading, spacing: 22) {
                HStack {
                    Text("FocusFix").font(.largeTitle.weight(.semibold))
                    Spacer()
                    Button("Appearance") { dark.toggle() }
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
            }.padding(30).frame(width: narrow ? 380 : 490)
            if expanded {
                Divider()
                AnalyticsPanel { expanded = false }.frame(width: 359)
            }
        }.frame(height: 620)
        .background(Color(nsColor: .windowBackgroundColor))
        .modifier(BadgeCelebrationHost(badges: badges))
        .environment(\.colorScheme, dark ? .dark : .light)
        .environment(\.accessibilityReduceMotion, CommandLine.arguments.contains("--reduce-motion"))
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
