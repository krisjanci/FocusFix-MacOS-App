import SwiftUI
import AppKit

struct ContentView: View {
    @ObservedObject var tracker: ActivityTracker
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
                HStack(spacing: 0) {
                    metric("Individual events", value: tracker.eventCount)
                    Divider().frame(height: 32)
                    metric("Mouse intervals", value: tracker.movementRows)
                }
            }
            .frame(maxWidth: .infinity).padding(26)
            .background(teal.opacity(0.06), in: RoundedRectangle(cornerRadius: 18))

            VStack(alignment: .leading, spacing: 10) {
                Label("Keyboard, clicks, scrolls & app switches", systemImage: "keyboard")
                Label("Mouse movement summarized every second", systemImage: "cursorarrow.motionlines")
                Label("Local files. No typed text or cursor paths saved.", systemImage: "lock.shield")
            }.font(.callout).foregroundStyle(.secondary)
            Text(tracker.message).font(.callout)
                .fixedSize(horizontal: false, vertical: true)
                .foregroundStyle(tracker.hasError ? Color.red : Color.secondary)
                .frame(maxWidth: .infinity, minHeight: 38, alignment: .leading)
                .accessibilityLabel("Status: \(tracker.message)")
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
                Button("Export CSVs") { tracker.exportSession() }
                    .disabled(tracker.isRecording || tracker.sessionFolder == nil).controlSize(.large)
                Spacer()
                Button { tracker.showFiles() } label: { Image(systemName: "folder") }
                    .help("Open local session files").accessibilityLabel("Open session files")
                    .disabled(tracker.sessionFolder == nil)
            }
            Text("No surveys, reminders, or predictions. Control recording from the menu bar when this window is closed.")
                .font(.caption).foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(30).frame(width: 490)
        .background(Color(nsColor: .windowBackgroundColor))
        .onAppear { NSApp.windows.forEach { $0.acceptsMouseMovedEvents = true } }
    }
    private func metric(_ title: String, value: Int) -> some View {
        VStack(spacing: 5) {
            Text(value, format: .number).font(.title3.weight(.semibold)).monospacedDigit()
            Text(title).font(.caption).foregroundStyle(.secondary)
        }.frame(maxWidth: .infinity)
    }
}
