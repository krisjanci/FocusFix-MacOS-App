import Foundation

// FF: RECORDING CONTRACT — context is a declaration, independent of intervention phase.
nonisolated enum RecordingMode: String, Codable { case manual, automatic }
nonisolated enum CaptureState: String, Codable {
    case disabled, ready, recording
    case userPaused = "user_paused", idlePaused = "idle_paused", permissionUnavailable = "permission_unavailable"
}
nonisolated enum ActivityContext: String, Codable { case work, nonWork = "non_work", unknown }
nonisolated enum InterventionPhase: String, Codable {
    case normal, explicitBreak = "explicit_break", checkIn = "check_in", awaitingReturn = "awaiting_return"
    init(legacyPhase: String) {
        switch legacyPhase {
        case "check_in": self = .checkIn
        case "resting": self = .explicitBreak
        case "awaiting_return": self = .awaitingReturn
        default: self = .normal // Legacy "work" is a phase, never a context label.
        }
    }
}
nonisolated enum ContextSource: String, Codable {
    case manualStart = "manual_start", automaticDefault = "automatic_default"
    case userAction = "user_action", historyEdit = "history_edit", notification, lifecycle
}
nonisolated struct ContextInterval: Codable, Hashable, Identifiable {
    let id: UUID
    let logicalID: UUID
    var start: Double
    var end: Double?
    let context: ActivityContext
    let source: ContextSource
    let effectiveAtUTC: Date
    let recordedAtUTC: Date
}
nonisolated struct ContextRevision: Codable, Hashable {
    let id: UUID
    let sequence: Int
    let recordedAtUTC: Date
    let previousIntervals: [ContextInterval]
}

nonisolated struct RecordingContract: Codable, Hashable {
    static let schemaVersion = 11
    static let format = "focusfix.recording.v11"
    static let requiredCapabilities = ["context_intervals_v1", "independent_intervention_phase", "monotonic_elapsed_v1"]
    let format: String
    let recordingID: UUID
    let segmentID: UUID
    let scoringTimeZone: String
    let mode: RecordingMode
    let elapsedOrigin: Double
    var observedThrough: Double
    var finalized: Bool
    var intervals: [ContextInterval]
    var revisions: [ContextRevision]

    init(recordingID: UUID = UUID(), segmentID: UUID = UUID(), mode: RecordingMode,
         startedAt: Date, initialContext: ActivityContext? = nil, logicalID: UUID = UUID(),
         elapsedOrigin: Double = 0, continuing: ContextInterval? = nil, scoringTimeZone: String = TimeZone.current.identifier) {
        format = Self.format
        self.scoringTimeZone = scoringTimeZone
        self.recordingID = recordingID; self.segmentID = segmentID; self.mode = mode
        self.elapsedOrigin = elapsedOrigin
        observedThrough = elapsedOrigin; finalized = false; revisions = []
        intervals = [ContextInterval(id: UUID(), logicalID: logicalID, start: elapsedOrigin, end: nil,
            context: initialContext ?? (mode == .manual ? .work : .unknown),
            source: mode == .manual ? .manualStart : .automaticDefault,
            effectiveAtUTC: startedAt, recordedAtUTC: startedAt)]
        if let continuing {
            intervals = [ContextInterval(id: UUID(), logicalID: continuing.logicalID, start: elapsedOrigin, end: nil,
                context: continuing.context, source: continuing.source, effectiveAtUTC: continuing.effectiveAtUTC, recordedAtUTC: continuing.recordedAtUTC)]
        }
    }
    private enum CodingKeys: String, CodingKey {
        case format, recordingID, segmentID, scoringTimeZone, mode, elapsedOrigin, observedThrough, finalized, intervals, revisions
    }
    init(from decoder: Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        format = try values.decode(String.self, forKey: .format)
        recordingID = try values.decode(UUID.self, forKey: .recordingID)
        segmentID = try values.decode(UUID.self, forKey: .segmentID)
        mode = try values.decode(RecordingMode.self, forKey: .mode)
        // Earlier local iterations of the additive v11 format had origin zero and no scoring-zone field.
        elapsedOrigin = try values.decodeIfPresent(Double.self, forKey: .elapsedOrigin) ?? 0
        scoringTimeZone = try values.decodeIfPresent(String.self, forKey: .scoringTimeZone) ?? "UTC"
        observedThrough = try values.decode(Double.self, forKey: .observedThrough)
        finalized = try values.decode(Bool.self, forKey: .finalized)
        intervals = try values.decode([ContextInterval].self, forKey: .intervals)
        revisions = try values.decodeIfPresent([ContextRevision].self, forKey: .revisions) ?? []
    }
    enum Invalid: Error { case contract, bounds, overlap, revision, finalized }

    func validate() throws {
        guard TimeZone(identifier: scoringTimeZone) != nil, format == Self.format, observedThrough.isFinite, elapsedOrigin.isFinite, elapsedOrigin >= 0, observedThrough >= elapsedOrigin else { throw Invalid.contract }
        var previousEnd = elapsedOrigin
        var ids = Set<UUID>()
        for (index, item) in intervals.enumerated() {
            guard ids.insert(item.id).inserted, item.start.isFinite, item.start >= previousEnd,
                  item.start >= 0, item.start <= observedThrough,
                  item.effectiveAtUTC.timeIntervalSince1970.isFinite,
                  item.recordedAtUTC.timeIntervalSince1970.isFinite else { throw Invalid.bounds }
            if let end = item.end {
                guard end.isFinite, end > item.start, end <= observedThrough else { throw Invalid.overlap }
                previousEnd = end
            } else {
                guard !finalized, index == intervals.count - 1 else { throw Invalid.overlap }
                previousEnd = observedThrough
            }
        }
        guard revisions.enumerated().allSatisfy({ $0.element.sequence == $0.offset + 1 }),
              Set(revisions.map(\.id)).count == revisions.count else { throw Invalid.revision }
        for revision in revisions {
            guard revision.recordedAtUTC.timeIntervalSince1970.isFinite else { throw Invalid.revision }
            var prior = self; prior.intervals = revision.previousIntervals; prior.revisions = []
            try prior.validate()
        }
    }
    mutating func observe(through time: Double) throws {
        guard !finalized, time.isFinite, time >= observedThrough else { throw Invalid.bounds }
        observedThrough = time
    }
    mutating func finish(at time: Double) throws {
        try observe(through: time)
        if let index = intervals.indices.last, intervals[index].end == nil {
            if intervals[index].start == time { intervals.removeLast() }
            else { intervals[index].end = time }
        }
        finalized = true
        try validate()
    }
    var currentContext: ActivityContext { intervals.last?.context ?? .unknown }
    var currentWorkPeriodID: UUID? { currentContext == .work ? intervals.last?.logicalID : nil }

    // Forward-only actions never relabel earlier unknown use. Repeating a label is a no-op.
    mutating func changeContext(_ context: ActivityContext, at time: Double, effectiveAt: Date,
                                recordedAt: Date, source: ContextSource, actionID: UUID = UUID()) throws {
        guard !finalized else { throw Invalid.finalized }
        try observe(through: time)
        guard currentContext != context else { return }
        if let index = intervals.indices.last, intervals[index].end == nil {
            if intervals[index].start == time { intervals.removeLast() }
            else { intervals[index].end = time }
        }
        intervals.append(ContextInterval(id: actionID, logicalID: UUID(), start: time, end: nil,
            context: context, source: source, effectiveAtUTC: effectiveAt, recordedAtUTC: recordedAt))
        try validate()
    }

    // A history action is one atomic snapshot, with the prior labels retained as provenance.
    mutating func correctContext(_ context: ActivityContext, start: Double, end: Double,
                                 effectiveAt: Date, recordedAt: Date, actionID: UUID,
                                 expectedRevision: Int) throws {
        if revisions.contains(where: { $0.id == actionID }) { return }
        guard finalized, expectedRevision == revisions.count else { throw Invalid.revision }
        guard start.isFinite, end.isFinite, start >= elapsedOrigin, start < end,
              end <= observedThrough else { throw Invalid.bounds }
        let before = intervals
        var replacement: [ContextInterval] = []
        var covered = 0.0
        for item in before {
            guard let itemEnd = item.end else { throw Invalid.overlap }
            let left = max(start, item.start), right = min(end, itemEnd)
            if right <= left { replacement.append(item); continue }
            covered += right - left
            if item.start < left {
                var fragment = item; fragment.end = left
                replacement.append(fragment)
            }
            replacement.append(ContextInterval(id: UUID(), logicalID: actionID, start: left, end: right,
                context: context, source: .historyEdit, effectiveAtUTC: effectiveAt, recordedAtUTC: recordedAt))
            if right < itemEnd {
                replacement.append(ContextInterval(id: UUID(), logicalID: item.logicalID, start: right, end: itemEnd,
                    context: item.context, source: item.source, effectiveAtUTC: item.effectiveAtUTC, recordedAtUTC: item.recordedAtUTC))
            }
        }
        guard abs(covered - (end - start)) < 0.000001 else { throw Invalid.bounds }
        intervals = replacement
        revisions.append(ContextRevision(id: actionID, sequence: revisions.count + 1,
            recordedAtUTC: recordedAt, previousIntervals: before))
        try validate()
    }
    func save(to folder: URL) throws {
        try validate()
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .secondsSince1970
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        let data = try encoder.encode(self)
        guard data.count <= 16 * 1024 * 1024 else { throw Invalid.contract }
        try data.write(to: folder.appendingPathComponent("context_intervals.json"), options: .atomic)
    }
    static func load(from folder: URL) throws -> Self {
        let url = folder.appendingPathComponent("context_intervals.json")
        let values = try url.resourceValues(forKeys: [.isRegularFileKey, .isSymbolicLinkKey, .fileSizeKey])
        guard values.isRegularFile == true, values.isSymbolicLink != true,
              (values.fileSize ?? Int.max) <= 16 * 1024 * 1024 else { throw Invalid.contract }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .custom { decoder in
            let value = try decoder.singleValueContainer()
            if let seconds = try? value.decode(Double.self), seconds.isFinite { return Date(timeIntervalSince1970: seconds) }
            let string = try value.decode(String.self)
            let formatter = ISO8601DateFormatter()
            formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
            if let date = formatter.date(from: string) { return date }
            formatter.formatOptions = [.withInternetDateTime]
            guard let date = formatter.date(from: string) else { throw Invalid.contract }
            return date
        }
        let result = try decoder.decode(Self.self, from: Data(contentsOf: url))
        try result.validate()
        return result
    }
}
