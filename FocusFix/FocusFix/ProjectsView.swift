import SwiftUI
import UniformTypeIdentifiers

struct ProjectsView: View {
    @ObservedObject var store: ProjectStore
    @ObservedObject var tracker: ActivityTracker
    let close: () -> Void
    var reduceMotionOverride: Bool? = nil
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var selectedProject: UUID?
    @State private var projectEditor = false
    @State private var editingProject: UUID?
    @State private var projectName = ""
    @State private var projectColor = Color(tagHex: SessionTags.palette[0])
    @State private var newTask = ""
    @State private var editingTask: UUID?
    @State private var taskTitle = ""
    @State private var error: String?
    @State private var settled: Set<UUID> = []
    @State private var swiping: Set<UUID> = []
    @State private var deletion: WorkProject?

    private var project: WorkProject? { store.projects.first { $0.id == selectedProject } }
    private var usesReducedMotion: Bool { reduceMotionOverride ?? reduceMotion }
    private var animation: Animation? { usesReducedMotion ? nil : .spring(duration: 0.45, bounce: 0.12) }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Button(action: close) { Label("Timer", systemImage: "chevron.left") }.buttonStyle(.plain)
                Spacer()
                Text(tracker.isWorking ? tracker.workAssignment.summary : "Ready to focus")
                    .font(.caption).foregroundStyle(.secondary).lineLimit(1)
                Text(clock).font(.caption.monospacedDigit()).foregroundStyle(.secondary)
            }
            Divider()
            HStack {
                if project != nil && !projectEditor {
                    Button { selectedProject = nil } label: { Image(systemName: "chevron.left") }
                        .buttonStyle(.plain).accessibilityLabel("Back to projects")
                }
                Text(projectEditor ? (editingProject == nil ? "New project" : "Edit project") : project?.name ?? "Projects")
                    .font(.title3.weight(.semibold)).lineLimit(1)
                Spacer()
                if !projectEditor {
                    Button {
                        editingProject = nil; projectName = ""; projectColor = Color(tagHex: SessionTags.palette[0]); projectEditor = true
                    } label: { Image(systemName: "plus") }.accessibilityLabel("New project")
                }
            }
            if let notice = store.notice {
                Text(notice).font(.caption).foregroundStyle(.red)
                Button("Reload projects") { store.reload() }
            }
            if let error { Text(error).font(.caption).foregroundStyle(.red).fixedSize(horizontal: false, vertical: true) }
            if projectEditor { projectForm }
            else if let project { checklist(project) }
            else { projectList }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .confirmationDialog("Delete project and its tasks? Recorded work will be kept.", isPresented: Binding(
            get: { deletion != nil }, set: { if !$0 { deletion = nil } }), titleVisibility: .visible) {
                Button("Delete project", role: .destructive) {
                    if let deletion { perform { try store.deleteProject(deletion.id) } }
                    deletion = nil
                }
                Button("Cancel", role: .cancel) { deletion = nil }
            }
        .onChange(of: store.projects) { _, values in tracker.reconcileWorkAssignment(projects: values) }
        .task(id: project?.tasks) {
            // Dates survive navigation and relaunch; cancelled tasks cannot perform stale moves.
            swiping = []
            let completedNow = matureTasks()
            withAnimation(animation) { settled = completedNow }
            while !Task.isCancelled {
                let completed = matureTasks()
                if completed != settled {
                    let duration = usesReducedMotion ? 0.15 : 0.18
                    withAnimation(usesReducedMotion ? .easeOut(duration: duration) : .easeIn(duration: duration)) {
                        swiping = completed.subtracting(settled)
                    }
                    do { try await Task.sleep(for: .seconds(duration)) } catch { return }
                    withAnimation(animation) { settled = completed; swiping = [] }
                    continue
                }
                let pending = (project?.tasks ?? []).compactMap(\.completedAt)
                    .map { 3 - Date().timeIntervalSince($0) }.filter { $0 > 0 }
                guard let wait = pending.min() else { return }
                do { try await Task.sleep(for: .seconds(wait)) } catch { return }
            }
        }
    }

    private func matureTasks() -> Set<UUID> {
        Set((project?.tasks ?? []).filter {
            $0.completedAt.map { Date().timeIntervalSince($0) >= 3 } ?? false
        }.map(\.id))
    }

    private var clock: String {
        let seconds = Int(max(0, tracker.declaredWorkSeconds))
        return String(format: "%d:%02d", seconds / 60, seconds % 60)
    }

    private var projectForm: some View {
        VStack(alignment: .leading, spacing: 12) {
            TextField("Project name", text: $projectName).textFieldStyle(.roundedBorder).onSubmit(saveProject)
            ColorPicker("Project color", selection: $projectColor, supportsOpacity: false)
            HStack {
                Button("Cancel") { projectEditor = false; error = nil }
                Spacer()
                Button("Save project", action: saveProject).buttonStyle(.borderedProminent)
                    .disabled(projectName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
            Spacer(minLength: 0)
        }
    }

    private var projectList: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 0) {
                if store.projects.isEmpty {
                    VStack(alignment: .leading, spacing: 8) {
                        Image(systemName: "doc.text").font(.largeTitle).foregroundStyle(.teal)
                        Text("Give your work a home").font(.headline)
                        Text("Create a project, add a few tasks, and choose what to focus on.").font(.callout).foregroundStyle(.secondary)
                    }.padding(.vertical, 16)
                }
                ForEach(store.projects) { value in
                    HStack(spacing: 10) {
                        Button {
                            selectedProject = value.id; error = nil; editingTask = nil
                        } label: {
                            HStack {
                                Circle().fill(Color(tagHex: value.color)).frame(width: 10, height: 10)
                                Text(value.name).lineLimit(1)
                                Spacer()
                                Text("\(value.tasks.filter { $0.completedAt == nil }.count)").foregroundStyle(.secondary)
                                Image(systemName: "chevron.right").font(.caption).foregroundStyle(.secondary)
                            }.contentShape(Rectangle())
                        }.buttonStyle(.plain)
                        Menu { projectActions(value) } label: { Image(systemName: "ellipsis") }.menuStyle(.borderlessButton).fixedSize()
                            .accessibilityLabel("Options for \(value.name)")
                    }.padding(.vertical, 11)
                    Divider()
                }
                Button(tracker.isWorking ? "Switch to no project" : "Start work without a project") {
                    perform { try tracker.workOn(project: nil) }
                }.buttonStyle(.plain).foregroundStyle(.secondary).padding(.vertical, 12)
            }
        }
    }

    private func checklist(_ project: WorkProject) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Circle().fill(Color(tagHex: project.color)).frame(width: 8, height: 8)
                Text("Untasked Work").font(.callout)
                Spacer()
                workButton(project, task: nil)
                Menu { projectActions(project) } label: { Image(systemName: "ellipsis") }.menuStyle(.borderlessButton).fixedSize()
                    .accessibilityLabel("Project options")
            }
            HStack {
                TextField("Add a task…", text: $newTask).textFieldStyle(.roundedBorder).onSubmit { addTask(project) }
                Button { addTask(project) } label: { Image(systemName: "plus") }.accessibilityLabel("Add task")
                    .disabled(newTask.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
            ScrollViewReader { reader in
                ScrollView {
                    LazyVStack(spacing: 0) {
                        if project.tasks.isEmpty {
                            Text("What would you like to work on?").font(.callout).foregroundStyle(.secondary).padding(.vertical, 18)
                        }
                        let ordered = project.tasks.filter { !settled.contains($0.id) } + project.tasks.filter { settled.contains($0.id) }.sorted {
                            ($0.completedAt ?? .distantPast) < ($1.completedAt ?? .distantPast)
                        }
                        ForEach(ordered) { task in
                            taskRow(task, project: project).id(task.id)
                                .transition(usesReducedMotion ? .opacity : .asymmetric(insertion: .move(edge: .trailing).combined(with: .opacity), removal: .opacity))
                        }
                    }.animation(animation, value: project.tasks).animation(animation, value: settled)
                }
                .onChange(of: selectedProject) { _, _ in if let first = project.tasks.first { reader.scrollTo(first.id, anchor: .top) } }
            }
        }
    }

    private func taskRow(_ task: ProjectTask, project: WorkProject) -> some View {
        let finished = settled.contains(task.id) || swiping.contains(task.id)
        return HStack(spacing: 9) {
            Button {
                perform { try store.completeTask(task.id, project: project.id, at: task.completedAt == nil ? Date() : nil) }
            } label: {
                Image(systemName: task.completedAt == nil ? "circle" : "checkmark.circle.fill")
                    .font(.system(size: 19)).foregroundStyle(task.completedAt == nil ? Color.secondary : .green)
            }.buttonStyle(.plain).accessibilityLabel("\(task.completedAt == nil ? "Complete" : "Reopen") \(task.title)")
                .accessibilityValue(task.completedAt == nil ? "Incomplete" : "Complete")
            if editingTask == task.id {
                TextField("Task title", text: $taskTitle).textFieldStyle(.roundedBorder).onSubmit { saveTask(task, project: project) }
                    .onExitCommand { editingTask = nil }
                Button("Save") { saveTask(task, project: project) }
            } else {
                Text(task.title).font(.callout).lineLimit(2).foregroundStyle(finished ? .secondary : .primary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                if task.completedAt == nil { workButton(project, task: task) }
                Menu {
                    Button("Rename") { editingTask = task.id; taskTitle = task.title }
                    Button("Move up") { move(task, project: project, direction: -1) }
                    Button("Move down") { move(task, project: project, direction: 1) }
                    Button("Delete task", role: .destructive) { perform { try store.deleteTask(task.id, project: project.id) } }
                } label: { Image(systemName: "ellipsis") }.menuStyle(.borderlessButton).fixedSize()
                    .accessibilityLabel("Options for \(task.title)")
            }
        }
        .padding(.vertical, 10).padding(.horizontal, 4)
        .background(tracker.isWorking && tracker.workAssignment.taskID == task.id ? Color(tagHex: project.color).opacity(0.09) : .clear,
                    in: RoundedRectangle(cornerRadius: 8))
        .scaleEffect(finished && !usesReducedMotion ? 0.85 : 1, anchor: .leading).opacity(finished ? 0.6 : 1)
        .offset(x: swiping.contains(task.id) && !usesReducedMotion ? 430 : 0)
        .overlay(alignment: .bottom) { Divider().opacity(0.5) }
        .draggable(task.id.uuidString)
        .dropDestination(for: String.self) { values, location in
            guard let id = values.first.flatMap(UUID.init(uuidString:)), project.tasks.contains(where: { $0.id == id }) else { return false }
            perform {
                if location.y > 20 { try store.moveTask(id, after: task.id, project: project.id) }
                else { try store.moveTask(id, before: task.id, project: project.id) }
            }
            return true
        }
        .accessibilityAction(named: "Move up") { move(task, project: project, direction: -1) }
        .accessibilityAction(named: "Move down") { move(task, project: project, direction: 1) }
    }

    private func workButton(_ project: WorkProject, task: ProjectTask?) -> some View {
        let active = tracker.isWorking && tracker.workAssignment.projectID == project.id && tracker.workAssignment.taskID == task?.id
        return Button {
            perform { try tracker.workOn(project: project, task: task) }
        } label: {
            Image(systemName: active ? "waveform" : "play.fill").font(.caption)
                .foregroundStyle(active ? Color(tagHex: project.color) : .secondary)
        }.buttonStyle(.plain).disabled(active)
            .help(active ? "Currently working on this" : "Work on this")
            .accessibilityLabel(active ? "Currently working on \(task?.title ?? "Untasked Work")" : "Work on \(task?.title ?? "Untasked Work")")
    }

    @ViewBuilder private func projectActions(_ project: WorkProject) -> some View {
        Button("Edit project") {
            editingProject = project.id; projectName = project.name; projectColor = Color(tagHex: project.color); projectEditor = true
        }
        Button("Delete project", role: .destructive) { deletion = project }
    }
    private func saveProject() {
        perform {
            if let editingProject { try store.editProject(editingProject, name: projectName, color: projectColor.tagHex) }
            else { selectedProject = try store.addProject(projectName, color: projectColor.tagHex) }
            projectEditor = false
        }
    }
    private func addTask(_ project: WorkProject) { perform { try store.addTask(newTask, project: project.id); newTask = "" } }
    private func saveTask(_ task: ProjectTask, project: WorkProject) {
        perform { try store.renameTask(task.id, project: project.id, title: taskTitle); editingTask = nil }
    }
    private func move(_ task: ProjectTask, project: WorkProject, direction: Int) {
        guard let index = project.tasks.firstIndex(where: { $0.id == task.id }), project.tasks.indices.contains(index + direction) else { return }
        perform {
            if direction < 0 { try store.moveTask(task.id, before: project.tasks[index - 1].id, project: project.id) }
            else { try store.moveTask(project.tasks[index + 1].id, before: task.id, project: project.id) }
        }
    }
    private func perform(_ action: () throws -> Void) {
        do { try action(); error = nil } catch { self.error = error.localizedDescription }
    }
}
