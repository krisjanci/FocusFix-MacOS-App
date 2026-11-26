import Foundation

nonisolated struct CoverageSlice: Equatable {
    let start: Double
    let end: Double
    let phase: InterventionPhase
}
// Exact coverage is independent of rounded movement measurements. Each interval is
// encoded as [start, end, phase], with adjacent equal phases merged across checkpoints.
nonisolated struct ObservedCoverage: Codable {
    static let filename = "observed_coverage.json"
    var version = 1
    var intervals: [Interval] = []
    struct Interval: Codable {
        var start: Double
        var end: Double
        let phase: InterventionPhase
        init(start: Double, end: Double, phase: InterventionPhase) {
            self.start = start; self.end = end; self.phase = phase
        }
        init(from decoder: Decoder) throws {
            var values = try decoder.unkeyedContainer()
            start = try values.decode(Double.self); end = try values.decode(Double.self)
            phase = try values.decode(InterventionPhase.self)
            guard values.isAtEnd else { throw RecordingContract.Invalid.contract }
        }
        func encode(to encoder: Encoder) throws {
            var values = encoder.unkeyedContainer()
            try values.encode(start); try values.encode(end); try values.encode(phase)
        }
    }
    mutating func append(start: Double, end: Double, phase: InterventionPhase) {
        if let last = intervals.last, last.end == start, last.phase == phase {
            intervals[intervals.count - 1].end = end
        } else { intervals.append(Interval(start: start, end: end, phase: phase)) }
    }
    func save(to folder: URL) throws {
        let encoder = JSONEncoder(); encoder.outputFormatting = [.sortedKeys]
        let url = folder.appendingPathComponent(Self.filename)
        try encoder.encode(self).write(to: url, options: .atomic)
        let handle = try FileHandle(forWritingTo: url)
        defer { try? handle.close() }
        try handle.synchronize()
    }
    func slices(origin: Double, through: Double) throws -> [CoverageSlice] {
        guard version == 1 else { throw RecordingContract.Invalid.contract }
        var previous = origin
        return try intervals.compactMap { interval in
            guard interval.start.isFinite, interval.end.isFinite, interval.start >= previous,
                  interval.end > interval.start, interval.phase != .explicitBreak else { throw RecordingContract.Invalid.bounds }
            previous = interval.end
            let lower = max(origin, interval.start), upper = min(through, interval.end)
            return upper > lower ? CoverageSlice(start: lower, end: upper, phase: interval.phase) : nil
        }
    }
}
nonisolated struct RecordingCoverage: Equatable {
    var work: Double = 0
    var nonWork: Double = 0
    var unknown: Double = 0
    var explicitBreak: Double = 0
    var checkInOrAwaitingReturn: Double = 0
    var unavailable: Double = 0
    var workSlices: [CoverageSlice] = []

    init(origin: Double, end: Double, labels: [ContextInterval], observations: [CoverageSlice], breaks: [CoverageSlice]) throws {
        guard origin.isFinite, end.isFinite, origin >= 0, end >= origin else { throw RecordingContract.Invalid.bounds }
        func checked(_ slices: [CoverageSlice]) throws -> [CoverageSlice] {
            var previous = origin
            return try slices.sorted { $0.start < $1.start }.map { slice in
                guard slice.start.isFinite, slice.end.isFinite, slice.start >= previous, slice.end > slice.start,
                      slice.start >= origin, slice.end <= end else { throw RecordingContract.Invalid.overlap }
                previous = slice.end
                return slice
            }
        }
        let observed = try checked(observations)
        let explicit = try checked(breaks)
        for slice in explicit { explicitBreak += slice.end - slice.start }
        for slice in observed {
            let breakOverlap = explicit.reduce(0.0) { $0 + max(0, min($1.end, slice.end) - max($1.start, slice.start)) }
            if breakOverlap > 0 {
                guard slice.phase == .awaitingReturn else { throw RecordingContract.Invalid.overlap }
                checkInOrAwaitingReturn += max(0, slice.end - slice.start - breakOverlap)
                continue
            }
            if slice.phase != .normal {
                checkInOrAwaitingReturn += slice.end - slice.start
                continue
            }
            if labels.isEmpty { unknown += slice.end - slice.start; continue }
            for label in labels {
                let lower = max(slice.start, label.start), upper = min(slice.end, label.end ?? end)
                guard upper > lower else { continue }
                switch label.context {
                case .work:
                    work += upper - lower
                    workSlices.append(CoverageSlice(start: lower, end: upper, phase: .normal))
                case .nonWork: nonWork += upper - lower
                case .unknown: unknown += upper - lower
                }
            }
        }
        unavailable = max(0, end - origin - work - nonWork - unknown - explicitBreak - checkInOrAwaitingReturn)
    }
    var summary: String {
        "Declared work \(Self.time(work)) · Not working \(Self.time(nonWork)) · Unknown \(Self.time(unknown)) · Break \(Self.time(explicitBreak)) · Check-in / awaiting return \(Self.time(checkInOrAwaitingReturn)) · Unavailable \(Self.time(unavailable))"
    }
    static func time(_ seconds: Double) -> String {
        let seconds = Int(max(0, seconds))
        return "\(seconds / 60)m \(seconds % 60)s"
    }
    // CSV quoting includes multiline custom break labels; no private text is returned to UI.
    static func csv(_ text: String) throws -> [[String]] {
        var rows: [[String]] = [], row: [String] = [], value = "", quoted = false
        var index = text.startIndex
        while index < text.endIndex {
            let character = text[index]
            let next = text.index(after: index)
            if character == "\"" {
                if quoted, next < text.endIndex, text[next] == "\"" { value.append("\""); index = text.index(after: next); continue }
                quoted.toggle()
            } else if character == ",", !quoted { row.append(value); value = "" }
            else if character == "\n", !quoted {
                row.append(value.trimmingCharacters(in: .newlines)); rows.append(row); row = []; value = ""
            } else { value.append(character) }
            index = next
        }
        guard !quoted else { throw RecordingContract.Invalid.contract }
        if !value.isEmpty || !row.isEmpty { row.append(value); rows.append(row) }
        return rows
    }
    static func load(session: SavedSession) throws -> Self {
        let contract = session.recordingContract
        let origin = contract?.elapsedOrigin ?? 0
        let end = contract?.observedThrough ?? session.duration ?? 0
        func rows(_ name: String) throws -> [[String]] {
            guard try SessionStorage.contains(name, in: session.folder) else { return [] }
            let data = try SessionStorage.data(name, in: session.folder, limit: 64 * 1024 * 1024)
            guard let text = String(data: data, encoding: .utf8) else { throw RecordingContract.Invalid.contract }
            return try csv(text)
        }
        var observations: [CoverageSlice] = []
        let hasExactCoverage = session.schemaVersion >= 12
        if hasExactCoverage {
            let data = try SessionStorage.data(ObservedCoverage.filename, in: session.folder, limit: 64 * 1024 * 1024)
            let coverage = try JSONDecoder().decode(ObservedCoverage.self, from: data)
            observations = try coverage.slices(origin: origin, through: end)
        }
        let mouse = hasExactCoverage ? [] : try rows("mouse_movement.csv")
        if let header = mouse.first, let startIndex = header.firstIndex(of: "start_seconds"),
           let endIndex = header.firstIndex(of: "end_seconds") {
            let phaseIndex = header.firstIndex(of: "activity_phase")
            for row in mouse.dropFirst() {
                guard row.count == header.count, let start = Double(row[startIndex]), let finish = Double(row[endIndex]),
                      start.isFinite, finish.isFinite, start >= 0, finish > start else { throw RecordingContract.Invalid.bounds }
                let lower = max(origin, start), upper = min(end, finish)
                guard upper > lower else { continue } // Uncheckpointed crash tails are excluded.
                let phase = phaseIndex.map { row[$0] } ?? "work"
                guard ["work", "check_in", "awaiting_return"].contains(phase) else { throw RecordingContract.Invalid.contract }
                observations.append(CoverageSlice(start: lower, end: upper,
                    phase: InterventionPhase(legacyPhase: phase)))
            }
        }
        var breakStarts: [String: Double] = [:], breakEnds: [String: Double] = [:]
        let log = try rows("breaks.csv")
        if let header = log.first, let action = header.firstIndex(of: "action"),
           let id = header.firstIndex(of: "break_id"), let start = header.firstIndex(of: "start_seconds"),
           let finish = header.firstIndex(of: "end_seconds") {
            for row in log.dropFirst() where row.count == header.count {
                if !row[id].isEmpty, let value = Double(row[start]) { breakStarts[row[id]] = value }
                if row[action] == "break_end", let value = Double(row[finish]) { breakEnds[row[id]] = value }
            }
        }
        let breaks = breakStarts.compactMap { id, start -> CoverageSlice? in
            let lower = max(origin, start), upper = min(end, breakEnds[id] ?? end)
            return upper > lower ? CoverageSlice(start: lower, end: upper, phase: .explicitBreak) : nil
        }
        return try Self(origin: origin, end: end, labels: contract?.intervals ?? [], observations: observations, breaks: breaks)
    }
}
