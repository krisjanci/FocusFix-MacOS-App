import Foundation
import CoreGraphics

@main struct GroupPresentationTests {
    static func member(_ name: String, work: Int, habits: Int, workRank: Int, habitsRank: Int) -> SocialMember {
        SocialMember(id: UUID(), name: name, symbol: "leaf.fill", color: "teal", work: work, habits: habits, workRank: workRank, habitsRank: habitsRank)
    }
    static func main() throws {
        let alex = member("Alex", work: 8, habits: 2, workRank: 1, habitsRank: 3)
        let sam = member("Sam", work: 6, habits: 5, workRank: 2, habitsRank: 1)
        let jordan = member("Jordan", work: 6, habits: 4, workRank: 2, habitsRank: 2)
        let zero = member("Zero", work: 0, habits: 0, workRank: 4, habitsRank: 4)
        precondition(LeaderboardMetric.work.sorted([sam,zero,alex,jordan]).map(\.name) == ["Alex","Jordan","Sam","Zero"])
        precondition(LeaderboardMetric.habits.sorted([sam,zero,alex,jordan]).map(\.name) == ["Sam","Jordan","Alex","Zero"])
        precondition(PodiumPlace(rank: 1, score: 0) == nil)
        precondition(PodiumPlace(rank: 4, score: 3) == nil)
        precondition(PodiumPlace(rank: 2, score: 6) == .second)
        precondition(PodiumPlace(rank: 2, score: 6) == PodiumPlace(rank: LeaderboardMetric.work.rank(jordan), score: jordan.work))
        precondition(PodiumPlace(rank: LeaderboardMetric.habits.rank(alex), score: alex.habits) == .third)
        let first = SocialGroup(id: UUID(), name: "First", owner: alex.id, code: nil, members: [alex])
        let second = SocialGroup(id: UUID(), name: "Second", owner: sam.id, code: nil, members: [sam])
        var selected = GroupSelection(groupID: second.id, metric: .habits)
        selected.reconcile(groups: [first,second]); precondition(selected.groupID == second.id)
        selected.reconcile(groups: [first]); precondition(selected.groupID == first.id && selected.metric == .habits)
        selected.reconcile(groups: []); precondition(selected.groupID == nil)
        let restored = try JSONDecoder().decode(GroupSelection.self, from: JSONEncoder().encode(selected))
        precondition(restored == selected && SocialGroup.capacity == 50)
        let states: [(Bool,Bool,Bool,Bool,Bool,Bool,GroupAccessState)] = [
            (false,true,false,true,false,false,.signedOut), (true,false,false,false,false,false,.disabled),
            (true,true,true,false,false,false,.loading), (true,true,false,true,false,false,.enabled),
            (true,true,false,true,true,true,.offline), (true,false,false,false,false,true,.unavailable)]
        for (signedIn,enabled,busy,loaded,failed,notice,expected) in states {
            precondition(GroupAccessState.resolve(signedIn: signedIn, enabled: enabled, busy: busy, loaded: loaded, failed: failed, notice: notice) == expected)
        }
        let screen = CGRect(x: -1440, y: 24, width: 1440, height: 876)
        precondition(PeopleWindowLayout.canExpand(in: screen))
        precondition(!PeopleWindowLayout.canExpand(in: CGRect(x:0,y:0,width:849,height:700)))
        let expanded = PeopleWindowLayout.clampedFrame(current: CGRect(x:-500,y:10,width:490,height:1000),expanded:true,visible:screen)
        precondition(screen.contains(expanded) && expanded.width == 850)
        let collapsed = PeopleWindowLayout.clampedFrame(current: expanded,expanded:false,visible:screen)
        precondition(collapsed.width == 490 && screen.contains(collapsed))
        let narrow = CGRect(x:0,y:0,width:700,height:600)
        precondition(narrow.contains(PeopleWindowLayout.clampedFrame(current:expanded,expanded:true,visible:narrow)))
        print("Shared group selection, access states, tied and zero-score podium rules, and screen-clamped expansion passed")
    }
}
