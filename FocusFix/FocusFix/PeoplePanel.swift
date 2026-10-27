import SwiftUI

struct GroupAccessCard: View {
    let state: GroupAccessState
    let pending: Bool
    let notice: String?
    let signIn: () -> Void
    let enable: () -> Void
    let retry: () -> Void
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            switch state {
            case .signedOut:
                Label("Sign in to join groups", systemImage: "person.crop.circle").font(.headline)
                Text("Your account connects you to private groups. Recording and personal progress still work as a guest.")
                Button("Sign in from Profile", action: signIn).buttonStyle(.borderedProminent)
            case .disabled:
                Label("Enable group progress", systemImage: "person.2").font(.headline)
                Text("Sync work and qualifying-break summaries, scores and streak freezes with your account. Guest history stays on this Mac.")
                Text("Members see your display name, standard avatar and scores. Your email, photo and recordings stay private.")
                Button("Enable group progress", action: enable).buttonStyle(.borderedProminent)
                Text("This is an in-app choice. There is no macOS permission prompt.").font(.caption)
            case .loading:
                HStack { ProgressView().controlSize(.small); Text("Loading your groups…") }
                Text("Progress sync enabled").font(.caption)
            case .enabled:
                Label("Progress sync enabled", systemImage: "checkmark.circle.fill").font(.caption.weight(.medium))
                if pending { Text("Recent progress is waiting to sync.").font(.caption) }
            case .offline:
                Label("Progress sync enabled · Retry needed", systemImage: "arrow.triangle.2.circlepath").font(.callout.weight(.medium))
                Text("Your pending progress is kept on this Mac. Showing the latest groups available this launch.")
                Button("Retry sync", action: retry)
            case .unavailable:
                Label("Group progress unavailable", systemImage: "exclamationmark.circle").font(.headline)
                Text("The saved progress could not be opened. Its existing file has been kept.")
                Button("Retry", action: retry)
            }
            if let notice { Text(notice).font(.caption).textSelection(.enabled) }
        }
        .font(.callout).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
        .tint(.teal)
    }
}

struct GroupSelectionControls: View {
    @ObservedObject var social: SocialController
    var body: some View {
        VStack(spacing: 12) {
            if social.groups.count > 1 {
                Picker("Selected group", selection: Binding(get: { social.selectedGroup?.id }, set: { if let id = $0 { social.selectGroup(id) } })) {
                    ForEach(social.groups) { Text($0.name).tag(Optional($0.id)) }
                }.labelsHidden()
            }
            Picker("Leaderboard", selection: Binding(get: { social.selection.metric }, set: { social.selectMetric($0) })) {
                ForEach(LeaderboardMetric.allCases) { Text($0.title).tag($0) }
            }.pickerStyle(.segmented).labelsHidden()
        }
    }
}

struct PeoplePanel: View {
    @ObservedObject var social: SocialController
    let close: () -> Void
    @Environment(\.openWindow) private var openWindow
    @State private var profilePresented = false
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("PEOPLE").font(.system(size: 10, weight: .semibold)).tracking(1.5).foregroundStyle(.secondary)
                Spacer()
                Button(action: close) { Image(systemName: "sidebar.right") }
                    .buttonStyle(.plain).help("Collapse People").accessibilityLabel("Collapse People")
            }
            if [.signedOut, .disabled, .unavailable].contains(social.accessState) {
                ScrollView { accessCard.padding(.top, 12) }
            } else {
                if let group = social.selectedGroup {
                    GroupHeading(group: group, compact: true)
                    GroupSelectionControls(social: social)
                    Text(social.selection.metric.explanation).font(.caption).foregroundStyle(.secondary)
                    GroupLeaderboard(group: group, metric: social.selection.metric, currentUser: social.userID)
                        .frame(maxHeight: .infinity)
                } else if social.accessState == .loading {
                    accessCard
                    Spacer()
                } else {
                    Label(social.syncFailed ? "Connect to load your groups" : "Your first group", systemImage: "person.2").font(.headline)
                    Text("Create a private group or enter an invite code. Each group has room for 50 people.")
                        .font(.callout).foregroundStyle(.secondary)
                    Button("Create or join a group") { openWindow(id: "groups") }
                    Spacer()
                }
                if social.accessState != .loading { accessCard }
                HStack {
                    Button("Manage groups") { openWindow(id: "groups") }
                    Spacer()
                    Button { Task { await social.retry() } } label: { Image(systemName: "arrow.clockwise") }
                        .accessibilityLabel("Refresh groups").help("Refresh groups").disabled(social.busy)
                }.font(.caption)
            }
        }
        .padding(16).frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(Color(nsColor: .controlBackgroundColor)).tint(.teal)
        .sheet(isPresented: $profilePresented) { SharingView() }
        .task { social.start(); await social.refresh() }
    }
    private var accessCard: some View {
        GroupAccessCard(state: social.accessState, pending: social.pendingConfirmation, notice: social.notice,
            signIn: { profilePresented = true }, enable: { Task { await social.enable() } }, retry: { Task { await social.retry() } })
    }
}
