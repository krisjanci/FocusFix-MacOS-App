import SwiftUI
import AppKit

struct AIPlanningButton: View {
    let action: () -> Void
    @Environment(\.scenePhase) private var scenePhase
    @State private var reason = AIPlanning.unavailableReason
    @State private var showingInfo = false
    private let teal = Color(red: 0.02, green: 0.60, blue: 0.54)

    var body: some View {
        HStack(spacing: 6) {
            Button(action: action) {
                HStack(spacing: 7) {
                    Text("Try with AI")
                    Image(systemName: "mic.fill")
                }.font(.system(size: 12, weight: .medium))
                    .padding(.horizontal, 12).frame(height: 26)
                    .foregroundStyle(reason == nil ? teal : Color.secondary)
                    .background((reason == nil ? teal : Color.secondary).opacity(0.08), in: Capsule())
                    .contentShape(Capsule())
            }.buttonStyle(.plain).disabled(reason != nil).opacity(reason == nil ? 1 : 0.45)
                .accessibilityLabel("Try with AI")
                .help(reason ?? "Describe your work to create an editable plan")
            if reason != nil {
                Button { reason = AIPlanning.unavailableReason; showingInfo = true } label: {
                    Image(systemName: "info.circle").foregroundStyle(.gray).font(.system(size: 14))
                        .frame(width: 24, height: 26).contentShape(Rectangle())
                }.buttonStyle(.plain).accessibilityLabel("How to enable Apple Intelligence")
                    .popover(isPresented: $showingInfo) {
                        VStack(alignment: .leading, spacing: 12) {
                            Text("Use Apple Intelligence").font(.headline)
                            if let reason { Text(reason).font(.callout) }
                            Text(AIPlanning.setup).font(.callout).foregroundStyle(.secondary)
                            Button("Open System Settings") {
                                NSWorkspace.shared.open(URL(fileURLWithPath: "/System/Applications/System Settings.app"))
                            }
                            Link("Apple Intelligence setup guide", destination: URL(string: "https://support.apple.com/121115")!)
                            Button("Check again") { reason = AIPlanning.unavailableReason; if reason == nil { showingInfo = false } }
                        }.padding(20).frame(width: 330)
                    }
            }
        }
        .task { reason = AIPlanning.unavailableReason }
        .onChange(of: scenePhase) { _, value in if value == .active { reason = AIPlanning.unavailableReason } }
    }
}

@available(macOS 26.0, *)
struct AIPlanningSheet: View {
    @ObservedObject var store: ProjectStore
    let project: WorkProject?
    let initialText: String
    let initialColor: String
    let saved: (UUID) -> Void
    @Environment(\.dismiss) private var dismiss
    @StateObject private var speech = AIPlanningSpeech()
    @State private var title = ""
    @State private var color = "#168B80"
    @State private var tasks: [ProjectTask] = []
    @State private var preview = false
    @State private var generating = false
    @State private var error: String?
    @State private var job: Task<Void, Never>?
    private let teal = Color(red: 0.02, green: 0.60, blue: 0.54)
    private var busy: Bool { generating || speech.isBusy }

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            HStack(spacing: 8) {
                Image(systemName: preview ? "checklist" : "mic.fill").foregroundStyle(teal)
                Text(preview ? "Review your plan" : "Try with AI").font(.system(size: 22, weight: .semibold, design: .rounded))
                Spacer()
                Text(preview ? "2 of 2" : "1 of 2").font(.caption.monospacedDigit()).foregroundStyle(.secondary)
            }
            Text(subtitle).font(.callout).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    if preview { previewContent } else { captureContent }
                }.padding(1)
            }.scrollIndicators(.automatic)
            if let error = error ?? speech.error {
                Text(error).font(.caption).foregroundStyle(.red).fixedSize(horizontal: false, vertical: true)
                    .accessibilityLabel("Error: \(error)")
            }
            Divider()
            HStack {
                Button("Cancel") { cancel(); dismiss() }.keyboardShortcut(.cancelAction)
                Spacer()
                if preview {
                    Button("Back") { preview = false; error = nil }
                    Button(project == nil ? "Save project & tasks" : "Save tasks", action: save)
                        .buttonStyle(.borderedProminent).disabled(tasks.isEmpty)
                } else {
                    Button(action: generate) {
                        HStack(spacing: 7) {
                            if generating { ProgressView().controlSize(.small) }
                            Text(generating ? "Organizing…" : "Create preview")
                        }
                    }.buttonStyle(.borderedProminent)
                        .disabled(busy || speech.isRecording || speech.transcript.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || speech.transcript.count > 4000)
                }
            }
        }.padding(24).frame(width: 440, height: 580).tint(teal)
            .background {
                ZStack {
                    Color(nsColor: .windowBackgroundColor)
                    if let project { Color(tagHex: project.color).opacity(0.04) }
                }
            }
            .onAppear { speech.transcript = initialText; color = initialColor }
            .onDisappear(perform: cancel)
    }

    private var subtitle: String {
        if preview { return project == nil ? "Make it yours before saving. Nothing has been added yet." : "New tasks for \(project!.name). Review before adding them." }
        return project == nil ? "Talk through a project and its tasks. We’ll organize the titles and estimate focused work." : "Describe what you need to do in \(project!.name). We’ll turn it into tasks."
    }

    private var captureContent: some View {
        VStack(alignment: .leading, spacing: 12) {
            Button {
                job = Task { if speech.isRecording { await speech.finish() } else { await speech.start() } }
            } label: {
                HStack(spacing: 10) {
                    Image(systemName: speech.isRecording ? "stop.circle.fill" : "mic.circle.fill").font(.system(size: 30))
                    VStack(alignment: .leading, spacing: 3) {
                        Text(speech.isRecording ? "Stop recording" : "Start speaking").font(.headline)
                        Text(speech.isRecording ? "Your microphone is on" : "Up to 2 minutes · transcribed on your Mac").font(.caption).foregroundStyle(.secondary)
                    }
                    Spacer()
                }.foregroundStyle(speech.isRecording ? Color.red : teal)
                    .padding(14).background(teal.opacity(0.06), in: RoundedRectangle(cornerRadius: 14))
                    .overlay { RoundedRectangle(cornerRadius: 14).stroke(teal.opacity(0.16)) }
            }.buttonStyle(.plain).disabled(busy)
            if speech.isBusy {
                HStack(spacing: 8) { ProgressView().controlSize(.small); Text(speech.status).font(.caption).foregroundStyle(.secondary) }
            } else if speech.isRecording {
                Text(speech.status).font(.caption).foregroundStyle(.secondary)
            }
            Text("Your words").font(.callout.weight(.medium))
            TextEditor(text: $speech.transcript).font(.body).scrollContentBackground(.hidden)
                .padding(8).frame(minHeight: 170)
                .background(Color.primary.opacity(0.035), in: RoundedRectangle(cornerRadius: 10))
                .overlay { RoundedRectangle(cornerRadius: 10).stroke(Color.primary.opacity(0.1)) }
                .disabled(busy || speech.isRecording).accessibilityLabel("Work plan transcript, editable")
            HStack {
                Text("Speak, type, or edit your transcript.")
                Spacer()
                Text("\(speech.transcript.count)/4,000").foregroundStyle(speech.transcript.count > 4000 ? .red : .secondary)
            }.font(.caption2).foregroundStyle(.secondary)
            Label("Processed on your Mac. Audio is deleted after transcription or when you close this window.", systemImage: "lock.shield")
                .font(.caption).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
        }
    }

    private var previewContent: some View {
        VStack(alignment: .leading, spacing: 14) {
            if project == nil {
                Text("Project title").font(.callout.weight(.medium))
                TextField("Project title", text: $title).textFieldStyle(.roundedBorder)
                ProjectColorChooser(selection: $color, inline: true)
                    .accessibilityLabel("Project color")
            }
            HStack {
                Text("Tasks · \(tasks.count)").font(.callout.weight(.medium))
                Spacer()
                Text("Predicted FS").font(.caption).foregroundStyle(.secondary)
            }
            ForEach($tasks) { $task in
                HStack(alignment: .top, spacing: 8) {
                    TextField("Task title", text: $task.title, axis: .vertical)
                        .textFieldStyle(.plain).font(.system(size: 14)).lineLimit(1...3)
                        .accessibilityLabel("Task title")
                    Picker("Predicted FS", selection: Binding(get: { task.estimate }, set: { task.predictedFocusSessions = $0 })) {
                        ForEach(1...6, id: \.self) { half in Text((Double(half) / 2).formatted()).tag(Double(half) / 2) }
                    }.labelsHidden().frame(width: 66).accessibilityLabel("Predicted Focus Sessions for \(task.title)")
                    Button { tasks.removeAll { $0.id == task.id } } label: { Image(systemName: "minus.circle").foregroundStyle(.secondary) }
                        .buttonStyle(.plain).accessibilityLabel("Remove \(task.title)")
                }.padding(12).background(Color.primary.opacity(0.035), in: RoundedRectangle(cornerRadius: 10))
            }
            Button { tasks.append(ProjectTask(title: "", predictedFocusSessions: 1)) } label: {
                Label("Add a task", systemImage: "plus")
            }.buttonStyle(.plain).foregroundStyle(teal).disabled(tasks.count >= 30)
            Text("1 FS = 1 hour of focused work. AI estimates are suggestions; adjust them to fit your pace.")
                .font(.caption).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
        }
    }

    private func generate() {
        error = nil; speech.error = nil; generating = true
        job = Task {
            defer { generating = false }
            do {
                let plan = try await AIPlanning.generate(transcript: speech.transcript, projectName: project?.name)
                try Task.checkCancellation()
                title = plan.title
                tasks = plan.tasks.map { ProjectTask(title: $0.title, predictedFocusSessions: Double($0.focusSessions) ?? 1) }
                preview = true
            } catch is CancellationError { } catch { self.error = error.localizedDescription }
        }
    }

    private func save() {
        do {
            let id = try store.savePlan(projectID: project?.id, name: title, color: color, tasks: tasks)
            saved(id); dismiss()
        } catch { self.error = error.localizedDescription }
    }

    private func cancel() { job?.cancel(); job = nil; speech.cancel() }
}
