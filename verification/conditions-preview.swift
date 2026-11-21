// Standalone synthetic preview; never links ActivityTracker or account services.
import SwiftUI
import AppKit

@MainActor private enum PreviewConditions {
    static let root = FileManager.default.temporaryDirectory.appendingPathComponent("conditions-preview-\(UUID())")
    static let library = SessionConditionLibrary(file: root.appendingPathComponent("catalog.json"))
}

private struct ConditionsPreview: View {
    @State private var presented = false
    @State private var conditions: [SessionCondition] = []
    @State private var working = false
    @State private var dark = false
    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            HStack {
                Text("Conditions preview").font(.title2)
                Spacer()
                Button("Appearance") { dark.toggle() }
            }
            Text("Synthetic data · no recording or account access").font(.caption).foregroundStyle(.secondary)
            VStack(spacing: 16) {
                Text("00:00").font(.system(size: 46, weight: .light, design: .rounded))
                ConditionChipLayout {
                    Label("Add tags", systemImage: "plus").font(.caption).padding(6)
                    Label("Work target", systemImage: "scope").font(.caption).padding(6)
                    Button { presented = true } label: { Label("Conditions", systemImage: "plus").font(.caption).padding(6) }
                        .buttonStyle(.plain).background(Color.primary.opacity(0.06), in: Capsule())
                }
                if !conditions.isEmpty {
                    Button { presented = true } label: { SessionConditionSummary(conditions: conditions) }.buttonStyle(.plain)
                }
                Text(working ? "Working · target and elapsed time preserved" : "Ready to start").font(.caption)
            }.padding(26).frame(maxWidth: .infinity).background(.teal.opacity(0.05), in: RoundedRectangle(cornerRadius: 16))
            Button("Reset preview") { conditions = []; working = false }
        }.padding(30).frame(width: 490)
            .preferredColorScheme(dark ? .dark : .light)
            .sheet(isPresented: $presented) {
                SessionConditionEditor(conditions: conditions, library: PreviewConditions.library,
                    confirmationTitle: working ? "Done" : "Start work") { values in
                    conditions = values; working = true
                }.preferredColorScheme(dark ? .dark : .light)
            }
    }
}

private final class ConditionsPreviewDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.regular)
        NSApp.activate(ignoringOtherApps: true)
    }
    func applicationWillTerminate(_ notification: Notification) {
        try? FileManager.default.removeItem(at: PreviewConditions.root)
    }
}

@main struct ConditionsPreviewApp: App {
    @NSApplicationDelegateAdaptor(ConditionsPreviewDelegate.self) private var delegate
    var body: some Scene {
        WindowGroup("FocusFix Conditions Preview") { ConditionsPreview() }
            .windowResizability(.contentSize)
    }
}
