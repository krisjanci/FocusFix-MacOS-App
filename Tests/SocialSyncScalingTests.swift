import Foundation
import Combine

@main @MainActor struct SocialSyncScalingTests {
    static func main() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("compact-sync-\(UUID())")
        defer { try? FileManager.default.removeItem(at: root) }
        let owner = UUID(), other = UUID(), member = UUID(), groupID = UUID()
        let config = AccountConfiguration(url: "https://example.invalid", publicKey: "sb_publishable_fixture")!
        var active = owner, calls: [[String: Any]] = []
        var status = 200, block = false, omitAcknowledgements = false
        var continuation: CheckedContinuation<Void, Never>?
        var remoteName = "Member", remotePhoto: Data? = Data([1, 2, 3]), version = "group-1"
        let today = DailyProgress.key(for: Date(), calendar: DailyProgress.calendar(timeZone: TimeZone(secondsFromGMT: 0)!))
        func progress(_ seconds: Double?) throws -> DailyProgress {
            let days: [String: Any] = seconds.map { [today: ["workSeconds": $0, "completedBreakIDs": []]] } ?? [:]
            return try JSONDecoder().decode(DailyProgress.self, from: JSONSerialization.data(withJSONObject:
                ["version": 1, "days": days, "frozenDays": [], "protectionStart": today, "reconciledThrough": today]))
        }
        let transport: AccountAPI.Transport = { request in
            var data = Data("[]".utf8)
            if request.url!.path.contains("auth/v1/token") {
                data = try JSONEncoder().encode(AccountSession(access_token: "fake", refresh_token: "fake", expires_at: Date().timeIntervalSince1970 + 3600,
                    expires_in: 3600, user: AccountUser(id: active, email: nil)))
            } else if request.url!.path.contains("social_state") {
                let object = try JSONSerialization.jsonObject(with: request.httpBody!) as! [String: Any]
                let payload = object["p_payload"] as! [String: Any]
                calls.append(payload)
                precondition(payload["syncVersion"] as? Int == 2)
                let sent = try JSONDecoder().decode([DeclaredWorkPending].self, from: JSONSerialization.data(withJSONObject: payload["segments"]!))
                let full = payload["progressRevision"] == nil
                let show = payload["includeGroups"] as? Bool == true
                let changed = show && payload["groupVersion"] as? String != version
                var person = SocialMember(id: member, name: remoteName, symbol: "leaf.fill", color: "teal", work: 1, habits: 0, workRank: 1, habitsRank: 1)
                person.photoVersion = remotePhoto == nil ? nil : "photo-1"
                let known = payload["photoVersions"] as? [String: String] ?? [:]
                if known[member.uuidString.lowercased()] != person.photoVersion { person.photo = remotePhoto }
                let groups = active == owner && changed ? [SocialGroup(id: groupID, name: "Group", owner: owner, code: nil, members: [person])] : []
                let state = SocialState(timezone: "UTC", progress: try progress(full ? 3600 : nil), groups: groups, invitations: [],
                    declaredWorkSyncVersion: 1, socialSyncVersion: 2, progressRevision: 1, progressIsDelta: !full,
                    removedDays: [], groupsIncluded: changed, groupVersion: show ? version : nil,
                    acknowledgedWork: omitAcknowledgements ? [] : sent.map { .init(segmentID: $0.segmentID, revision: $0.revision!) },
                    progressMetadataVersion: "metadata-1", progressMetadataIncluded: full)
                if block { await withCheckedContinuation { continuation = $0 } }
                data = try JSONEncoder().encode(state)
                return (data, HTTPURLResponse(url: request.url!, statusCode: status, httpVersion: nil, headerFields: ["Retry-After": "120"])!)
            }
            return (data, HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!)
        }
        let account = AccountController(configuration: config, transport: transport, readCredential: { nil }, writeCredential: { _ in }, defaults: nil)
        await account.authenticate(email: "fixture@example.invalid", password: "fixture", create: false)
        var clock = Date()
        let social = SocialController(account: account, storageDirectory: root, selectionDefaults: nil, now: { clock })
        _ = await social.automaticRefresh()
        precondition(calls.isEmpty, "Hidden idle app polled")
        await social.enable()
        precondition(social.groups.first?.members.first?.photo == remotePhoto)
        let before = calls.count
        _ = await social.automaticRefresh()
        precondition(calls.count == before, "Enabled but idle app polled")
        let segment = UUID(), start = Date().timeIntervalSince1970 - 3600
        func stage(_ seconds: Double) {
            social.stageDeclaredWork(segmentID: segment, days: [today: seconds], capturedOwner: owner, capturedOrigin: config.origin.absoluteString,
                startedAt: start, observedThrough: start + 3600, intervals: [.init(start: start, end: start + seconds)])
        }
        stage(3600)
        clock = clock.addingTimeInterval(3600)
        _ = await social.automaticRefresh()
        precondition(calls.count == before, "Work uploaded before the four-hour deadline")
        // A one-hour launch does not reset the saved deadline or lose the pending work.
        let shortLaunch = SocialController(account: account, storageDirectory: root, selectionDefaults: nil, now: { clock })
        _ = await shortLaunch.automaticRefresh()
        precondition(calls.count == before && shortLaunch.ledger?.declaredWorkPending?.isEmpty == false
            && shortLaunch.groups.first?.members.first?.photo == remotePhoto, "Relaunch lost its cached thumbnail or queue")
        clock = clock.addingTimeInterval(3 * 3600 + 1)
        _ = await shortLaunch.automaticRefresh()
        precondition(calls.count == before + 1 && shortLaunch.ledger?.declaredWorkPending?.isEmpty == true,
            "Relaunch rearmed the deadline instead of uploading overdue work")
        // Continue with the original instance, whose pending revision is idempotent.
        calls.removeLast()
        _ = await social.automaticRefresh()
        precondition(calls.count == before + 1 && calls.last?["includeGroups"] as? Bool == false)
        precondition(social.ledger?.declaredWorkPending?.isEmpty == true, "Atomic acknowledgement failed")
        precondition(social.groups.first?.members.first?.photo == remotePhoto, "Write-only response cleared groups")
        // Unchanged polls must not atomically replace the full local history file.
        let ledgerFile = try FileManager.default.contentsOfDirectory(at: root.appendingPathComponent("FocusFix/Social"), includingPropertiesForKeys: nil).first { $0.pathExtension == "json" }!
        let inode = try FileManager.default.attributesOfItem(atPath: ledgerFile.path)[.systemFileNumber] as? NSNumber
        // Omitted unchanged groups and image bytes reuse the current account's cache.
        _ = await social.refresh()
        let unchangedInode = try FileManager.default.attributesOfItem(atPath: ledgerFile.path)[.systemFileNumber] as? NSNumber
        precondition(inode == unchangedInode, "Unchanged poll rewrote the full local ledger")
        precondition(social.groups.first?.members.first?.photo == remotePhoto)
        remoteName = "Renamed"; version = "group-2"
        _ = await social.refresh()
        precondition(social.groups.first?.members.first?.name == remoteName && social.groups.first?.members.first?.photo == remotePhoto)
        remotePhoto = nil; version = "group-3"
        _ = await social.refresh()
        precondition(social.groups.first?.members.first?.photo == nil, "Revoked image remained visible")
        // A disappearing panel cannot stop another window's polling.
        let panel = UUID(), window = UUID()
        social.setGroupViewVisible(panel, visible: true)
        social.setGroupViewVisible(window, visible: true)
        social.setGroupViewVisible(panel, visible: false)
        let visibleCount = calls.count
        clock = clock.addingTimeInterval(4 * 3600 + 1)
        _ = await social.automaticRefresh()
        precondition(calls.count == visibleCount + 1 && calls.last?["includeGroups"] as? Bool == true)
        social.setGroupViewVisible(window, visible: false)
        _ = await social.automaticRefresh()
        precondition(calls.count == visibleCount + 1)
        // Exact revision matching retains a correction staged during a request.
        stage(1800); block = true
        let request = Task { await social.refresh() }
        while continuation == nil { await Task.yield() }
        stage(900)
        continuation?.resume(); continuation = nil
        _ = await request.value; block = false
        precondition(social.ledger?.declaredWorkPending?[segment.uuidString]?.revision == 3)
        _ = await social.refresh()
        precondition(social.ledger?.declaredWorkPending?.isEmpty == true)
        // The cursor and authoritative base survive relaunch together.
        let restored = SocialController(account: account, storageDirectory: root, selectionDefaults: nil, now: { clock })
        _ = await restored.refresh()
        precondition(calls.last?["groupVersion"] as? String == version, "Relaunch discarded the group cache")
        precondition(calls.last?["progressRevision"] != nil && calls.last?["progressMetadataVersion"] as? String == "metadata-1"
            && restored.ledger?.progress.days[today]?.workSeconds == 3600)
        stage(600); status = 429
        _ = await social.refresh()
        precondition(social.nextAutomaticSyncAt.timeIntervalSince(clock) > 119)
        let failures = calls.count
        _ = await social.automaticRefresh()
        precondition(calls.count == failures && social.ledger?.declaredWorkPending?.isEmpty == false)
        status = 200
        _ = await social.refresh()
        precondition(social.ledger?.declaredWorkPending?.isEmpty == true)
        // More than one upload batch from an offline period drains in the same due cycle.
        for _ in 0..<51 {
            social.stageDeclaredWork(segmentID: UUID(), days: [today: 60], capturedOwner: owner,
                capturedOrigin: config.origin.absoluteString, startedAt: start, observedThrough: start + 3600,
                intervals: [.init(start: start, end: start + 60)])
        }
        clock = clock.addingTimeInterval(4 * 3600 + 1)
        let backlogCalls = calls.count
        _ = await social.automaticRefresh()
        precondition(calls.count == backlogCalls + 2 && social.ledger?.declaredWorkPending?.isEmpty == true,
            "Offline backlog was delayed by another four hours per batch")
        stage(300); omitAcknowledgements = true
        clock = clock.addingTimeInterval(4 * 3600 + 1)
        let missingAckCalls = calls.count
        _ = await social.automaticRefresh()
        precondition(calls.count == missingAckCalls + 1 && social.syncFailed
            && social.nextAutomaticSyncAt > clock && social.ledger?.declaredWorkPending?.isEmpty == false,
            "A successful response without acknowledgements caused a retry loop or dropped work")
        omitAcknowledgements = false
        _ = await social.refresh()
        precondition(social.ledger?.declaredWorkPending?.isEmpty == true)
        await account.signOut()
        precondition(social.groups.isEmpty)
        active = other
        await account.authenticate(email: "other@example.invalid", password: "fixture", create: false)
        await social.enable()
        precondition((calls.last?["photoVersions"] as? [String: String])?.isEmpty == true && social.groups.isEmpty)
        // Reapplying a delta must never apply pending optimistic work twice.
        var ledger = SocialLedger(timezone: "UTC")
        let event = SocialEvent(kind: "work", at: Date(), seconds: 60)
        ledger.append(event)
        let full = SocialState(timezone: "UTC", progress: try progress(3600), groups: [], socialSyncVersion: 2,
            progressRevision: 1, progressIsDelta: false)
        ledger.accept(full, sent: [])
        precondition(ledger.progress.days[today]?.workSeconds == 3660)
        let delta = SocialState(timezone: "UTC", progress: try progress(nil), groups: [], socialSyncVersion: 2,
            progressRevision: 1, progressIsDelta: true)
        ledger.accept(delta, sent: [])
        precondition(ledger.progress.days[today]?.workSeconds == 3660, "Optimistic work double-applied during delta merge")
        let deletion = SocialState(timezone: "UTC", progress: try progress(nil), groups: [], socialSyncVersion: 2,
            progressRevision: 2, progressIsDelta: true, removedDays: [today])
        ledger.accept(deletion, sent: [event.id])
        precondition(ledger.progress.days[today] == nil)
        var metadata = try progress(3600)
        metadata.frozenDays = ["2026-01-02"]
        let base = metadata
        let merged = base.mergingServerDays(try progress(nil), removed: [], includesMetadata: false)
        precondition(merged.frozenDays == base.frozenDays && merged.protectionStart == base.protectionStart)
        print("PASS: compact atomic sync, hidden/visible windows, versioned image cache, exact in-flight revisions, cursor relaunch, Retry-After, account isolation and authoritative deltas")
    }
}
