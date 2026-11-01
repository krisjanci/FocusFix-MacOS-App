// MARK: - FF: SESSIONS
// Shows the local session library and the separate Test tracking window.

import SwiftUI
import AppKit

struct SessionLibraryView: View {
    @ObservedObject var tracker: ActivityTracker
    @State private var selection: SavedSession.ID?
    @State private var pendingDeletion: SavedSession?
    @State private var confirmDeletion = false
    @State private var notice: String?
    @State private var exportingAll = false
    @State private var tagging: SavedSession?
    @ObservedObject var tagLibrary = SessionTagLibrary.shared

    // Find the saved session matching the current list selection.
    private var selected: SavedSession? { tracker.sessions.first { $0.id == selection } }
    private let teal = Color(red: 0.02, green: 0.60, blue: 0.54)

    // List local saved sessions with selection and export/delete controls.
    var body: some View {
        VStack(spacing: 0) {
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Your sessions").font(.title2.weight(.semibold))
                    Text("All time counts toward your daily goal. Sessions of 15+ minutes are saved in your history.").font(.callout).foregroundStyle(.secondary)
                }
                Spacer()
                Text("\(tracker.sessions.count)").font(.title2.monospacedDigit()).foregroundStyle(teal)
            }.padding(24)
            Divider()
            if let error = tracker.libraryError {
                ContentUnavailableView("Couldn't load sessions", systemImage: "exclamationmark.triangle",
                    description: Text(error))
            } else if tracker.sessions.isEmpty {
                ContentUnavailableView("No sessions yet", systemImage: "clock",
                    description: Text("Complete a session of 15 minutes or longer to see it here."))
            } else {
                ScrollViewReader { proxy in
                    ScrollView {
                        LazyVStack(spacing: 8) {
                            ForEach(tracker.sessions) { session in
                                sessionRow(session)
                            }
                        }.padding(.horizontal, 18).padding(.vertical, 10)
                    }
                    .focusable()
                    .onKeyPress(.upArrow) { moveSelection(-1); return .handled }
                    .onKeyPress(.downArrow) { moveSelection(1); return .handled }
                    .onKeyPress(.return) {
                        guard let selected, !exportingAll else { return .ignored }
                        tagging = selected
                        return .handled
                    }
                    .onChange(of: selection) { _, id in
                        if let id { proxy.scrollTo(id, anchor: .center) }
                    }
                }
            }
            Divider()
            HStack {
                Button { tracker.refreshSessions() } label: { Image(systemName: "arrow.clockwise") }
                    .help("Refresh sessions").accessibilityLabel("Refresh sessions")
                Button("Show in Finder") {
                    if let selected { NSWorkspace.shared.activateFileViewerSelecting([selected.folder]) }
                }.disabled(selected == nil)
                Spacer()
                Button("Delete…", role: .destructive) {
                    pendingDeletion = selected
                    confirmDeletion = true
                }.disabled(exportingAll || selected == nil || selected.map(tracker.isActive) == true)
                Button(exportingAll ? "Exporting…" : "Export All…") { exportAll() }
                    .disabled(exportingAll || tracker.libraryError != nil || !tracker.sessions.contains { !tracker.isActive($0) })
                    .help("Export all saved sessions into one folder. The current recording is skipped.")
                Button("Export…") { exportSelected() }
                    .buttonStyle(.borderedProminent).tint(teal)
                    .disabled(exportingAll || selected == nil || selected.map(tracker.isActive) == true)
            }.padding(18)
        }
        .frame(minWidth: 650, minHeight: 400)
        .background(Color(nsColor: .windowBackgroundColor))
        .onAppear { tracker.refreshSessions() }
        .sheet(item: $tagging) { session in
            SessionTagEditor(tags: session.tags, colors: session.tagColors, library: tagLibrary) { tags, colors in
                try tracker.updateTags(tags, colors: colors, for: session)
            }
        }
        .confirmationDialog("Move this session to Trash?", isPresented: $confirmDeletion, titleVisibility: .visible) {
            Button("Move to Trash", role: .destructive) {
                guard let session = pendingDeletion else { return }
                do {
                    try tracker.deleteSession(session)
                    selection = nil
                } catch { notice = error.localizedDescription }
                pendingDeletion = nil
            }
            Button("Cancel", role: .cancel) { pendingDeletion = nil }
        } message: {
            Text("Session: \(pendingDeletion?.startedAt.formatted(date: .abbreviated, time: .standard) ?? "Selected session"). The local recording will be moved to Trash. Exported copies and backups stay unchanged.")
            Text("Deleting a local session does not delete research data already received. Use Settings → Privacy & Research to request research-data deletion.")
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
                SessionTagButton(tags: session.tags,
                    colors: tagLibrary.resolvedColors(for: session.tags, saved: session.tagColors)) {
                        selection = session.id; tagging = session
                    }.disabled(exportingAll)
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
                    .stroke(selection == session.id ? teal : Color.clear, lineWidth: 1.5)
            }
            .contentShape(RoundedRectangle(cornerRadius: 10))
            .onTapGesture { selection = session.id }
            .id(session.id)
    }

    // Preserve arrow-key selection while tag chips remain independent controls.
    private func moveSelection(_ step: Int) {
        guard !tracker.sessions.isEmpty else { return }
        let current = tracker.sessions.firstIndex { $0.id == selection }
        let next = current.map { min(max($0 + step, 0), tracker.sessions.count - 1) } ?? 0
        selection = tracker.sessions[next].id
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
    // Export the selected session through the tracker and report any error.
    private func exportSelected() {
        guard let selected else { return }
        do {
            if let url = try tracker.exportSavedSession(selected) { notice = "Exported to \(url.path)" }
        } catch { notice = "Export failed: \(error.localizedDescription)" }
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
