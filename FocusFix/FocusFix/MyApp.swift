import SwiftUI
import AppKit

final class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationWillFinishLaunching(_ notification: Notification) {
        ActivityTracker.shared.configureNotifications()
    }
    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { false }
}

@main struct MyApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var delegate
    @StateObject private var tracker = ActivityTracker.shared
    @AppStorage("appearance") private var appearance = "system"
    private var colorScheme: ColorScheme? {
        appearance == "dark" ? .dark : appearance == "light" ? .light : nil
    }
    var body: some Scene {
        Window("FocusFix", id: "collector") {
            ContentView(tracker: tracker)
                .preferredColorScheme(colorScheme)
        }.windowResizability(.contentSize)
        Window("Sessions — FocusFix", id: "sessions") {
            SessionLibraryView(tracker: tracker).preferredColorScheme(colorScheme)
        }.defaultSize(width: 760, height: 520)
        Window("Test tracking — FocusFix", id: "tracking") {
            TrackingTestView(tracker: tracker).preferredColorScheme(colorScheme)
        }.windowResizability(.contentSize)
        MenuBarExtra {
            RecordingMenu(tracker: tracker)
        } label: {
            Label(tracker.breakPhase != .work && tracker.isRecording ? "FocusFix on break" : tracker.isRecording ? "FocusFix recording" : "FocusFix",
                  systemImage: tracker.breakPhase != .work && tracker.isRecording ? "leaf.fill" : tracker.isRecording ? "record.circle.fill" : "pause.circle")
        }
    }
}

private struct RecordingMenu: View {
    @ObservedObject var tracker: ActivityTracker
    @Environment(\.openWindow) private var openWindow
    var body: some View {
        Text(tracker.isRecording ? "\(tracker.breakPhase == .work ? "Recording" : "On break") · \(tracker.formattedTime)" : "FocusFix · Idle")
        Button("Show FocusFix") {
            openWindow(id: "collector")
            NSApp.activate(ignoringOtherApps: true)
        }
        Button(tracker.isRecording ? "Stop & save" : "Start session") {
            if tracker.isRecording { tracker.stop() } else {
                tracker.requestStart()
                if !tracker.isRecording {
                    openWindow(id: "collector")
                    NSApp.activate(ignoringOtherApps: true)
                }
            }
        }
        if tracker.isRecording {
            Divider()
            if tracker.breakPhase != .work {
                Button("I'm back") { tracker.returnFromBreak() }
            } else {
                Button(tracker.breakPromptPending ? "Break suggested — take a break" : "Take a break") {
                    tracker.chooseBreak()
                    openWindow(id: "collector")
                    NSApp.activate(ignoringOtherApps: true)
                }
                if tracker.breakPromptPending {
                    Button("Skip — wait 25 min") { tracker.deferBreak(snooze: false) }
                    Button("Snooze 10 min") { tracker.deferBreak(snooze: true) }
                }
            }
        }
        Button("Sessions") {
            openWindow(id: "sessions")
            NSApp.activate(ignoringOtherApps: true)
        }
        Divider()
        Button("Quit FocusFix") {
            tracker.stop(reason: "app_quit")
            NSApp.terminate(nil)
        }.keyboardShortcut("q")
    }
}
