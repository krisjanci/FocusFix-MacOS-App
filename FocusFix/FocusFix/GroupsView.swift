import SwiftUI
import AppKit

struct GroupsView: View {
    @ObservedObject private var social = SocialController.shared
    @ObservedObject private var account = AccountController.shared
    @State private var selected: UUID?
    @State private var habits = false
    @State private var name = ""
    @State private var code = ""
    @State private var profilePresented = false
    @State private var management = false
    @State private var confirmation: GroupConfirmation?
    private var group: SocialGroup? { social.groups.first { $0.id == selected } ?? social.groups.first }
    private let teal = Color(red: 0.02, green: 0.60, blue: 0.54)

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 22) {
                HStack {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Groups").font(.title2.weight(.semibold))
                        Text("Small commitments. Shared progress.").foregroundStyle(.secondary)
                    }
                    Spacer()
                    if social.busy { ProgressView().controlSize(.small).accessibilityLabel("Syncing groups") }
                    Button { Task { await social.refresh() } } label: { Image(systemName: "arrow.clockwise") }
                        .help("Refresh groups").accessibilityLabel("Refresh groups").disabled(social.busy || !social.enabled)
                }
                if account.session == nil {
                    Label("Progress together", systemImage: "person.2").font(.headline)
                    Text("Sign in from Profile to create a private group or join with an invite code. Your personal recording and weekday streak remain available without an account.")
                        .foregroundStyle(.secondary)
                    Button("Open Profile") { profilePresented = true }
                } else if !social.enabled {
                    Text("Private by invitation").font(.headline)
                    privacy
                    Text("Enable account progress to sync your work goal, qualifying breaks and automatic streak freezes across devices. Existing guest history stays on this Mac.")
                        .foregroundStyle(.secondary)
                    Button("Enable group progress") { Task { await social.enable() } }
                        .buttonStyle(.borderedProminent).disabled(social.busy || social.notice != nil)
                } else {
                    if let group {
                        Picker("Group", selection: Binding(get: { self.group?.id ?? group.id }, set: { selected = $0 })) {
                            ForEach(social.groups) { Text($0.name).tag($0.id) }
                        }
                        Picker("Leaderboard", selection: $habits) {
                            Text("Work").tag(false)
                            Text("Healthy habits").tag(true)
                        }.pickerStyle(.segmented)
                        Text(habits ? "One point for a day with a completed break of at least one minute." : "One point for a day with at least 60 minutes of work across sessions.")
                            .font(.callout).foregroundStyle(.secondary)
                        LeaderboardTable(members: group.members, habits: habits, currentUser: social.userID)
                        Text("All time · Since joining · Equal scores share a rank")
                            .font(.caption).foregroundStyle(.secondary)
                        DisclosureGroup("Manage group", isExpanded: $management) {
                            VStack(alignment: .leading, spacing: 12) {
                                if group.owner == social.userID {
                                    if let invite = group.code {
                                        Text(invite).font(.system(.caption, design: .monospaced)).textSelection(.enabled)
                                        Button("Copy invite code") {
                                            NSPasteboard.general.clearContents(); NSPasteboard.general.setString(invite, forType: .string)
                                        }
                                    }
                                    Button("Reset invite code") { confirm("Reset invite code?", "Previously shared codes will stop working.", "reset", group) }
                                    ForEach(group.members.filter { $0.id != social.userID }) { member in
                                        Button("Remove \(member.name)", role: .destructive) {
                                            confirmation = GroupConfirmation(title: "Remove \(member.name)?", message: "Their group score will be removed. Rejoining starts a new score.", action: "remove", fields: ["group": group.id.uuidString, "member": member.id.uuidString])
                                        }
                                    }
                                    Button("Delete group", role: .destructive) { confirm("Delete this group?", "This removes the group and its scores for everyone.", "delete", group) }
                                } else {
                                    Button("Leave group", role: .destructive) { confirm("Leave this group?", "Your score will be removed. Rejoining starts a new score.", "leave", group) }
                                }
                            }.padding(.top, 10)
                        }.disabled(social.busy)
                    } else {
                        Label("Your first group", systemImage: "person.2").font(.headline)
                        Text("Invite a few people and build steady habits together.").foregroundStyle(.secondary)
                    }
                    Divider()
                    DisclosureGroup(social.groups.isEmpty ? "Create or join a group" : "Add a group") {
                        VStack(alignment: .leading, spacing: 12) {
                            privacy
                            HStack {
                                TextField("Group name", text: $name).textFieldStyle(.roundedBorder)
                                Button("Create") { Task { if await social.refresh(action: "create", fields: ["name": name]) { name = "" } } }
                                    .disabled(name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || name.count > 60)
                            }
                            HStack {
                                TextField("Invite code", text: $code).textFieldStyle(.roundedBorder)
                                Button("Join") { Task { if await social.refresh(action: "join", fields: ["code": code]) { code = "" } } }
                                    .disabled(code.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                            }
                        }.padding(.top, 10)
                    }
                    .disabled(social.busy)
                    DisclosureGroup("Scoring & streak freezes") {
                        Text("Each leaderboard awards at most one point per day. Only work and breaks after joining count. Weekends can earn points, but are optional for your work streak. Three freezes refill each month, without rollover. A freeze automatically protects an established streak after a missed weekday; it adds no day or points and cannot cover consecutive calendar dates. Late synced work can replace a freeze and return its token. Dates use your account’s scoring timezone: \(social.ledger?.timezone ?? "").")
                            .font(.callout).foregroundStyle(.secondary).padding(.top, 8)
                    }
                    if social.pendingConfirmation {
                        Label("Offline changes or streak decisions are pending sync.", systemImage: "clock")
                            .font(.caption).foregroundStyle(.secondary)
                    }
                }
                if let notice = social.notice {
                    Text(notice).font(.callout).foregroundStyle(.secondary).textSelection(.enabled)
                    Button("Retry") { Task { await social.refresh() } }.disabled(social.busy)
                }
            }.padding(24).frame(maxWidth: 760, alignment: .leading).frame(maxWidth: .infinity)
        }
        .frame(minWidth: 380, minHeight: 420).tint(teal)
        .sheet(isPresented: $profilePresented) { SharingView() }
        .task { social.start(); await social.refresh() }
        .alert(item: $confirmation) { item in
            Alert(title: Text(item.title), message: Text(item.message), primaryButton: .destructive(Text("Confirm")) {
                Task { await social.refresh(action: item.action, fields: item.fields) }
            }, secondaryButton: .cancel())
        }
    }

    private var privacy: some View {
        Text("Creating or joining shares your display name, standard avatar, and two scores with current group members. Your email, photo, recordings, surveys, and research participation stay private. Share invite codes only with people you want in the group.")
            .font(.callout).foregroundStyle(.secondary)
    }
    private func confirm(_ title: String, _ message: String, _ action: String, _ group: SocialGroup) {
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

// Value-only rows also used by isolated visual verification; no account or network dependencies.
struct LeaderboardTable: View {
    let members: [SocialMember]
    let habits: Bool
    let currentUser: UUID?
    private var sorted: [SocialMember] {
        members.sorted {
            let a = habits ? $0.habits : $0.work, b = habits ? $1.habits : $1.work
            if a != b { return a > b }
            if $0.name != $1.name { return $0.name < $1.name }
            return $0.id.uuidString < $1.id.uuidString
        }
    }
    var body: some View {
        VStack(spacing: 4) {
            ForEach(sorted) { member in
                HStack(spacing: 12) {
                    Text("\(habits ? member.habitsRank : member.workRank)").monospacedDigit().frame(width: 26)
                    ProfileAvatar(profile: UserProfile(name: member.name, symbol: member.symbol, color: member.color), size: 30)
                    Text(member.name).lineLimit(2)
                    if member.id == currentUser { Text("You").font(.caption).foregroundStyle(.secondary) }
                    Spacer()
                    Text("\(habits ? member.habits : member.work)").monospacedDigit().fontWeight(.medium)
                }
                .padding(12)
                .background(member.id == currentUser ? Color.teal.opacity(0.08) : Color.clear, in: RoundedRectangle(cornerRadius: 10))
                .accessibilityElement(children: .combine)
            }
        }
    }
}
