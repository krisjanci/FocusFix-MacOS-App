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
                Button("Sign in from Profile", action: signIn).buttonPressFeedback().buttonStyle(.borderedProminent)
            case .disabled:
                Label("Enable group progress", systemImage: "person.2").font(.headline)
                Text("Sync work and qualifying-break summaries, scores and streak freezes with your account. Guest history stays on this Mac.")
                Text("Members see your display name, standard avatar and scores. You can choose to share a profile photo. Your email and recordings stay private.")
                Button("Enable group progress", action: enable).buttonPressFeedback().buttonStyle(.borderedProminent)
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
                Button("Retry sync", action: retry).buttonPressFeedback()
            case .unavailable:
                Label("Group progress unavailable", systemImage: "exclamationmark.circle").font(.headline)
                Text("The saved progress could not be opened. Its existing file has been kept.")
                Button("Retry", action: retry).buttonPressFeedback()
            }
            if let notice { Text(notice).font(.caption).textSelection(.enabled) }
        }
        .font(.callout).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
        .tint(.teal)
    }
}

struct GroupSelectionControls: View {
    @ObservedObject var social: SocialController
    @Binding var showingChat: Bool
    var body: some View {
        VStack(spacing: 12) {
            if social.groups.count > 1 {
                Picker("Selected group", selection: Binding(get: { social.selectedGroup?.id }, set: { id in
                    guard let id else { return }
                    let userID = social.userID
                    // Native pickers can write their binding during a SwiftUI update.
                    Task { @MainActor in
                        guard social.userID == userID else { return }
                        social.selectGroup(id)
                    }
                })) {
                    ForEach(social.groups) { Text($0.name).tag(Optional($0.id)) }
                }.labelsHidden()
            }
            Picker("Group section", selection: Binding(get: { showingChat ? "chat" : social.selection.metric.rawValue }, set: { section in
                let userID = social.userID
                Task { @MainActor in
                    guard social.userID == userID else { return }
                    showingChat = section == "chat"
                    if let metric = LeaderboardMetric(rawValue: section) { social.selectMetric(metric) }
                }
            })) {
                ForEach(LeaderboardMetric.allCases) { Text($0.title).tag($0.rawValue) }
                Text("Chat").tag("chat")
            }.pickerStyle(.segmented).labelsHidden()
        }
    }
}

struct GroupChatComingSoon: View {
    var body: some View {
        VStack(spacing: 12) {
            Image(systemName: "bubble.left.and.bubble.right").font(.system(size: 28)).foregroundStyle(.teal)
            Text("Group chat").font(.headline)
            Text("Coming soon").font(.callout).foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, minHeight: 180)
        .background(Color.teal.opacity(0.06), in: RoundedRectangle(cornerRadius: 14))
        .accessibilityElement(children: .combine)
    }
}

struct PeoplePanel: View {
    @ObservedObject var social: SocialController
    let close: () -> Void
    @Environment(\.openWindow) private var openWindow
    @State private var profilePresented = false
    @State private var showingChat = false
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("PEOPLE").font(.system(size: 10, weight: .semibold)).tracking(1.5).foregroundStyle(.secondary)
                Spacer()
                Button(action: close) { Image(systemName: "sidebar.right") }.buttonPressFeedback()
                    .buttonStyle(.plain).help("Collapse People").accessibilityLabel("Collapse People")
            }
            ScrollView {
                VStack(alignment: .leading, spacing: 12) {
                    if let notice = social.invitationNotice {
                        Text(notice).font(.caption).foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    if !social.invitations.isEmpty { InvitationInbox(social: social) }
                    if [.signedOut, .disabled, .unavailable].contains(social.accessState) {
                        accessCard.padding(.top, 12)
                    } else {
                        if let group = social.selectedGroup {
                            GroupHeading(group: group, compact: true, metric: social.selection.metric)
                            GroupSelectionControls(social: social, showingChat: $showingChat)
                            if showingChat {
                                GroupChatComingSoon()
                            } else {
                                Text(social.selection.metric.explanation).font(.caption).foregroundStyle(.secondary)
                                GroupLeaderboard(group: group, metric: social.selection.metric, currentUser: social.userID, scrolls: false)
                            }
                        } else if social.accessState == .loading {
                            accessCard
                            Spacer()
                        } else {
                            Label(social.syncFailed ? "Connect to load your groups" : "Your first group", systemImage: "person.2").font(.headline)
                            Text("Create a private group or enter an invite code. Each group has room for 50 people.")
                                .font(.callout).foregroundStyle(.secondary)
                            Button("Create or join a group") { openWindow(id: "groups") }.buttonPressFeedback()
                            Spacer()
                        }
                        if social.accessState != .loading { accessCard }
                        HStack {
                            Button("Manage groups") { openWindow(id: "groups") }.buttonPressFeedback()
                            Spacer()
                            Button { Task { await social.retry() } } label: { Image(systemName: "arrow.clockwise") }.buttonPressFeedback()
                                .accessibilityLabel("Refresh groups").help("Refresh groups").disabled(social.busy)
                        }.font(.caption)
                    }
                }.frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .padding(16).frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(Color(nsColor: .controlBackgroundColor)).tint(.teal)
        .sheet(isPresented: $profilePresented) { SharingView() }
        .onChange(of: social.userID) { _, _ in showingChat = false }
        .background(GroupSyncVisibility().frame(width: 0, height: 0))
        .task { social.start() }
    }
    private var accessCard: some View {
        GroupAccessCard(state: social.accessState, pending: social.pendingConfirmation, notice: social.notice,
            signIn: { profilePresented = true }, enable: { Task { await social.enable() } }, retry: { Task { await social.retry() } })
    }
}
