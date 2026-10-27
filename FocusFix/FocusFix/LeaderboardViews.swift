import SwiftUI

// All ranking presentation is value-only and shared by live groups and the practice tour.
struct PodiumMarker: View {
    let place: PodiumPlace
    var allowsAnimation = true
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.controlActiveState) private var activeState
    @Environment(\.scenePhase) private var scenePhase
    @State private var visible = false
    @State private var entered = false
    @State private var glint = false
    private var animating: Bool { allowsAnimation && visible && !reduceMotion && activeState == .key && scenePhase == .active }
    private var color: Color {
        switch place { case .first: return Color(red: 0.74, green: 0.50, blue: 0.10)
        case .second: return Color(red: 0.48, green: 0.55, blue: 0.62)
        case .third: return Color(red: 0.66, green: 0.37, blue: 0.20) }
    }
    var body: some View {
        Group {
            switch place {
            case .first: Image(systemName: "crown.fill")
            case .second: Image(systemName: "medal.fill")
            case .third:
                HStack(spacing: -2) {
                    Image(systemName: "laurel.leading")
                    Circle().frame(width: 4, height: 4)
                    Image(systemName: "laurel.trailing")
                }
            }
        }
        .font(.system(size: 15, weight: .medium)).foregroundStyle(color)
        .frame(width: 24, height: 26)
        .scaleEffect(!reduceMotion && !entered ? 0.85 : glint ? 1.10 : 1)
        .shadow(color: color.opacity(glint ? 0.5 : 0), radius: glint ? 4 : 0)
        .accessibilityHidden(true)
        .onAppear { visible = true }.onDisappear { visible = false }
        .task(id: animating) {
            guard animating else { entered = true; glint = false; return }
            entered = false
            do {
                try await Task.sleep(for: .milliseconds(16))
                guard !Task.isCancelled else { return }
                withAnimation(.spring(duration: 0.35, bounce: 0.15)) { entered = true }
                while !Task.isCancelled {
                    try await Task.sleep(for: .seconds(6))
                    guard !Task.isCancelled else { return }
                    withAnimation(.easeInOut(duration: 0.7)) { glint = true }
                    try await Task.sleep(for: .seconds(0.7))
                    guard !Task.isCancelled else { return }
                    withAnimation(.easeOut(duration: 0.7)) { glint = false }
                }
            } catch { glint = false }
        }
    }
}

struct LeaderboardRow: View {
    let member: SocialMember
    let metric: LeaderboardMetric
    let isCurrentUser: Bool
    var pinned = false
    var allowsAnimation = true
    var body: some View {
        HStack(spacing: 8) {
            HStack(spacing: 2) {
                Text("\(metric.rank(member))").font(.system(.callout, design: .rounded).weight(.semibold)).monospacedDigit()
                if let place = PodiumPlace(rank: metric.rank(member), score: metric.score(member)) {
                    PodiumMarker(place: place, allowsAnimation: !pinned && allowsAnimation)
                }
            }.frame(width: 46, alignment: .leading)
            ProfileAvatar(profile: UserProfile(name: member.name, symbol: member.symbol, color: member.color), size: 29)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 2) {
                Text(member.name).font(.callout.weight(isCurrentUser ? .semibold : .regular)).lineLimit(2)
                if isCurrentUser && !pinned { Text("You").font(.caption2).foregroundStyle(.secondary) }
            }
            Spacer(minLength: 4)
            Text("\(metric.score(member))").font(.system(.title3, design: .rounded).weight(.semibold)).monospacedDigit()
        }
        .padding(.horizontal, 10).padding(.vertical, 11)
        .background(isCurrentUser ? Color.teal.opacity(0.08) : Color.clear, in: RoundedRectangle(cornerRadius: 10))
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Rank \(metric.rank(member)), \(member.name)\(isCurrentUser ? ", you" : ""), \(metric.score(member)) \(metric.title.lowercased()) points")
    }
}

struct LeaderboardTable: View {
    let members: [SocialMember]
    let metric: LeaderboardMetric
    let currentUser: UUID?
    var allowsAnimation = true
    var body: some View {
        let ordered = metric.sorted(members)
        return LazyVStack(spacing: 2) {
            ForEach(ordered) { member in
                LeaderboardRow(member: member, metric: metric, isCurrentUser: member.id == currentUser, allowsAnimation: allowsAnimation)
                if member.id != ordered.last?.id { Divider().padding(.leading, 56) }
            }
        }
    }
}

struct GroupLeaderboard: View {
    let group: SocialGroup
    let metric: LeaderboardMetric
    let currentUser: UUID?
    var allowsAnimation = true
    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                Text("RANK / MEMBER")
                Spacer()
                Text(metric.scoreTitle)
            }.font(.system(size: 9, weight: .semibold)).tracking(1).foregroundStyle(.secondary)
                .padding(.horizontal, 10).padding(.vertical, 10)
            ScrollView {
                LeaderboardTable(members: group.members, metric: metric, currentUser: currentUser, allowsAnimation: allowsAnimation)
                    .padding(.bottom, 8)
            }.accessibilityLabel("\(group.name), \(metric.title) leaderboard, \(group.members.count) people")
            if let person = group.members.first(where: { $0.id == currentUser }) {
                Divider()
                Text("YOUR RANK").font(.system(size: 9, weight: .semibold)).tracking(1).foregroundStyle(.secondary)
                    .padding(.top, 12).padding(.leading, 10)
                LeaderboardRow(member: person, metric: metric, isCurrentUser: true, pinned: true)
                    .padding(.top, 3)
            }
        }
    }
}

struct GroupHeading: View {
    let group: SocialGroup
    var compact = false
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            if !compact { Text("YOUR GROUP").font(.system(size: 9, weight: .semibold)).tracking(1.5).foregroundStyle(.secondary) }
            Text(group.name).font(.system(size: 21, weight: .semibold, design: .rounded)).lineLimit(2)
            HStack(spacing: 6) {
                Label("\(group.members.count) / \(SocialGroup.capacity) people", systemImage: "person.2")
                if group.members.count >= SocialGroup.capacity { Text("· Full") }
                Spacer()
                Text("ALL TIME").font(.system(size: 9, weight: .medium)).tracking(0.7)
            }.font(.caption).foregroundStyle(.secondary)
        }
    }
}
