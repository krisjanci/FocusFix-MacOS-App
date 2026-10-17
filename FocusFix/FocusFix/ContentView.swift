import SwiftUI
import AppKit

struct ContentView: View {
    @ObservedObject var tracker: ActivityTracker
    @Environment(\.openWindow) private var openWindow
    @AppStorage("appearance") private var appearance = "system"
    private let teal = Color(red: 0.02, green: 0.60, blue: 0.54)

    var body: some View {
        VStack(alignment: .leading, spacing: 26) {
            HStack(spacing: 14) {
                Image(nsImage: NSApplication.shared.applicationIconImage)
                    .resizable().scaledToFit().frame(width: 54, height: 54)
                    .accessibilityHidden(true)
                VStack(alignment: .leading, spacing: 4) {
                    Text("FocusFix").font(.system(size: 25, weight: .semibold, design: .rounded))
                    Text("ACTIVITY COLLECTOR").font(.system(size: 10, weight: .semibold))
                        .tracking(2).foregroundStyle(.secondary)
                }
                Spacer()
                Label(tracker.isRecording ? "Recording" : "Idle", systemImage: "circle.fill")
                    .font(.caption.weight(.medium))
                    .foregroundStyle(tracker.isRecording ? teal : Color.secondary)
                    .padding(.horizontal, 12).padding(.vertical, 7)
                    .background(teal.opacity(0.08), in: Capsule())
            }
            VStack(spacing: 16) {
                Text("SESSION TIME").font(.caption2.weight(.medium)).tracking(2).foregroundStyle(.secondary)
                Text(tracker.formattedTime)
                    .font(.system(size: 46, weight: .light, design: .rounded)).monospacedDigit()
            }
            .frame(maxWidth: .infinity).padding(26)
            .background(teal.opacity(0.06), in: RoundedRectangle(cornerRadius: 18))

            // Only actionable problems belong on the main recording screen.
            if tracker.hasError || tracker.needsPermission {
                Text(tracker.message).font(.callout)
                    .fixedSize(horizontal: false, vertical: true)
                    .foregroundStyle(tracker.hasError ? Color.red : Color.secondary)
            }
            if tracker.needsPermission {
                Button("Allow Accessibility Access") { tracker.requestPermission() }.buttonStyle(.bordered)
            }
            HStack(spacing: 12) {
                Button {
                    if tracker.isRecording { tracker.stop() } else { tracker.start() }
                } label: {
                    Label(tracker.isRecording ? "Stop & save" : "Start session",
                          systemImage: tracker.isRecording ? "stop.fill" : "record.circle")
                        .frame(minWidth: 124)
                }.buttonStyle(.borderedProminent).tint(teal).controlSize(.large)
                Button { openWindow(id: "sessions") } label: {
                    Label("Sessions", systemImage: "folder")
                }.controlSize(.large)
                Spacer()
            }
            HStack {
                Button("Test tracking") { openWindow(id: "tracking") }
                    .buttonStyle(.plain).foregroundStyle(.secondary)
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
        .onAppear { NSApp.windows.forEach { $0.acceptsMouseMovedEvents = true } }
    }
}
