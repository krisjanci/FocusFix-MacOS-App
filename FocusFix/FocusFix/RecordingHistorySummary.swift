import SwiftUI

// Value-only history components can be inspected without a tracker or local files.
struct EmptyRecordingHistoryView: View {
    var body: some View {
        VStack(spacing: 12) {
            Image(systemName: "clock").font(.title2).foregroundStyle(.secondary).accessibilityHidden(true)
            Text("No recordings yet").font(.headline)
            Text("Opt into automatic recording, or Start work manually. Legacy history stays available.")
                .font(.callout).foregroundStyle(.secondary).multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
        }.padding(16).frame(maxWidth: .infinity).accessibilityElement(children: .combine)
    }
}
struct RecordingHistorySummary: View {
    let contract: RecordingContract?
    let summary: String?
    var error: String? = nil
    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(contract.map { "Recording \($0.recordingID.uuidString.prefix(8)) · segment \($0.segmentID.uuidString.prefix(8))" } ?? "Legacy recording · context unknown")
                .font(.caption).foregroundStyle(.secondary)
            Text(summary ?? error ?? "Loading observed coverage…")
                .font(.caption).fixedSize(horizontal: false, vertical: true)
            if let contract, !contract.intervals.isEmpty {
                DisclosureGroup("Context intervals · \(contract.intervals.count)") {
                    Text("These are labels of intent; observed totals above exclude breaks and gaps.")
                        .font(.caption).foregroundStyle(.secondary)
                    ScrollView {
                        LazyVStack(alignment: .leading, spacing: 6) {
                            ForEach(contract.intervals) { interval in
                                let context = interval.context == .work ? "Declared work" : interval.context == .nonWork ? "Not working" : "Unknown"
                                let lower = String(format: "%.3f", interval.start - contract.elapsedOrigin)
                                let upper = interval.end.map { String(format: "%.3f", $0 - contract.elapsedOrigin) } ?? "ongoing"
                                Text("\(context) · [\(lower), \(upper)) s · \(interval.context == .work ? "work period" : "context") \(interval.logicalID.uuidString.prefix(8))")
                                    .font(.caption).fixedSize(horizontal: false, vertical: true)
                            }
                        }.frame(maxWidth: .infinity, alignment: .leading)
                    }.frame(maxHeight: 140)
                }.font(.caption)
            }
        }.frame(maxWidth: .infinity, alignment: .leading)
    }
}
