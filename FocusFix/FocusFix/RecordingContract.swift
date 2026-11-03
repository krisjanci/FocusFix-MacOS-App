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
    let mode: RecordingMode
    let elapsedOrigin: Double
    var observedThrough: Double
    var finalized: Bool
    var intervals: [ContextInterval]
    var revisions: [ContextRevision]

    init(recordingID: UUID = UUID(), segmentID: UUID = UUID(), mode: RecordingMode,
         startedAt: Date, initialContext: ActivityContext? = nil, logicalID: UUID = UUID(),
         elapsedOrigin: Double = 0, continuing: ContextInterval? = nil) {
        format = Self.format
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
    enum Invalid: Error { case contract, bounds, overlap, revision, finalized }

    func validate() throws {
        guard format == Self.format, observedThrough.isFinite, elapsedOrigin.isFinite, elapsedOrigin >= 0, observedThrough >= elapsedOrigin else { throw Invalid.contract }
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
    func save(to folder: URL) throws {
        try validate()
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        try encoder.encode(self).write(to: folder.appendingPathComponent("context_intervals.json"), options: .atomic)
    }
    static func load(from folder: URL) throws -> Self {
        let url = folder.appendingPathComponent("context_intervals.json")
        let values = try url.resourceValues(forKeys: [.isRegularFileKey, .isSymbolicLinkKey, .fileSizeKey])
        guard values.isRegularFile == true, values.isSymbolicLink != true,
              (values.fileSize ?? Int.max) <= 16 * 1024 * 1024 else { throw Invalid.contract }
        let decoder = JSONDecoder(); decoder.dateDecodingStrategy = .iso8601
        let result = try decoder.decode(Self.self, from: Data(contentsOf: url))
        try result.validate()
        return result
    }
}
