import Foundation
import CoreGraphics

// Presentation state contains only the selected group ID and metric, never member data.
enum LeaderboardMetric: String, Codable, CaseIterable, Identifiable {
    case work, habits
    var id: String { rawValue }
    var title: String { self == .work ? "Work streak" : "Healthy habits" }
    var scoreTitle: String { self == .work ? "DAY STREAK" : "DAY STREAK" }
    var explanation: String {
        self == .work ? "Current weekday streaks since joining: 60 minutes of declared work earns a day. An unprotected missed weekday resets the streak to 0." : "Current weekday streaks since joining: a completed 1-minute break earns a day. An unprotected missed weekday resets the streak to 0."
    }
    func score(_ member: SocialMember) -> Int { self == .work ? (member.workStreak ?? 0) : (member.habitsStreak ?? 0) }
    func rank(_ member: SocialMember) -> Int { self == .work ? (member.workStreakRank ?? 0) : (member.habitsStreakRank ?? 0) }
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

// Both modes share one panel selection; compact mode presents it as a sheet.
enum CollectorPanel: String, Identifiable {
    case groups, analytics
    var id: String { rawValue }
}

enum CollectorWindowLayout {
    static let compactWidth: CGFloat = 490
    static let minimumPanelWidth: CGFloat = 300

    // Uniform scaling preserves the compact view's proportions. On unusually
    // narrow screens, keep the right panel usable rather than clipping controls.
    static func fullScreenScale(contentHeight: CGFloat, available: CGSize) -> CGFloat {
        min(available.height / max(1, contentHeight),
            max(1, available.width - minimumPanelWidth) / compactWidth)
    }

    static func restoredFrame(_ saved: CGRect, visible: CGRect) -> CGRect {
        let width = min(saved.width, visible.width)
        let height = min(saved.height, visible.height)
        return CGRect(x: min(max(saved.minX, visible.minX), visible.maxX - width),
                      y: min(max(saved.minY, visible.minY), visible.maxY - height),
                      width: width, height: height)
    }
}
