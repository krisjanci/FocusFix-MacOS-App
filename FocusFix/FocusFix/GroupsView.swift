import SwiftUI
import AppKit

struct GroupsView: View {
    @ObservedObject var social = SocialController.shared
    @State private var profilePresented = false
    @State private var sheet: GroupSheet?
    @State private var scoringPresented = false
    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                Text("Groups").font(.title2.weight(.semibold))
                Spacer()
                if social.busy { ProgressView().controlSize(.small).accessibilityLabel("Syncing groups") }
                Button { Task { await social.retry() } } label: { Image(systemName: "arrow.clockwise") }
                    .accessibilityLabel("Refresh groups").help("Refresh groups").disabled(social.busy || social.userID == nil)
            }
            if [.signedOut, .disabled, .unavailable].contains(social.accessState) {
                ScrollView { accessCard.padding(.top, 10) }
            } else {
                if let group = social.selectedGroup {
                    GroupHeading(group: group)
                    GroupSelectionControls(social: social)
                    Text(social.selection.metric.explanation).font(.callout).foregroundStyle(.secondary)
                    GroupLeaderboard(group: group, metric: social.selection.metric, currentUser: social.userID)
                        .frame(minHeight: 180, maxHeight: .infinity)
                } else {
                    if social.accessState == .loading { accessCard }
                    else {
                        Label(social.syncFailed ? "Connect to load your groups" : "Your first group", systemImage: "person.2").font(.headline)
                        Text("Create a private group or enter an invite code. Up to 50 people can build steady habits together.")
                            .font(.callout).foregroundStyle(.secondary)
                    }
                    Spacer()
                }
                if social.accessState != .loading { accessCard }
                Divider()
                HStack {
                    Button("Create or join") { sheet = .add }
                    if let group = social.selectedGroup { Button("Manage group") { sheet = .manage(group.id) } }
                    Spacer()
                    Button { scoringPresented = true } label: { Image(systemName: "info.circle") }
                        .accessibilityLabel("Scoring and streak freeze rules").help("Scoring and streak freeze rules")
                }.disabled(social.busy)
            }
        }
        .padding(24).frame(minWidth: 380, minHeight: 480).tint(.teal)
        .sheet(isPresented: $profilePresented) { SharingView() }
        .sheet(item: $sheet) { value in
            switch value {
            case .add: AddGroupSheet(social: social)
            case .manage(let id): ManageGroupSheet(social: social, groupID: id)
            }
        }
        .popover(isPresented: $scoringPresented) {
            Text("Each leaderboard awards at most one point per day since joining. Weekends can earn points and remain optional for your weekday work streak. Three freezes refill each month, without rollover or consecutive calendar-date use. Freezes add no points or streak days. Late synced work can return an unnecessary freeze. Scoring timezone: \(social.ledger?.timezone ?? ""). Equal scores share a rank; podium symbols celebrate positive scores only.")
                .font(.callout).padding(20).frame(width: 320).fixedSize(horizontal: false, vertical: true)
        }
        .task { social.start(); await social.refresh() }
    }
    private var accessCard: some View {
        GroupAccessCard(state: social.accessState, pending: social.pendingConfirmation, notice: social.notice,
            signIn: { profilePresented = true }, enable: { Task { await social.enable() } }, retry: { Task { await social.retry() } })
    }
}

private enum GroupSheet: Identifiable {
    case add, manage(UUID)
    var id: String { switch self { case .add: return "add"; case .manage(let id): return id.uuidString } }
}

private struct AddGroupSheet: View {
    @ObservedObject var social: SocialController
    @Environment(\.dismiss) private var dismiss
    @State private var name = ""
    @State private var code = ""
    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            Text("Create or join a group").font(.title2.weight(.semibold))
            Text("Current members will see your display name, standard avatar and two scores. Your email, photo, recordings, surveys and research participation stay private. Share codes only with people you want to invite.")
                .font(.callout).foregroundStyle(.secondary)
            Text("Up to 50 people per group, including its creator.").font(.caption).foregroundStyle(.secondary)
            TextField("Group name", text: $name).textFieldStyle(.roundedBorder)
            Button("Create group") {
                Task { if await social.refresh(action: "create", fields: ["name": name]) { dismiss() } }
            }.disabled(name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || name.count > 60 || social.busy)
            Divider()
            TextField("Invite code", text: $code).textFieldStyle(.roundedBorder)
            Button("Join group") {
                Task { if await social.refresh(action: "join", fields: ["code": code]) { dismiss() } }
            }.disabled(code.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || social.busy)
            if let notice = social.notice { Text(notice).font(.caption).foregroundStyle(.secondary) }
            HStack { Spacer(); Button("Done") { dismiss() }.keyboardShortcut(.cancelAction) }
        }.padding(24).frame(width: 420).tint(.teal)
    }
}

private struct ManageGroupSheet: View {
    @ObservedObject var social: SocialController
    let groupID: UUID
    @Environment(\.dismiss) private var dismiss
    @State private var confirmation: GroupConfirmation?
    private var group: SocialGroup? { social.groups.first { $0.id == groupID } }
    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                Text("Manage group").font(.title2.weight(.semibold))
                Spacer(); Button("Done") { dismiss() }.keyboardShortcut(.cancelAction)
            }
            ScrollView {
                VStack(alignment: .leading, spacing: 14) {
                    if let group {
                        GroupHeading(group: group)
                        if group.owner == social.userID {
                            if let code = group.code {
                                Text(code).font(.system(.caption, design: .monospaced)).textSelection(.enabled)
                                Button("Copy invite code") {
                                    NSPasteboard.general.clearContents(); NSPasteboard.general.setString(code, forType: .string)
                                }
                            }
                            if group.members.count >= SocialGroup.capacity { Text("This group is full. Remove a member before someone else can join.").font(.caption).foregroundStyle(.secondary) }
                            Button("Reset invite code") { confirm("Reset invite code?", "Previously shared codes will stop working.", action: "reset", group: group) }
                            Divider()
                            ForEach(group.members.filter { $0.id != social.userID }) { member in
                                HStack {
                                    Text(member.name).lineLimit(2); Spacer()
                                    Button("Remove", role: .destructive) {
                                        confirmation = GroupConfirmation(title: "Remove \(member.name)?", message: "Rejoining starts a new group score.", action: "remove", fields: ["group": group.id.uuidString, "member": member.id.uuidString])
                                    }.accessibilityLabel("Remove \(member.name)")
                                }
                            }
                            Divider()
                            Button("Delete group", role: .destructive) { confirm("Delete this group?", "This removes the group and its scores for everyone.", action: "delete", group: group) }
                        } else {
                            Button("Leave group", role: .destructive) { confirm("Leave this group?", "Your score will be removed. Rejoining starts a new score.", action: "leave", group: group) }
                        }
                    } else { Text("You are no longer a member of this group.").foregroundStyle(.secondary) }
                    if let notice = social.notice { Text(notice).font(.caption).foregroundStyle(.secondary) }
                }.frame(maxWidth: .infinity, alignment: .leading).disabled(social.busy)
            }
        }.padding(24).frame(width: 440, height: 480).tint(.teal)
        .alert(item: $confirmation) { item in
            Alert(title: Text(item.title), message: Text(item.message), primaryButton: .destructive(Text("Confirm")) {
                Task {
                    if await social.refresh(action: item.action, fields: item.fields), item.action == "delete" || item.action == "leave" { dismiss() }
                }
            }, secondaryButton: .cancel())
        }
    }
    private func confirm(_ title: String, _ message: String, action: String, group: SocialGroup) {
        confirmation = GroupConfirmation(title: title, message: message, action: action, fields: ["group": group.id.uuidString])
    }
}

private struct GroupConfirmation: Identifiable {
    let id = UUID()
    let title: String
    let message: String
    let action: String
    let fields: [String: String]
}
