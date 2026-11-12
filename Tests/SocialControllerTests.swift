import Foundation
import Combine

@main @MainActor struct SocialControllerTests {
    static func main() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("social-test-\(UUID())")
        defer { try? FileManager.default.removeItem(at: root) }
        let owner = UUID(), other = UUID()
        let suite = "focusfix.social.selection.\(UUID())"
        let preferences = UserDefaults(suiteName: suite)!
        defer { preferences.removePersistentDomain(forName: suite) }
        let firstGroup = SocialGroup(id: UUID(), name: "Study circle", owner: owner, code: nil, members: [])
        let secondGroup = SocialGroup(id: UUID(), name: "Weekend crew", owner: owner, code: nil, members: [])
        var remoteGroups: [SocialGroup] = []
        let invitation = GroupInvitation(id: UUID(), groupID: firstGroup.id, groupName: firstGroup.name, inviterName: "Admin")
        var remoteInvitations = [invitation]
        var active = owner
        var offline = false
        var inboxOffline = false
        var block = false
        var continuation: CheckedContinuation<Void, Never>?
        var bodies: [[String: Any]] = []
        var workBodies: [[DeclaredWorkPending]] = []
        var workVersion: Int? = nil
        var workOffline = false
        var blockWork = false
        var workContinuation: CheckedContinuation<Void, Never>?
        let config = AccountConfiguration(url: "https://example.supabase.co", publicKey: "sb_publishable_test")!
        let transport: AccountAPI.Transport = { request in
            var data = Data("{}".utf8)
            if request.url!.path.contains("auth/v1/token") {
                data = try JSONEncoder().encode(AccountSession(access_token: active.uuidString, refresh_token: "fake-refresh",
                    expires_at: Date().timeIntervalSince1970 + 3600, expires_in: 3600,
                    user: AccountUser(id: active, email: nil)))
            } else if request.url!.path.contains("account_profiles") { data = Data("[]".utf8) }
            else if request.url!.path.contains("group_invitations") || request.url!.path.contains("decline_group_invitation") {
                if inboxOffline { throw URLError(.notConnectedToInternet) }
                if request.url!.path.contains("decline_group_invitation") {
                    let payload = try JSONSerialization.jsonObject(with: request.httpBody!) as! [String: String]
                    precondition(payload["p_invitation"] == invitation.id.uuidString)
                    remoteInvitations = []
                }
                data = try JSONEncoder().encode(remoteInvitations)
            }
            else if request.url!.path.contains("sync_declared_work") {
                if workOffline { throw URLError(.notConnectedToInternet) }
                let object = try JSONSerialization.jsonObject(with: request.httpBody!) as! [String: Any]
                precondition(object["p_timezone"] as? String == "UTC")
                let segments = try JSONDecoder().decode([DeclaredWorkPending].self, from: JSONSerialization.data(withJSONObject: object["p_segments"]!))
                workBodies.append(segments)
                if blockWork { await withCheckedContinuation { workContinuation = $0 } }
                data = try JSONEncoder().encode(DeclaredWorkResponse(version: 1, acknowledged: segments.map { .init(segmentID: $0.segmentID, revision: $0.revision!) }))
            }
            else if request.url!.path.contains("social_state") {
                if offline { throw URLError(.notConnectedToInternet) }
                let object = try JSONSerialization.jsonObject(with: request.httpBody!) as! [String: Any]
                bodies.append(object)
                if object["p_action"] as? String == "accept" {
                    let fields = object["p_payload"] as! [String: Any]
                    precondition(fields["invitation"] as? String == invitation.id.uuidString)
                    remoteInvitations = []; remoteGroups = [firstGroup]
                }
                if block { await withCheckedContinuation { continuation = $0 } }
                var progress = DailyProgress()
                progress.reconcile(at: Date(), calendar: DailyProgress.calendar(timeZone: TimeZone(secondsFromGMT: 0)!))
                data = try JSONEncoder().encode(SocialState(timezone: "UTC", progress: progress, groups: remoteGroups, invitations: remoteInvitations, declaredWorkSyncVersion: workVersion))
            }
            return (data, HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!)
        }
        let account = AccountController(configuration: config, transport: transport,
            readCredential: { nil }, writeCredential: { _ in }, defaults: nil)
        let social = SocialController(account: account, storageDirectory: root, selectionDefaults: preferences)
        social.record(kind: "work", seconds: 60)
        precondition(!social.enabled && bodies.isEmpty && social.accessState == .signedOut)
        await account.authenticate(email: "test@example.invalid", password: "test-password", create: false)
        await social.refresh()
        precondition(!social.enabled && bodies.isEmpty) // No implicit opt-in or guest history.
        precondition(social.accessState == .disabled && social.invitations.count == 1)
        await social.respond(to: invitation, accept: false)
        precondition(!social.enabled && social.invitations.isEmpty && bodies.isEmpty)
        remoteInvitations = [invitation]
        await social.refresh()
        precondition(social.invitations.count == 1)
        await social.enable()
        precondition(social.enabled && bodies.count == 1 && social.ledger?.timezone == "UTC")
        precondition(social.accessState == .enabled)
        await social.respond(to: invitation, accept: true)
        precondition(social.invitations.isEmpty && social.groups.first?.id == invitation.groupID)
        remoteGroups = [firstGroup,secondGroup]
        await social.refresh()
        social.selectGroup(secondGroup.id); social.selectMetric(.habits)
        precondition(social.selectedGroup?.id == secondGroup.id && social.selection.metric == .habits)
        // Native pickers may echo their current selection during a view update.
        // Unchanged/invalid selections must not trigger another UI publication.
        var selectionPublications = 0
        let selectionSubscription = social.$selection.dropFirst().sink { _ in selectionPublications += 1 }
        social.selectMetric(.habits)
        social.selectGroup(secondGroup.id)
        social.selectGroup(UUID())
        precondition(selectionPublications == 0)
        social.selectMetric(.work)
        social.selectGroup(firstGroup.id)
        precondition(selectionPublications == 2)
        social.selectMetric(.habits)
        social.selectGroup(secondGroup.id)
        precondition(selectionPublications == 4)
        selectionSubscription.cancel()
        offline = true
        social.record(kind: "work", seconds: 60, at: Date().addingTimeInterval(61))
        await social.refresh()
        precondition(social.ledger?.pending.count == 1 && social.pendingConfirmation && social.accessState == .offline)
        // A fresh process reloads the same durable outbox, scoped to account and origin.
        let restored = SocialController(account: account, storageDirectory: root, selectionDefaults: preferences)
        await restored.refresh()
        precondition(restored.ledger?.pending.count == 1)
        precondition(restored.selection.groupID == secondGroup.id && restored.selection.metric == .habits)
        let submittedID = restored.ledger!.pending[0].id
        offline = false; block = true
        let request = Task { await restored.refresh() }
        while continuation == nil { await Task.yield() }
        restored.record(kind: "work", seconds: 1, at: Date().addingTimeInterval(62))
        precondition(restored.ledger?.pending.count == 2)
        precondition(restored.ledger!.pending[0].id == submittedID)
        precondition(restored.ledger!.pending[0].seconds == 60)
        await account.signOut()
        precondition(restored.groups.isEmpty && restored.invitations.isEmpty && restored.selection == GroupSelection())
        remoteGroups = []
        active = other
        await account.authenticate(email: "other@example.invalid", password: "test-password", create: false)
        restored.record(kind: "work", seconds: 60)
        precondition(!restored.enabled && restored.groups.isEmpty)
        continuation?.resume(); continuation = nil
        _ = await request.value
        precondition(!restored.enabled && restored.groups.isEmpty) // Old response cannot repopulate another account.
        block = false
        await restored.enable()
        let payload = bodies.last!["p_payload"] as! [String: Any]
        precondition((payload["events"] as! [[String: Any]]).isEmpty)
        await account.signOut(); active = owner
        remoteGroups = [firstGroup,secondGroup]
        await account.authenticate(email: "test@example.invalid", password: "test-password", create: false)
        await restored.refresh()
        let ownPayload = bodies.last!["p_payload"] as! [String: Any]
        precondition((ownPayload["events"] as! [[String: Any]]).count == 2)
        precondition(restored.ledger?.pending.isEmpty == true)
        precondition(restored.selection.groupID == secondGroup.id && restored.selection.metric == .habits)
        restored.discardCache(userID: owner, origin: config.origin)
        precondition(!restored.enabled)
        let afterDeletion = SocialController(account: account, storageDirectory: root, selectionDefaults: preferences)
        await afterDeletion.refresh()
        precondition(!afterDeletion.enabled)
        // An inbox outage must not misreport a local storage error or block opt-in.
        inboxOffline = true
        await afterDeletion.refresh()
        precondition(afterDeletion.notice == nil && afterDeletion.invitationNotice != nil)
        precondition(afterDeletion.accessState == .disabled)
        await afterDeletion.enable()
        precondition(afterDeletion.enabled && afterDeletion.invitationNotice == nil)
        inboxOffline = false
        // Version negotiation keeps replacements away from the legacy increment RPC.
        let segment = UUID(), start = Date().timeIntervalSince1970 - 3600
        func stage(_ seconds: Double) {
            afterDeletion.stageDeclaredWork(segmentID: segment, days: seconds == 0 ? [:] : ["2026-11-12": seconds],
                capturedOwner: owner, capturedOrigin: config.origin.absoluteString,
                startedAt: start, observedThrough: start + 3600,
                intervals: seconds == 0 ? [] : [.init(start: start, end: start + seconds)])
        }
        stage(3600)
        await afterDeletion.refresh()
        precondition(workBodies.isEmpty && afterDeletion.declaredWorkSyncHeld)
        workVersion = 1; workOffline = true
        // The user action succeeds once, even if the separate work request fails.
        let edited = await afterDeletion.refresh(action: "edit", fields: ["group": firstGroup.id.uuidString])
        precondition(edited)
        precondition(afterDeletion.ledger?.declaredWorkPending?.count == 1 && afterDeletion.pendingConfirmation)
        workOffline = false; blockWork = true
        let syncTask = Task { await afterDeletion.refresh() }
        while workContinuation == nil { await Task.yield() }
        stage(1800)
        workContinuation?.resume(); workContinuation = nil
        _ = await syncTask.value
        blockWork = false
        precondition(afterDeletion.ledger?.declaredWorkPending?[segment.uuidString]?.revision == 2)
        await afterDeletion.refresh()
        precondition(afterDeletion.ledger?.declaredWorkPending?.isEmpty == true)
        precondition((bodies.last!["p_action"] as? String) == "sync")
        // Correcting already-acknowledged work to zero must still enqueue a replacement.
        stage(0)
        precondition(afterDeletion.ledger?.declaredWorkPending?[segment.uuidString]?.revision == 3)
        await afterDeletion.refresh()
        precondition(afterDeletion.ledger?.declaredWorkPending?.isEmpty == true)
        let count = workBodies.count
        stage(0); await afterDeletion.refresh()
        precondition(workBodies.count == count)
        // A successful inbox response must never clear a corrupt-ledger warning:
        // otherwise Enable could overwrite the unreadable original with a new ledger.
        let identity = "\(config.origin.absoluteString)|\(owner)"
        let fileName = Data(identity.utf8).base64EncodedString().replacingOccurrences(of: "/", with: "_").replacingOccurrences(of: "+", with: "-")
        let ledgerFile = root.appendingPathComponent("FocusFix/Social/\(fileName).json")
        let original = Data("unreadable synthetic ledger".utf8)
        try original.write(to: ledgerFile)
        let corrupt = SocialController(account: account, storageDirectory: root, selectionDefaults: preferences)
        await corrupt.refresh()
        precondition(corrupt.accessState == .unavailable && corrupt.notice != nil)
        precondition(corrupt.invitationNotice == nil)
        await corrupt.enable()
        precondition(!corrupt.enabled)
        let preserved = try Data(contentsOf: ledgerFile)
        precondition(preserved == original)
        print("Social opt-in, durable offline outbox, account isolation, stale responses and retry acknowledgement passed")
    }
}
