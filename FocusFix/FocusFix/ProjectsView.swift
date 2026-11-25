import SwiftUI
import AppKit
import UniformTypeIdentifiers

struct ProjectsView: View {
    @ObservedObject var store: ProjectStore
    @ObservedObject var tracker: ActivityTracker
    let close: () -> Void
    var reduceMotionOverride: Bool? = nil
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var selectedProject: UUID?
    @State private var detailTask: ProjectTask?
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
    @State private var editingList = false
    @State private var dragSource: ChecklistDragItem?
    @State private var insertion: ChecklistInsertion?
    @State private var projectsExpansion = ChecklistExpansion(size: 8)
    @State private var tasksExpansion = ChecklistExpansion(size: 7)
    @State private var showingTaskEntry = false
    @State private var newTaskScrollTarget: UUID?
    @FocusState private var newTaskFocused: Bool
    @FocusState private var renameFocus: UUID?
    private let teal = Color(red: 0.02, green: 0.60, blue: 0.54)

    private var project: WorkProject? { store.projects.first { $0.id == selectedProject } }
    private var usesReducedMotion: Bool { reduceMotionOverride ?? reduceMotion }
    private var animation: Animation? { usesReducedMotion ? nil : .spring(duration: 0.45, bounce: 0.12) }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Button(action: goBack) {
                    Image(systemName: "arrow.left").frame(width: 28, height: 22)
                }.buttonStyle(.bordered)
                    .accessibilityLabel(projectEditor ? "Cancel project editing" : project == nil ? "Back to timer" : "Back to projects")
                pageHeading
                    .font(.system(size: 23, weight: .semibold, design: .rounded)).lineLimit(1)
                    .frame(maxWidth: .infinity, alignment: .leading)
                if !projectEditor {
                    Button(editingList ? "Done" : "Edit", action: toggleEditing)
                        .buttonStyle(.plain).font(.callout.weight(.medium)).foregroundStyle(teal)
                        .accessibilityLabel(editingList ? "Finish editing" : "Edit projects and tasks")
                }
            }
            if tracker.isWorking {
                HStack {
                    Text(tracker.workAssignment.summary).lineLimit(1)
                    Spacer()
                    Text(clock).monospacedDigit()
                }.font(.caption).foregroundStyle(.secondary)
            }
            if tracker.needsPermission {
                Text(tracker.message).font(.caption).foregroundStyle(.secondary)
                Button("Enable Input Monitoring") { tracker.requestPermission() }
            } else if tracker.hasError {
                Text(tracker.message).font(.caption).foregroundStyle(.red)
            }
            if let notice = store.notice {
                Text(notice).font(.caption).foregroundStyle(.red)
                Button("Reload projects") { store.reload() }
            }
            if let notice = tracker.projectWorkNotice {
                HStack {
                    Text(notice).font(.caption).foregroundStyle(.secondary)
                    Button("Refresh") { tracker.refreshSessions() }.buttonStyle(.plain)
                }
            }
            if let error { Text(error).font(.caption).foregroundStyle(.red).fixedSize(horizontal: false, vertical: true) }
            if projectEditor { projectForm }
            else if let project { checklist(project) }
            else { projectList }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .preference(key: BrowsedProjectTintKey.self, value: project?.color)
        .sheet(item: $detailTask) { task in
            if let project {
                ProjectTaskDetails(store: store, tracker: tracker, projectID: project.id, task: task)
            }
        }
        .onExitCommand(perform: cancelEditingOrGoBack)
        .confirmationDialog("Delete project and its tasks? Recorded work will be kept.", isPresented: Binding(
            get: { deletion != nil }, set: { if !$0 { deletion = nil } }), titleVisibility: .visible) {
                Button("Delete project", role: .destructive) {
                    if let deletion { perform { try store.deleteProject(deletion.id) } }
                    deletion = nil
                }
                Button("Cancel", role: .cancel) { deletion = nil }
            }
        .onChange(of: store.projects) { _, values in
            tracker.reconcileWorkAssignment(projects: values)
            projectsExpansion.clamp(total: values.count)
            tasksExpansion.clamp(total: project?.tasks.count ?? 0)
            if let editingProject, !values.contains(where: { $0.id == editingProject }) { self.editingProject = nil }
            if let editingTask, project?.tasks.contains(where: { $0.id == editingTask }) != true { self.editingTask = nil }
        }
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
            VStack(alignment: .leading, spacing: 8) {
                HStack(spacing: 8) {
                    Text("Project color").font(.callout)
                    Circle().fill(projectColor).frame(width: 12, height: 12).accessibilityLabel("Selected project color")
                }
                ProjectColorChooser(selection: Binding(get: { projectColor.tagHex }, set: { projectColor = Color(tagHex: $0) }), inline: true)
            }
            HStack {
                Button("Cancel") { projectEditor = false; error = nil }
                Spacer()
                Button("Save project", action: saveProject).buttonStyle(.borderedProminent)
                    .disabled(projectName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
            Spacer(minLength: 0)
        }
    }

    @ViewBuilder private var pageHeading: some View {
        if projectEditor { Text("New project") }
        else if let project, editingProject == project.id {
            projectNameField(project)
        } else if let project, editingList && !project.isRandomTasks {
            Button(project.name) { beginProjectRename(project) }.buttonStyle(.plain)
                .accessibilityLabel("Rename project \(project.name)")
        } else { Text(project?.name ?? "Projects") }
    }

    private var projectList: some View {
        GeometryReader { geometry in
            let rowHeight = max(52, projectsExpansion.rowHeight(available: geometry.size.height,
                reserved: store.projects.count > 8 ? 60 : 30, divider: 1))
            ScrollView {
                VStack(alignment: .leading, spacing: 8) {
                    VStack(alignment: .leading, spacing: 0) {
                        ForEach(Array(store.projects[projectsExpansion.range(total: store.projects.count)])) { value in
                            HStack(spacing: 10) {
                                projectColorControl(value)
                                if editingProject == value.id {
                                    projectNameField(value)
                                    Button { saveProjectName(value) } label: { Image(systemName: "checkmark") }
                                        .buttonStyle(.plain).accessibilityLabel("Save project name")
                                } else {
                                    Button {
                                        if editingList { beginProjectRename(value) } else { openProject(value) }
                                    } label: {
                                        VStack(alignment: .leading, spacing: 3) {
                                            Text(value.name).lineLimit(1)
                                            Text("Total work time: " + projectTime(value.id))
                                                .font(.caption.monospacedDigit()).foregroundStyle(.secondary)
                                                .padding(.leading, 8)
                                        }.frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading).contentShape(Rectangle())
                                    }.buttonStyle(.plain).disabled(editingList && value.isRandomTasks)
                                        .accessibilityLabel(editingList ? "Rename project \(value.name)" : "Open project \(value.name)")
                                        .accessibilityValue("Total work time: " + projectTime(value.id))
                                }
                                Text("\(value.tasks.filter { $0.completedAt == nil }.count)").foregroundStyle(.secondary)
                                if editingList {
                                    if value.isRandomTasks {
                                        Image(systemName: "lock.fill").font(.caption).foregroundStyle(.secondary)
                                            .frame(width: 34, height: 26).help("Random Tasks cannot be renamed or deleted")
                                    } else {
                                        deleteButton("Delete project \(value.name)") { deletion = value }
                                    }
                                } else {
                                    Button { openProject(value) } label: { Image(systemName: "chevron.right").font(.caption).foregroundStyle(.secondary) }
                                        .buttonStyle(.plain).accessibilityLabel("Open \(value.name)")
                                }
                            }.frame(height: rowHeight)
                            .modifier(ChecklistReorderRow(item: .project(value.id), enabled: editingProject != value.id, source: $dragSource, insertion: $insertion) { dragging, after in
                                guard case .project(let id) = dragging else { return }
                                perform { try store.moveProject(id, relativeTo: value.id, after: after) }
                            })
                            .accessibilityAction(named: "Move up") { moveProject(value, direction: -1) }
                            .accessibilityAction(named: "Move down") { moveProject(value, direction: 1) }
                            Divider()
                        }
                    }
                    if projectsExpansion.hasMore(total: store.projects.count) {
                        centeredListButton("chevron.down", width: 36, lighter: true, label: "Show more projects") { expandProjects() }
                    }
                    if projectsExpansion.isExpanded {
                        centeredListButton("chevron.up", width: 36, lighter: true, label: "Show fewer projects") { collapseProjects() }
                    }
                    centeredListButton("plus", label: "New project", action: beginNewProject)
                }
            }.scrollIndicators(.automatic)
        }
    }

    private func projectNameField(_ project: WorkProject) -> some View {
        TextField("Project name", text: $projectName).textFieldStyle(.roundedBorder)
            .focused($renameFocus, equals: project.id)
            .task { renameFocus = nil; await Task.yield(); guard !Task.isCancelled else { return }; renameFocus = project.id }
            .onSubmit { saveProjectName(project) }.onExitCommand { editingProject = nil }
    }

    @ViewBuilder private func projectColorControl(_ project: WorkProject) -> some View {
        if editingList {
            ProjectColorChooser(selection: Binding(get: {
                store.projects.first { $0.id == project.id }?.color ?? project.color
            }, set: { color in
                guard let current = store.projects.first(where: { $0.id == project.id }) else { return }
                perform { try store.editProject(current.id, name: current.name, color: color) }
            })).accessibilityLabel("Color for \(project.name)")
        } else { Circle().fill(Color(tagHex: project.color)).frame(width: 10, height: 10) }
    }

    private func orderedTasks(_ project: WorkProject) -> [ProjectTask] {
        project.tasks.filter { $0.completedAt == nil || !settled.contains($0.id) } + project.completedTasks.filter { settled.contains($0.id) }
    }

    private func checklist(_ project: WorkProject) -> some View {
        let ordered = orderedTasks(project)
        return GeometryReader { geometry in
            let rowHeight = max(58, tasksExpansion.rowHeight(available: geometry.size.height,
                reserved: ordered.count > 7 ? 94 : 64))
            ScrollViewReader { scroll in
                ScrollView {
                    VStack(alignment: .leading, spacing: 8) {
                        HStack {
                            projectColorControl(project)
                            Text("Untasked Work").font(.callout.bold())
                            Spacer()
                            if !editingList { workButton(project, task: nil) }
                        }.padding(.horizontal, 4)
                        VStack(spacing: 0) {
                            if project.tasks.isEmpty {
                                Text("What would you like to work on?").font(.callout).foregroundStyle(.secondary).padding(.vertical, 18)
                            }
                            ForEach(Array(ordered[tasksExpansion.range(total: ordered.count)])) { task in
                                taskRow(task, project: project, height: rowHeight).id(task.id)
                                    .transition(usesReducedMotion ? .opacity : .asymmetric(insertion: .move(edge: .trailing).combined(with: .opacity), removal: .opacity))
                            }
                        }.animation(animation, value: project.tasks).animation(animation, value: settled)
                        if tasksExpansion.hasMore(total: ordered.count) {
                            centeredListButton("chevron.down", width: 36, lighter: true, label: "Show more tasks") { expandTasks() }
                        }
                        if tasksExpansion.isExpanded {
                            centeredListButton("chevron.up", width: 36, lighter: true, label: "Show fewer tasks") { collapseTasks() }
                        }
                        if showingTaskEntry {
                            HStack {
                                TextField("Add a task…", text: $newTask).textFieldStyle(.roundedBorder)
                                    .focused($newTaskFocused).onSubmit { addTask(project) }
                                    .onExitCommand { cancelTaskEntry() }
                                    .task { await Task.yield(); guard !Task.isCancelled else { return }; newTaskFocused = true }
                                Button { addTask(project) } label: { Image(systemName: "plus") }.accessibilityLabel("Save new task")
                                    .disabled(newTask.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                            }
                        } else {
                            centeredListButton("plus", label: "Add task") { showingTaskEntry = true }
                        }
                    }
                }.scrollIndicators(.automatic)
                .onChange(of: newTaskScrollTarget) { _, id in
                    if let id { withAnimation(animation) { scroll.scrollTo(id, anchor: .bottom) } }
                }
            }
        }
    }

    private func centeredListButton(_ symbol: String, width: CGFloat = 108, lighter: Bool = false,
                                    label: String, action: @escaping () -> Void) -> some View {
        HStack {
            Spacer(minLength: 0)
            Button(action: action) {
                Image(systemName: symbol).font(.system(size: 13, weight: .medium))
                    .frame(width: width, height: 22)
                    .background {
                        ZStack {
                            RoundedRectangle(cornerRadius: 5).fill(Color.primary.opacity(0.06))
                            if lighter { RoundedRectangle(cornerRadius: 5).fill(Color.white.opacity(0.1)) }
                        }
                    }
                    .contentShape(RoundedRectangle(cornerRadius: 5))
            }.buttonStyle(.plain).buttonPressFeedback().accessibilityLabel(label).help(label)
            Spacer(minLength: 0)
        }
    }

    private func beginNewProject() {
        guard finishRename() else { return }
        editingList = false; editingProject = nil; projectName = ""
        projectColor = Color(tagHex: SessionTags.palette[0]); projectEditor = true
    }
    private func expandProjects() {
        guard finishRename() else { return }
        withAnimation(animation) { projectsExpansion.expand(total: store.projects.count) }
        dragSource = nil; insertion = nil
    }
    private func collapseProjects() {
        guard finishRename() else { return }
        withAnimation(animation) { projectsExpansion.collapse() }
        dragSource = nil; insertion = nil
    }
    private func expandTasks() {
        guard finishRename() else { return }
        withAnimation(animation) { tasksExpansion.expand(total: project?.tasks.count ?? 0) }
        dragSource = nil; insertion = nil
    }
    private func collapseTasks() {
        guard finishRename() else { return }
        withAnimation(animation) { tasksExpansion.collapse() }
        dragSource = nil; insertion = nil
    }
    private func cancelTaskEntry() { showingTaskEntry = false; newTask = ""; newTaskFocused = false; error = nil }

    private func taskRow(_ task: ProjectTask, project: WorkProject, height: CGFloat) -> some View {
        let finished = settled.contains(task.id) || swiping.contains(task.id)
        return HStack(spacing: 9) {
            Button {
                perform { try store.completeTask(task.id, project: project.id, at: task.completedAt == nil ? Date() : nil) }
            } label: {
                Image(systemName: task.completedAt == nil ? "circle" : "checkmark.circle.fill")
                    .font(.system(size: 19)).foregroundStyle(task.completedAt == nil ? Color.secondary : .green)
            }.buttonStyle(.plain).disabled(editingList)
                .accessibilityLabel("\(task.completedAt == nil ? "Complete" : "Reopen") \(task.title)")
                .accessibilityValue(task.completedAt == nil ? "Incomplete" : "Complete")
            if editingTask == task.id {
                TextField("Task title", text: $taskTitle).textFieldStyle(.roundedBorder)
                    .focused($renameFocus, equals: task.id)
                    .task { renameFocus = nil; await Task.yield(); guard !Task.isCancelled else { return }; renameFocus = task.id }
                    .onSubmit { saveTask(task, project: project) }.onExitCommand { editingTask = nil }
                Button { saveTask(task, project: project) } label: { Image(systemName: "checkmark") }
                    .buttonStyle(.plain).accessibilityLabel("Save task name")
            } else if editingList {
                Button { beginTaskRename(task) } label: {
                    Text(task.title).font(.system(size: 15)).lineLimit(1).frame(maxWidth: .infinity, alignment: .leading).contentShape(Rectangle())
                }.buttonStyle(.plain).accessibilityLabel("Rename task \(task.title)")
            } else {
                Button { detailTask = task } label: {
                    VStack(alignment: .leading, spacing: 4) {
                        Text(task.title).font(.system(size: 15)).lineLimit(1)
                            .foregroundStyle(finished ? .secondary : .primary)
                        HStack(spacing: 12) {
                            Text("Worked: " + taskTime(task, project: project.id))
                            Text("Predicted: \(task.estimate.formatted()) FS")
                        }.font(.caption2.monospacedDigit()).foregroundStyle(.secondary)
                            .padding(.leading, 8)
                    }.frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading).contentShape(Rectangle())
                }.buttonStyle(.plain).accessibilityLabel("Details for \(task.title)")
                    .accessibilityValue("Worked: " + taskTime(task, project: project.id) + "; Predicted: \(task.estimate.formatted()) Focus Sessions")
            }
            if editingList {
                deleteButton("Delete task \(task.title)") { perform { try store.deleteTask(task.id, project: project.id) } }
            } else if task.completedAt == nil { workButton(project, task: task) }
        }
        .frame(height: height)
        .padding(.horizontal, 4)
        .help(task.completedWork.map { "\($0.projectName) · \($0.taskTitle)" + ($0.seconds.map { " · " + taskTime($0) } ?? " · Saving task time…") } ?? task.title)
        .background(tracker.isWorking && tracker.workAssignment.taskID == task.id ? Color(tagHex: project.color).opacity(0.09) : .clear,
                    in: RoundedRectangle(cornerRadius: 8))
        .scaleEffect(finished && !editingList && !usesReducedMotion ? 0.85 : 1, anchor: .leading).opacity(finished && !editingList ? 0.6 : 1)
        .offset(x: swiping.contains(task.id) && !usesReducedMotion ? 430 : 0)
        .overlay(alignment: .bottom) { Divider().opacity(0.5) }
        .modifier(ChecklistReorderRow(item: .task(project: project.id, id: task.id, completed: task.completedAt != nil), enabled: editingTask != task.id,
            source: $dragSource, insertion: $insertion) { dragging, after in
                guard case .task(let parent, let id, _) = dragging, parent == project.id else { return }
                perform {
                    if after { try store.moveTask(id, after: task.id, project: project.id) }
                    else { try store.moveTask(id, before: task.id, project: project.id) }
                }
            })
        .accessibilityAction(named: "Move up") { move(task, project: project, direction: -1) }
        .accessibilityAction(named: "Move down") { move(task, project: project, direction: 1) }
    }

    private func taskTime(_ seconds: Double) -> String { ProjectWorkTotals.duration(seconds) }

    private func projectTime(_ id: UUID) -> String {
        guard let totals = tracker.projectWorkTotals else { return tracker.projectWorkNotice == nil ? "Loading…" : "Unavailable" }
        return taskTime(totals.projects[id, default: 0])
    }

    private func taskTime(_ task: ProjectTask, project: UUID) -> String {
        if let completed = task.completedWork { return completed.seconds.map(taskTime) ?? "Saving…" }
        guard let totals = tracker.projectWorkTotals else { return tracker.projectWorkNotice == nil ? "Loading…" : "Unavailable" }
        return taskTime(totals.tasks[project]?[task.id] ?? 0)
    }

    private func workButton(_ project: WorkProject, task: ProjectTask?) -> some View {
        let active = tracker.isWorking && tracker.workAssignment.projectID == project.id && tracker.workAssignment.taskID == task?.id
        return Button {
            let saved = perform { try tracker.workOn(project: project, task: task) }
            if saved, tracker.isWorking, tracker.workAssignment.projectID == project.id,
               tracker.workAssignment.taskID == task?.id { close() }
        } label: {
            Image(systemName: active ? "waveform" : "play.fill").font(.system(size: 11, weight: .semibold))
                .foregroundStyle(.white).frame(width: 34, height: 26)
                .background(teal.opacity(active ? 0.65 : 1), in: RoundedRectangle(cornerRadius: 7))
        }.buttonStyle(.plain).disabled(active)
            .help(active ? "Currently working on this" : "Work on this")
            .accessibilityLabel(active ? "Currently working on \(task?.title ?? "Untasked Work")" : "Work on \(task?.title ?? "Untasked Work")")
    }

    private func deleteButton(_ label: String, action: @escaping () -> Void) -> some View {
        Button(role: .destructive, action: action) {
            Image(systemName: "xmark").font(.system(size: 12, weight: .semibold))
                .foregroundStyle(.red).frame(width: 34, height: 26)
                .background(Color.red.opacity(0.1), in: RoundedRectangle(cornerRadius: 7))
        }.buttonStyle(.plain).accessibilityLabel(label).help(label)
    }

    private func openProject(_ project: WorkProject) {
        selectedProject = project.id; editingList = false; editingProject = nil; editingTask = nil
        tasksExpansion = ChecklistExpansion(size: 7); cancelTaskEntry()
        error = nil; dragSource = nil; insertion = nil
    }
    private func toggleEditing() {
        guard finishRename() else { return }
        editingList.toggle(); dragSource = nil; insertion = nil
    }
    private func beginProjectRename(_ project: WorkProject) {
        guard !project.isRandomTasks, finishRename() else { return }
        editingProject = project.id; projectName = project.name; renameFocus = nil
    }
    private func beginTaskRename(_ task: ProjectTask) {
        guard finishRename() else { return }
        editingTask = task.id; taskTitle = task.title; renameFocus = nil
    }
    private func finishRename() -> Bool {
        if let id = editingProject, let project = store.projects.first(where: { $0.id == id }), !saveProjectName(project) { return false }
        if let id = editingTask, let project, let task = project.tasks.first(where: { $0.id == id }), !saveTask(task, project: project) { return false }
        return true
    }
    @discardableResult private func saveProjectName(_ project: WorkProject) -> Bool {
        perform { try store.editProject(project.id, name: projectName, color: project.color); editingProject = nil }
    }
    private func cancelEditingOrGoBack() {
        if showingTaskEntry { cancelTaskEntry() }
        else if editingProject != nil || editingTask != nil { editingProject = nil; editingTask = nil }
        else if editingList { editingList = false }
        else { goBack() }
    }
    private func goBack() {
        error = nil; editingList = false; editingProject = nil; editingTask = nil; dragSource = nil; insertion = nil
        cancelTaskEntry()
        if projectEditor { projectEditor = false }
        else if project != nil { selectedProject = nil; newTask = "" }
        else { close() }
    }
    private func moveProject(_ project: WorkProject, direction: Int) {
        guard let index = store.projects.firstIndex(where: { $0.id == project.id }), store.projects.indices.contains(index + direction) else { return }
        perform { try store.moveProject(project.id, relativeTo: store.projects[index + direction].id, after: direction > 0) }
    }
    private func saveProject() {
        perform {
            let id = try store.addProject(projectName, color: projectColor.tagHex)
            selectedProject = id
            if let position = store.projects.firstIndex(where: { $0.id == id }) { projectsExpansion.reveal(itemAt: position, total: store.projects.count) }
            tasksExpansion = ChecklistExpansion(size: 7); cancelTaskEntry()
            projectEditor = false
        }
    }
    private func addTask(_ project: WorkProject) {
        perform {
            let id = try store.addTask(newTask, project: project.id)
            if let updated = store.projects.first(where: { $0.id == project.id }),
               let position = orderedTasks(updated).firstIndex(where: { $0.id == id }) {
                tasksExpansion.reveal(itemAt: position, total: updated.tasks.count)
                newTaskScrollTarget = id
            }
            cancelTaskEntry()
        }
    }
    @discardableResult private func saveTask(_ task: ProjectTask, project: WorkProject) -> Bool {
        perform { try store.renameTask(task.id, project: project.id, title: taskTitle); editingTask = nil }
    }
    private func move(_ task: ProjectTask, project: WorkProject, direction: Int) {
        let tasks = task.completedAt == nil ? project.tasks.filter { $0.completedAt == nil } : project.completedTasks
        guard let index = tasks.firstIndex(where: { $0.id == task.id }), tasks.indices.contains(index + direction) else { return }
        perform {
            if direction < 0 { try store.moveTask(task.id, before: tasks[index - 1].id, project: project.id) }
            else { try store.moveTask(task.id, after: tasks[index + 1].id, project: project.id) }
        }
    }
    @discardableResult private func perform(_ action: () throws -> Void) -> Bool {
        do { try action(); error = nil; return true }
        catch { self.error = error.localizedDescription; return false }
    }
}

private struct ProjectTaskDetails: View {
    @ObservedObject var store: ProjectStore
    @ObservedObject var tracker: ActivityTracker
    let projectID: UUID
    let taskID: UUID
    @Environment(\.dismiss) private var dismiss
    @State private var description: String
    @State private var estimate: Double
    @State private var saveError: String?
    @State private var saved = true
    @State private var editingEstimate = false
    @State private var editingTitle = false
    @State private var titleDraft = ""
    @FocusState private var titleFocused: Bool

    init(store: ProjectStore, tracker: ActivityTracker, projectID: UUID, task: ProjectTask) {
        self.store = store; self.tracker = tracker; self.projectID = projectID; taskID = task.id
        _description = State(initialValue: task.description ?? "")
        _estimate = State(initialValue: task.estimate)
    }

    private var project: WorkProject? { store.projects.first { $0.id == projectID } }
    private var task: ProjectTask? { project?.tasks.first { $0.id == taskID } }
    private var worked: String {
        if let completed = task?.completedWork {
            return completed.seconds.map(ProjectWorkTotals.duration) ?? "Saving…"
        }
        guard let totals = tracker.projectWorkTotals else {
            return tracker.projectWorkNotice == nil ? "Loading…" : "Unavailable"
        }
        return ProjectWorkTotals.duration(totals.tasks[projectID]?[taskID] ?? 0)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Group {
                if editingTitle {
                    TextField("Task title", text: $titleDraft).textFieldStyle(.plain)
                        .focused($titleFocused).onSubmit { _ = saveTitle() }
                        .onExitCommand { editingTitle = false; titleFocused = false; saveError = nil }
                        .accessibilityLabel("Task title")
                } else {
                    Text(task?.title ?? "Task no longer available")
                        .fixedSize(horizontal: false, vertical: true)
                        .onTapGesture(count: 2) {
                            guard let task else { return }
                            titleDraft = task.title; editingTitle = true; titleFocused = true
                        }
                        .accessibilityAction(named: "Rename task") {
                            guard let task else { return }
                            titleDraft = task.title; editingTitle = true; titleFocused = true
                        }
                }
            }.font(.title3.weight(.semibold))
            Text(project?.name ?? "").font(.subheadline).foregroundStyle(.secondary)
            VStack(alignment: .leading, spacing: 6) {
                Text("Description (optional)").font(.callout.weight(.medium))
                TextEditor(text: $description).font(.body).scrollContentBackground(.hidden)
                    .padding(6).frame(height: 110)
                    .background(Color(nsColor: .textBackgroundColor).opacity(0.65), in: RoundedRectangle(cornerRadius: 8))
                    .overlay { RoundedRectangle(cornerRadius: 8).stroke(Color.primary.opacity(0.12)) }
                    .accessibilityLabel("Task description")
            }
            VStack(alignment: .leading, spacing: 6) {
                HStack {
                    Text("Predicted duration").font(.callout.weight(.medium))
                    Spacer()
                    Text("\(estimate.formatted()) FS").monospacedDigit()
                }
                Slider(value: $estimate, in: 0.5...3, step: 0.5) { Text("Predicted Focus Sessions") }
                    onEditingChanged: { editing in editingEstimate = editing; if !editing { save() } }
                    .labelsHidden().accessibilityValue("\(estimate.formatted()) Focus Sessions")
                HStack { Text("0.5 FS"); Spacer(); Text("3 FS") }.font(.caption).foregroundStyle(.secondary)
                Text("1 Focus Session = 1 hour of focused work").font(.caption).foregroundStyle(.secondary)
            }
            Text("Worked: " + worked).font(.callout.monospacedDigit())
            if let saveError {
                HStack {
                    Text(saveError).font(.caption).foregroundStyle(.red)
                    Button("Retry") { save() }
                }
            }
            HStack {
                Text(saveError != nil ? "Not saved" : saved ? "Saved automatically" : "Saving…").font(.caption).foregroundStyle(.secondary)
                Spacer()
                Button("Done", action: close).keyboardShortcut(.defaultAction)
            }
        }
        .padding(24).frame(width: 420)
        .tint(Color(tagHex: project?.color ?? "#168B80"))
        .background {
            ZStack {
                Color(nsColor: .windowBackgroundColor)
                if let project { TagTintBackground(colors: [project.color]) }
            }
        }
        .background(TaskPopupPositioner())
        .interactiveDismissDisabled()
        .onChange(of: titleFocused) { _, focused in
            if !focused, editingTitle { _ = saveTitle() }
        }
        .onExitCommand(perform: close)
        .onChange(of: description) { _, _ in saved = false }
        .onChange(of: estimate) { _, _ in
            saved = false
            if !editingEstimate { save() }
        }
        .task(id: description) {
            do { try await Task.sleep(for: .milliseconds(350)) } catch { return }
            guard !Task.isCancelled else { return }
            save()
        }
    }

    @discardableResult private func save() -> Bool {
        guard let task else { return true }
        do {
            if task.description ?? "" != description || task.estimate != estimate {
                try store.updateTaskDetails(taskID, project: projectID, description: description, estimate: estimate)
            }
            saved = true; saveError = nil
            return true
        } catch {
            saved = false; saveError = "Changes could not be saved. \(error.localizedDescription)"
            return false
        }
    }

    @discardableResult private func saveTitle() -> Bool {
        guard editingTitle else { return true }
        do {
            try store.renameTask(taskID, project: projectID, title: titleDraft)
            editingTitle = false; titleFocused = false; saveError = nil
            return true
        } catch {
            saveError = error.localizedDescription; titleFocused = true
            return false
        }
    }

    private func close() { if saveTitle(), save() { dismiss() } }
}

struct BrowsedProjectTintKey: PreferenceKey {
    static let defaultValue: String? = nil
    static func reduce(value: inout String?, nextValue: () -> String?) { value = nextValue() ?? value }
}

// Keep native task sheets over the original 490-point collector, even when a side panel adds width.
private struct TaskPopupPositioner: NSViewRepresentable {
    func makeNSView(context: Context) -> Probe { Probe() }
    func updateNSView(_ view: Probe, context: Context) { view.schedulePosition() }
    static func dismantleNSView(_ view: Probe, coordinator: ()) { view.stopObserving() }

    final class Probe: NSView {
        private var observers: [NSObjectProtocol] = []
        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            stopObserving()
            guard window != nil else { return }
            for name in [NSWindow.didResizeNotification, NSWindow.didMoveNotification,
                         NSWindow.didBeginSheetNotification, NSWindow.didBecomeKeyNotification] {
                observers.append(NotificationCenter.default.addObserver(forName: name, object: nil, queue: .main) { [weak self] note in
                    MainActor.assumeIsolated {
                        guard let self, let changed = note.object as? NSWindow,
                              changed === self.window || changed === self.window?.sheetParent else { return }
                        self.schedulePosition()
                    }
                })
            }
            schedulePosition()
        }
        func stopObserving() {
            observers.forEach(NotificationCenter.default.removeObserver)
            observers.removeAll()
        }
        func schedulePosition() {
            DispatchQueue.main.async { [weak self] in
                guard let sheet = self?.window, let parent = sheet.sheetParent,
                      let content = parent.contentView else { return }
                let bounds = parent.convertToScreen(content.bounds)
                let origin = NSPoint(x: bounds.minX + min(490, bounds.width) / 2 - sheet.frame.width / 2,
                                     y: bounds.midY - sheet.frame.height / 2)
                if abs(sheet.frame.minX - origin.x) > 0.5 || abs(sheet.frame.minY - origin.y) > 0.5 {
                    sheet.setFrameOrigin(origin)
                }
            }
        }
    }
}
