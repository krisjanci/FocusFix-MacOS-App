import SwiftUI
import AppKit

struct WelcomeView: View {
    @ObservedObject var launch: LaunchCoordinator
    @ObservedObject var account: AccountController
    private let teal = Color(red: 0.02, green: 0.60, blue: 0.54)

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 22) {
                HStack(spacing: 14) {
                    Image(nsImage: NSApplication.shared.applicationIconImage)
                        .resizable().scaledToFit().frame(width: 64, height: 64).accessibilityHidden(true)
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Welcome to FocusFix").font(.system(size: 25, weight: .semibold, design: .rounded))
                        Text("Make room for focus and a good break.").font(.callout).foregroundStyle(.secondary)
                    }
                }
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
                        Text(launch.page == .createAccount ? "Create your account" : "Log in").font(.title2.weight(.semibold))
                        Spacer()
                        Button("Back") { launch.showWelcome() }.disabled(account.busy)
                    }
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
                    Text("Your space to work and recharge.").font(.title2.weight(.medium))
                    Text("Create an account for a personal profile, or get started locally as a guest.")
                        .foregroundStyle(.secondary)
                    VStack(spacing: 12) {
                        Button { launch.showAccount(create: true) } label: {
                            Text("Create account").frame(maxWidth: .infinity)
                        }.buttonStyle(.borderedProminent)
                        Button { launch.showAccount(create: false) } label: {
                            Text("Log in").frame(maxWidth: .infinity)
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
                    Button("Use as guest") { launch.useGuest() }
                        .buttonStyle(.bordered).controlSize(.large)
                        .keyboardShortcut(.cancelAction)
                    Text(launch.isPreview ? "Use as guest returns to your app without changing your saved choice." : "Sessions, breaks and daily progress work without an account. Guest mode is remembered; you can sign in later from Profile.")
                        .font(.caption).foregroundStyle(.secondary)
                }
            }.padding(30).frame(maxWidth: .infinity, alignment: .leading)
        }
        .frame(width: 490, height: 650)
        .background(Color(nsColor: .windowBackgroundColor)).tint(teal)
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
    @Environment(\.openWindow) private var openWindow

    var body: some View {
        Group {
            if launch.page == .app { ContentView(tracker: tracker) }
            else { WelcomeView(launch: launch, account: account) }
        }
        .allowsHitTesting(launchFinished)
        .accessibilityHidden(!launchFinished)
        .overlay {
            if !launchFinished {
                LaunchScreen { finishIntro() }.transition(.identity)
            }
        }
        .onAppear {
            SharingController.shared.resume()
            tracker.refreshNotificationPermission()
            NSApp.windows.forEach { $0.acceptsMouseMovedEvents = true }
            tracker.openMainWindow = {
                openWindow(id: "collector")
                NSApp.activate(ignoringOtherApps: true)
            }
            if launchFinished { launch.begin() }
        }
        .onChange(of: launchFinished) { _, finished in if finished { launch.begin() } }
        .onDisappear { finishIntro() }
        .onChange(of: tracker.sessionCheckInPresented) { _, shown in if shown { finishIntro() } }
        .onChange(of: tracker.recordingNoticePresented) { _, shown in if shown { finishIntro() } }
    }

    private func finishIntro() {
        launchFinished = true
        launch.begin()
    }
}
