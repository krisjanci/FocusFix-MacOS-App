import SwiftUI
import AppKit

struct WelcomeView: View {
    @ObservedObject var launch: LaunchCoordinator
    @ObservedObject var account: AccountController
    private let accountTint = Color(red: 0.02, green: 0.60, blue: 0.54)

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                VStack(spacing: 12) {
                    Image(nsImage: NSApplication.shared.applicationIconImage)
                        .resizable().scaledToFit().frame(width: 56, height: 56).accessibilityHidden(true)
                    Text("FocusFix").font(.system(size: 32, weight: .semibold))
                    Text("A little focus. A better balance.").font(.callout).foregroundStyle(.secondary)
                }.frame(maxWidth: .infinity).padding(.bottom, 8)
                if launch.isPreview {
                    Label("Welcome screen preview", systemImage: "eye").font(.headline)
                    Text("Try the forms without changing your account or history. Sign-in, registration, password recovery and saved-account access are disabled. Nothing is sent or saved.")
                        .font(.callout).foregroundStyle(.secondary)
                }
                switch launch.page {
                case .restoring:
                    ProgressView("Restoring your account…")
                    Text("Your saved sign-in uses macOS Keychain. You can continue as a guest while staying local.")
                        .font(.callout).foregroundStyle(.secondary)
                case .createAccount, .login:
                    HStack {
                        Text(launch.page == .createAccount ? "Create your account" : "Log in to FocusFix").font(.title2.weight(.semibold))
                        Spacer()
                        Button("Back") { launch.showWelcome() }.disabled(account.busy)
                    }
                    Text(launch.page == .createAccount ? "Build your routine and stay connected with your groups." : "Welcome back. Your focus journey continues here.")
                        .font(.callout).foregroundStyle(.secondary)
                    AccountSignInForm(account: account, create: launch.page == .createAccount, isPreview: launch.isPreview,
                        onModeChange: { launch.showAccount(create: $0) })
                case .profileSetup:
                    Text("Make it yours").font(.title2.weight(.semibold))
                    Text("Choose a name and avatar for your private account profile, or do this later.")
                        .font(.callout).foregroundStyle(.secondary)
                    if !account.profileLoaded {
                        if account.busy { ProgressView("Loading your profile…") }
                        else { Button("Retry loading profile") { Task { await account.loadProfile() } } }
                    }
                    ProfileEditor(onSaved: { launch.finishProfileSetup() })
                    Button("Skip for now") { launch.finishProfileSetup() }.controlSize(.large)
                case .welcome, .app:
                    Text("Your space to focus.").font(.title2.weight(.semibold))
                    Text("Create an account for a personal profile, or get started locally as a guest.")
                        .foregroundStyle(.secondary)
                    VStack(spacing: 12) {
                        Button { launch.showAccount(create: false) } label: {
                            Text("Log in").frame(maxWidth: .infinity)
                        }.buttonStyle(.borderedProminent)
                        Button { launch.showAccount(create: true) } label: {
                            Text("Create new account").frame(maxWidth: .infinity)
                        }.buttonStyle(.bordered)
                    }.controlSize(.large).disabled(!account.configured && !launch.isPreview)
                    if !launch.isPreview && account.configured && account.remembersSignIn {
                        Button("Retry saved sign-in") { launch.restore() }
                    }
                    if !account.configured && !launch.isPreview {
                        Text("Online accounts aren't connected in this build. Guest mode is ready to use.")
                            .font(.caption).foregroundStyle(.secondary)
                    }
                    if let notice = account.notice {
                        Text(notice).font(.callout).foregroundStyle(.secondary)
                    }
                }
                if launch.page != .profileSetup {
                    Divider()
                    HStack {
                        Button("Continue as guest") { launch.useGuest() }
                        Spacer()
                        QuickTourButton()
                    }
                        .buttonStyle(.bordered).controlSize(.large)
                        .keyboardShortcut(.cancelAction)
                    Text(launch.isPreview ? "Use as guest returns to your app without changing your saved choice." : "Manual recording, breaks and progress work without an account. Automatic recording requires a separate choice in Privacy & Data Sharing. Guest mode is remembered; you can sign in later from Profile.")
                        .font(.caption).foregroundStyle(.secondary)
                }
            }.padding(30).frame(maxWidth: .infinity, alignment: .leading)
                .background(Color(nsColor: .controlBackgroundColor), in: RoundedRectangle(cornerRadius: 22))
                .overlay(RoundedRectangle(cornerRadius: 22).strokeBorder(Color.primary.opacity(0.06)))
                .padding(24)
        }
        .frame(width: 490, height: 700)
        .background(Color(nsColor: .windowBackgroundColor)).tint(accountTint)
    }
}

struct WelcomePreviewView: View {
    @StateObject private var launch = LaunchCoordinator.preview()
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Spacer()
                Button("Close preview") { dismiss() }.padding(12)
            }
            WelcomeView(launch: launch, account: launch.account)
        }
        .onChange(of: launch.page) { _, page in if page == .app { dismiss() } }
    }
}

struct CollectorRootView: View {
    @ObservedObject var tracker: ActivityTracker
    @ObservedObject var launch: LaunchCoordinator
    @ObservedObject var account: AccountController
    @Binding var launchFinished: Bool
    @ObservedObject private var tour = QuickTourController.shared

    // Keep existing modal check-ins intact; the requested tour waits until they close.
    private var canShowTour: Bool {
        !tracker.sessionCheckInPresented && !tracker.recordingNoticePresented &&
        !tracker.breakSetupPresented && !tracker.timedCheckInPresented
    }
    @Environment(\.openWindow) private var openWindow

    var body: some View {
        Group {
            if launch.page == .app { ContentView(tracker: tracker) }
            else { WelcomeView(launch: launch, account: account) }
        }
        .disabled(tour.isPresented && canShowTour)
        .opacity(tour.isPresented && canShowTour ? 0 : 1)
        .allowsHitTesting(launchFinished && !(tour.isPresented && canShowTour))
        .accessibilityHidden(!launchFinished || (tour.isPresented && canShowTour))
        .overlay {
            if tour.isPresented && canShowTour && launchFinished {
                QuickTourView()
            }
        }
        .overlay {
            if !launchFinished {
                LaunchScreen { finishIntro() }.transition(.identity)
            }
        }
        .onAppear {
            tracker.refreshNotificationPermission()
            NSApp.windows.forEach { $0.acceptsMouseMovedEvents = true }
            tracker.openMainWindow = {
                openWindow(id: "collector")
                NSApp.activate(ignoringOtherApps: true)
            }
            if launchFinished { launch.begin() }
        }
        .onChange(of: launchFinished) { _, finished in if finished { launch.begin() } }
        .task(id: "\(launchFinished)-\(launch.page)-\(tour.isPresented)-\(canShowTour)-\(account.needsFirstAccountTour)") {
            if launchFinished && launch.page == .app && !tour.isPresented && canShowTour {
                if account.needsFirstAccountTour {
                    tour.restart()
                    account.didPresentFirstAccountTour()
                } else if RecordingNotice().needsFirstLaunchChoice {
                    tracker.recordingNoticePresented = true
                }
            }
        }
        .onDisappear { finishIntro() }
        .onChange(of: tracker.sessionCheckInPresented) { _, shown in if shown { finishIntro() } }
        .onChange(of: tracker.recordingNoticePresented) { _, shown in if shown { finishIntro() } }
    }

    private func finishIntro() {
        launchFinished = true
        launch.begin()
    }
}
