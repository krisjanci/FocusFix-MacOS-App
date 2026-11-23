import SwiftUI

struct WorkAssignmentHistoryView: View {
    let session: SavedSession
    @Environment(\.dismiss) private var dismiss
    @State private var intervals: [AssignedWorkInterval]?
    @State private var error: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                Text("Project & task time").font(.title2.weight(.semibold))
                Spacer()
                Button("Done") { dismiss() }.keyboardShortcut(.cancelAction)
            }
            Text("Declared work only. Breaks, check-ins, Unknown activity, and missing observations are excluded.")
                .font(.caption).foregroundStyle(.secondary)
            if let error { Text(error).foregroundStyle(.red) }
            else if let intervals {
                if intervals.isEmpty { Text("No observed task work in this recording.").foregroundStyle(.secondary) }
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 12) {
                        ForEach(Array(intervals.enumerated()), id: \.offset) { _, interval in
                            HStack(alignment: .top, spacing: 8) {
                                Circle().fill(Color(tagHex: interval.assignment.projectColor ?? "#64748B"))
                                    .frame(width: 8, height: 8).padding(.top, 5)
                                VStack(alignment: .leading, spacing: 3) {
                                    Text(interval.assignment.summary).font(.callout)
                                    Text("\(time(interval.start - origin))–\(time(interval.end - origin))")
                                        .font(.caption.monospacedDigit()).foregroundStyle(.secondary)
                                }
                                Spacer()
                                Text(RecordingCoverage.time(interval.end - interval.start)).font(.caption.monospacedDigit())
                            }
                            Divider()
                        }
                    }
                }
            } else { ProgressView("Loading work assignments…") }
            Spacer(minLength: 0)
        }.padding(24).frame(width: 480, height: 430)
            .task(id: session.id) {
                do {
                    let result = try await Task.detached { try session.assignmentHistory() }.value
                    guard !Task.isCancelled else { return }
                    intervals = result
                } catch { self.error = "Project/task history could not be read. The original recording was kept." }
            }
    }
    private var origin: Double { session.recordingContract?.elapsedOrigin ?? 0 }
    private func time(_ value: Double) -> String {
        let seconds = Int(max(0, value))
        return String(format: "%d:%02d", seconds / 60, seconds % 60)
    }
}
