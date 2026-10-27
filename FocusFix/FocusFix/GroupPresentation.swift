import Foundation
import CoreGraphics

// Presentation state contains only the selected group ID and metric, never member data.
enum LeaderboardMetric: String, Codable, CaseIterable, Identifiable {
    case work, habits
    var id: String { rawValue }
    var title: String { self == .work ? "Work" : "Healthy habits" }
    var scoreTitle: String { self == .work ? "WORK DAYS" : "HEALTHY DAYS" }
    var explanation: String {
        self == .work ? "60 minutes of work earns one daily point." : "A completed 1-minute break earns one daily point."
    }
    func score(_ member: SocialMember) -> Int { self == .work ? member.work : member.habits }
    func rank(_ member: SocialMember) -> Int { self == .work ? member.workRank : member.habitsRank }
    func sorted(_ members: [SocialMember]) -> [SocialMember] {
        members.sorted {
            if score($0) != score($1) { return score($0) > score($1) }
            if $0.name != $1.name { return $0.name < $1.name }
            return $0.id.uuidString < $1.id.uuidString
        }
    }
}

enum PodiumPlace: Int, CaseIterable {
    case first = 1, second, third
    init?(rank: Int, score: Int) {
        guard score > 0, let value = Self(rawValue: rank) else { return nil }
        self = value
    }
    var title: String {
        switch self { case .first: return "First place"; case .second: return "Second place"; case .third: return "Third place" }
    }
}

struct GroupSelection: Codable, Equatable {
    var groupID: UUID?
    var metric: LeaderboardMetric = .work
    mutating func reconcile(groups: [SocialGroup]) {
        if !groups.contains(where: { $0.id == groupID }) { groupID = groups.first?.id }
    }
}

enum GroupAccessState: Equatable {
    case signedOut, disabled, loading, enabled, offline, unavailable
    static func resolve(signedIn: Bool, enabled: Bool, busy: Bool, loaded: Bool, failed: Bool, notice: Bool) -> Self {
        if !signedIn { return .signedOut }
        if !enabled { return notice ? .unavailable : .disabled }
        if failed { return .offline }
        if busy && !loaded { return .loading }
        return .enabled
    }
}

struct PeopleWindowLayout {
    static let compactWidth: CGFloat = 490
    static let panelWidth: CGFloat = 359
    static let expandedWidth: CGFloat = 850
    static func canExpand(in visibleFrame: CGRect) -> Bool { visibleFrame.width >= expandedWidth }
    static func clampedFrame(current: CGRect, expanded: Bool, visible: CGRect) -> CGRect {
        let width = min(expanded ? expandedWidth : compactWidth, visible.width)
        let height = min(current.height, visible.height)
        return CGRect(x: min(max(current.minX, visible.minX), visible.maxX - width),
                      y: min(max(current.minY, visible.minY), visible.maxY - height), width: width, height: height)
    }
}
