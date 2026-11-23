// MARK: - FF: SESSIONS
// Shows the local session library and the separate Test tracking window.

import SwiftUI
import AppKit

struct SessionLibraryView: View {
    @ObservedObject var tracker: ActivityTracker
    @State private var selection = Set<SavedSession.ID>()
    @State private var expandedDays = Set<String>()
    @State private var pendingDeletion: [SavedSession] = []
    @State private var confirmDeletion = false
    @State private var notice: String?
    @State private var exportingAll = false
    @State private var tagging: SavedSession?
    @State private var conditioning: SavedSession?
    @State private var assignmentHistory: SavedSession?
    @State private var coverage: RecordingCoverage?
    @State private var coverageError: String?
    @ObservedObject var tagLibrary = SessionTagLibrary.shared

    // Find the saved session matching the current list selection.
    private var selectedSessions: [SavedSession] { tracker.sessions.filter { selection.contains($0.id) } }
    private var selected: SavedSession? { selectedSessions.count == 1 ? selectedSessions.first : nil }
    private var canActOnSelection: Bool {
        !exportingAll && !selectedSessions.isEmpty && !selectedSessions.contains(where: tracker.isActive)
    }
    private let teal = Color(red: 0.02, green: 0.60, blue: 0.54)

    // List local saved sessions with selection and export/delete controls.
    var body: some View {
        VStack(spacing: 0) {
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Your recordings").font(.title2.weight(.semibold))
                    Text("Files are recording segments, not work periods. Manual and automatic recordings are saved on this Mac, including short ones. Only declared work with observed coverage counts toward work progress.").font(.callout).foregroundStyle(.secondary)
                }
                Spacer()
                Text("\(tracker.sessions.count)").font(.title2.monospacedDigit()).foregroundStyle(teal)
            }.padding(24)
            Divider()
            if let notice = tracker.libraryNotice { Text(notice).font(.caption).foregroundStyle(.secondary).padding(.horizontal, 20) }
            if let error = tracker.libraryError {
                ContentUnavailableView("Couldn't load sessions", systemImage: "exclamationmark.triangle",
                    description: Text(error))
            } else if tracker.sessions.isEmpty {
                EmptyRecordingHistoryView()
            } else {
                HStack {
                    Text("\(selectedSessions.count) selected").monospacedDigit()
                    Button("Select All") { selection = Set(tracker.sessions.map(\.id)); expandedDays.formUnion(SessionDay.groups(tracker.sessions).map(\.id)) }.buttonPressFeedback()
                        .keyboardShortcut("a", modifiers: .command)
                    Button("Deselect All") { selection.removeAll() }.buttonPressFeedback().disabled(selection.isEmpty)
                    Spacer()
                    Text("⌘-click to add · ⇧-click for a range")
                        .font(.caption).foregroundStyle(.secondary)
                }.padding(.horizontal, 20).padding(.vertical, 8)
                List(selection: $selection) {
                    ForEach(SessionDay.groups(tracker.sessions)) { day in
                        if day.sessions.count > 1 {
                            DisclosureGroup(isExpanded: Binding(
                                get: { expandedDays.contains(day.id) },
                                set: { if $0 { expandedDays.insert(day.id) } else { expandedDays.remove(day.id) } }
                            )) {
                                ForEach(day.sessions) { session in sessionRow(session).tag(session.id) }
                            } label: {
                                Label("\(day.date.formatted(date: .abbreviated, time: .omitted)) · \(day.sessions.count) recordings", systemImage: "folder")
                                    .font(.headline).padding(.vertical, 8)
                            }
                        } else if let session = day.sessions.first {
                            sessionRow(session).tag(session.id)
                        }
                    }
                }
                .listStyle(.inset)
                .onKeyPress(.return) {
                    guard let selected, !exportingAll else { return .ignored }
                    tagging = selected
                    return .handled
                }
            }
            if let selected {
                RecordingHistorySummary(contract: selected.recordingContract, summary: coverage?.summary,
                    error: coverageError).padding(.horizontal, 20).padding(.vertical, 8)
            }
            Divider()
            HStack {
                Button { tracker.refreshSessions() } label: { Image(systemName: "arrow.clockwise") }.buttonPressFeedback()
                    .help("Refresh sessions").accessibilityLabel("Refresh sessions")
                Button("Show in Finder") {
                    NSWorkspace.shared.activateFileViewerSelecting(selectedSessions.map(\.folder))
                }.buttonPressFeedback().disabled(selectedSessions.isEmpty)
                Spacer()
                Button(selectedSessions.count > 1 ? "Delete Selected…" : "Delete…", role: .destructive) {
                    pendingDeletion = selectedSessions
                    confirmDeletion = true
                }.buttonPressFeedback().disabled(!canActOnSelection)
                Button(exportingAll ? "Exporting…" : "Export All…") { exportAll() }.buttonPressFeedback()
                    .disabled(exportingAll || tracker.libraryError != nil || !tracker.sessions.contains { !tracker.isActive($0) })
                    .help("Export all saved sessions into one folder. The current recording is skipped.")
                Button(selectedSessions.count > 1 ? "Export Selected…" : "Export…") { exportSelected() }.buttonPressFeedback()
                    .buttonStyle(.borderedProminent).tint(teal)
                    .disabled(!canActOnSelection)
            }.padding(18)
        }
        .frame(minWidth: 800, minHeight: 400)
        .background(Color(nsColor: .windowBackgroundColor))
        .onAppear { tracker.refreshSessions() }
        .onChange(of: tracker.sessions) { _, sessions in
            selection.formIntersection(Set(sessions.map(\.id)))
        }
        .task(id: selected) {
            coverage = nil; coverageError = nil
            guard let selected else { return }
            do {
                let result = try await Task.detached { try RecordingCoverage.load(session: selected) }.value
                guard !Task.isCancelled else { return }
                coverage = result
            } catch { coverageError = "Coverage unavailable; missing observations are not zero activity." }
        }
        .sheet(item: $assignmentHistory) { session in WorkAssignmentHistoryView(session: session) }
        .sheet(item: $conditioning) { session in
            SessionConditionEditor(conditions: session.conditions) { conditions in
                try tracker.updateConditions(conditions, for: session)
            }
        }
        .sheet(item: $tagging) { session in
            SessionTagEditor(tags: session.tags, colors: session.tagColors, library: tagLibrary) { tags, colors in
                try tracker.updateTags(tags, colors: colors, for: session)
            }
        }
        .confirmationDialog("Move \(pendingDeletion.count) selected session\(pendingDeletion.count == 1 ? "" : "s") to Trash?",
                            isPresented: $confirmDeletion, titleVisibility: .visible) {
            Button("Move to Trash", role: .destructive) { deleteSelected() }
            Button("Cancel", role: .cancel) { pendingDeletion = [] }
        } message: {
            Text("The selected local recordings will be moved to Trash. Exported copies and backups stay unchanged.")
            Text("Deleting local sessions does not delete recordings already shared with the developer. Use Settings → Privacy & Data Sharing to request deletion of shared data.")
        }
        .alert("FocusFix", isPresented: Binding(get: { notice != nil }, set: { if !$0 { notice = nil } })) {
            Button("OK") { notice = nil }
        } message: { Text(notice ?? "") }
    }
    private func sessionRow(_ session: SavedSession) -> some View {
        HStack(spacing: 14) {
            Image(systemName: tracker.isActive(session) ? "record.circle" : "doc.text")
                .font(.title2).foregroundStyle(teal)
            VStack(alignment: .leading, spacing: 5) {
                Text(session.startedAt.formatted(date: .abbreviated, time: .standard))
                    .font(.headline)
                Text(session.endedAt.map { "Ended \($0.formatted(date: .abbreviated, time: .standard))" }
                    ?? (tracker.isActive(session) ? (tracker.breakPhase == .work ? "Recording now" : "On break") : "Unfinished session"))
                    .font(.caption).foregroundStyle(.secondary)
                if FileManager.default.fileExists(atPath: session.folder.appendingPathComponent(WorkAssignmentJournal.filename).path) {
                    Button { assignmentHistory = session } label: {
                        Label("Project & task time", systemImage: "doc.text").font(.caption)
                    }.buttonStyle(.plain)
                }
                if !session.tags.isEmpty {
                SessionTagButton(tags: session.tags,
                    colors: tagLibrary.resolvedColors(for: session.tags, saved: session.tagColors)) {
                        selection = [session.id]; tagging = session
                    }.disabled(exportingAll)
                }
                Button {
                    selection = [session.id]; conditioning = session
                } label: {
                    if session.conditions.isEmpty { Label("Conditions", systemImage: "plus").font(.caption) }
                    else { SessionConditionSummary(conditions: session.conditions) }
                }.buttonStyle(.plain).buttonPressFeedback().disabled(exportingAll)
                    .accessibilityLabel(session.conditions.isEmpty ? "Add Conditions" : "Edit session conditions")
            }
            Spacer()
            VStack(alignment: .trailing, spacing: 5) {
                Text(durationLabel(session)).monospacedDigit()
                Text(statusLabel(session)).font(.caption).foregroundStyle(.secondary)
            }
        }.accessibilityElement(children: .contain)
            .padding(.vertical, 10).padding(.horizontal, 8)
            .background {
                if !session.tags.isEmpty {
                    TagTintBackground(colors: session.tags.map { tagLibrary.color(for: $0, saved: session.tagColors) }, opacity: 0.18)
                        .clipShape(RoundedRectangle(cornerRadius: 10))
                }
            }
            .overlay {
                RoundedRectangle(cornerRadius: 10)
                    .stroke(selection.contains(session.id) ? teal : Color.clear, lineWidth: 1.5)
            }
            .contentShape(RoundedRectangle(cornerRadius: 10))
            .id(session.id)
    }

    // Show live duration for the active session and saved duration for completed sessions.
    private func durationLabel(_ session: SavedSession) -> String {
        guard let seconds = tracker.isActive(session) ? tracker.elapsed : session.duration else { return "—" }
        let value = Int(seconds)
        return String(format: "%02d:%02d:%02d", value / 3600, value / 60 % 60, value % 60)
    }
    // Translate a saved stop reason into a readable library label.
    private func statusLabel(_ session: SavedSession) -> String {
        if tracker.isActive(session) { return tracker.breakPhase == .work ? "Recording" : "On break" }
        if session.endedAt == nil { return "Incomplete" }
        switch session.status {
        case "user_stop": return "Saved"
        case "app_quit": return "Saved on quit"
        case "sleep_or_inactive_session": return "Stopped on sleep / inactivity"
        case "permission_lost": return "Access interrupted"
        case "recording_error", "monitor_unavailable", "input_monitor_interrupted": return "Check recording"
        default: return "Saved"
        }
    }
    private func deleteSelected() {
        let sessions = pendingDeletion
        pendingDeletion = []
        do {
            let result = try tracker.deleteSessions(sessions)
            selection.subtract(result.deleted.map(\.id))
            if !result.failures.isEmpty {
                notice = "Moved \(result.deleted.count) of \(sessions.count) sessions to Trash. Could not delete:\n" + result.failures.joined(separator: "\n")
            }
        } catch { notice = "Nothing was deleted: \(error.localizedDescription)" }
    }

    private func exportSelected() {
        guard canActOnSelection else { return }
        let sessions = selectedSessions
        exportingAll = true
        Task { @MainActor in
            defer { exportingAll = false }
            do {
                if let result = try await tracker.exportSavedSessions(sessions) {
                    notice = "Exported \(result.count) selected session\(result.count == 1 ? "" : "s") to \(result.folder.path)"
                }
            } catch { notice = "Export failed: \(error.localizedDescription)" }
        }
    }

    private func exportAll() {
        exportingAll = true
        Task { @MainActor in
            defer { exportingAll = false }
            do {
                if let result = try await tracker.exportAllSavedSessions() {
                    let noun = result.count == 1 ? "session" : "sessions"
                    notice = "Exported \(result.count) \(noun) to \(result.folder.path)"
                }
            } catch { notice = "Export failed: \(error.localizedDescription)" }
        }
    }
}

struct TrackingTestView: View {
    @ObservedObject var tracker: ActivityTracker
    // Show event and mouse counters in a separate diagnostic window.
    var body: some View {
        VStack(alignment: .leading, spacing: 22) {
            Label("Test tracking", systemImage: "waveform.path.ecg").font(.title2.weight(.semibold))
            Text(tracker.isRecording ? (tracker.breakPhase == .resting ? "Detailed tracking is paused for your break. Counts resume when you return or the timer finishes." : "Use your keyboard and mouse to check that the counts update. These events are part of the current session.")
                : "Start a session in the main window to check live tracking. Counts below are from the latest session in this app run.")
                .foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
            HStack(spacing: 32) {
                metric("Individual events", tracker.eventCount)
                Divider().frame(height: 44)
                metric("Mouse intervals", tracker.movementRows)
            }.frame(maxWidth: .infinity)
            Text("Counts update about once per second. Mouse intervals also include seconds without movement.")
                .font(.caption).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
        }.padding(28).frame(width: 430)
    }
    // Display one diagnostic count without putting it on the main recording screen.
    private func metric(_ name: String, _ value: Int) -> some View {
        VStack(spacing: 6) {
            Text(value, format: .number).font(.largeTitle).monospacedDigit()
            Text(name).font(.caption).foregroundStyle(.secondary)
        }
    }
}
