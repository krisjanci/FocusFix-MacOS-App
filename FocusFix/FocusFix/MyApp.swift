import SwiftUI
import AppKit

final class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { false }
}

@main struct MyApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var delegate
    @StateObject private var tracker = ActivityTracker.shared
    var body: some Scene {
        Window("FocusFix", id: "collector") {
            ContentView(tracker: tracker)
        }.windowResizability(.contentSize)
        MenuBarExtra {
            RecordingMenu(tracker: tracker)
        } label: {
            Label(tracker.isRecording ? "FocusFix recording" : "FocusFix",
                  systemImage: tracker.isRecording ? "record.circle.fill" : "pause.circle")
        }
    }
}

private struct RecordingMenu: View {
    @ObservedObject var tracker: ActivityTracker
    @Environment(\.openWindow) private var openWindow
    var body: some View {
        Text(tracker.isRecording ? "Recording · \(tracker.formattedTime)" : "FocusFix · Idle")
        Button("Show FocusFix") {
            openWindow(id: "collector")
            NSApp.activate(ignoringOtherApps: true)
        }
        Button(tracker.isRecording ? "Stop & save" : "Start session") {
            if tracker.isRecording { tracker.stop() } else {
                tracker.start()
                if !tracker.isRecording {
                    openWindow(id: "collector")
                    NSApp.activate(ignoringOtherApps: true)
                }
            }
        }
        Button("Open session files") { tracker.showFiles() }.disabled(tracker.sessionFolder == nil)
        Divider()
        Button("Quit FocusFix") {
            tracker.stop(reason: "app_quit")
            NSApp.terminate(nil)
        }.keyboardShortcut("q")
    }
}
