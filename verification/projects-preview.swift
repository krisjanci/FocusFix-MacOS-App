// Isolated synthetic preview: this stub never links the recorder or account services.
import SwiftUI
import AppKit

@MainActor final class ActivityTracker: ObservableObject {
    @Published var isWorking = false
    @Published var declaredWorkSeconds = 1024.0
    @Published var workAssignment = WorkAssignment.none
    @Published var projectWorkTotals: ProjectWorkTotals? = {
        var totals = ProjectWorkTotals()
        for project in PreviewProjects.store.projects {
            totals.projects[project.id] = 9720
            for task in project.tasks { totals.tasks[project.id, default: [:]][task.id] = 2700 }
        }
        return totals
    }()
    let projectWorkNotice: String? = nil
    func refreshSessions() { }
    let needsPermission = false
    let hasError = false
    let message = ""
    func requestPermission() { }
    func workOn(project: WorkProject?, task: ProjectTask? = nil, promoteProject: Bool = true) throws {
        isWorking = true
        workAssignment = WorkAssignment(projectID: project?.id, projectName: project?.name,
            projectColor: project?.color, taskID: task?.id, taskTitle: task?.title)
        if promoteProject, let project { try PreviewProjects.store.recordWork(on: project.id) }
    }
    func finishCurrentTask() {
        guard isWorking, let projectID = workAssignment.projectID, let task = workAssignment.taskID,
              let project = PreviewProjects.store.projects.first(where: { $0.id == projectID }) else { return }
        let finish = Date()
        let summary = CompletedTaskWork(projectID: projectID, projectName: project.name,
            taskTitle: workAssignment.taskTitle ?? "Task", finishedAt: finish, seconds: 90)
        do {
            try PreviewProjects.store.completeTask(task, project: projectID, at: finish, work: summary)
            workAssignment = .none
        } catch { }
    }
    func reconcileWorkAssignment(projects: [WorkProject]) {
        guard isWorking, let id = workAssignment.projectID else { return }
        let project = projects.first { $0.id == id }
        let task = project?.tasks.first { $0.id == workAssignment.taskID && $0.completedAt == nil }
        try? workOn(project: project, task: task, promoteProject: false)
    }
}

@MainActor enum PreviewProjects {
    static let root = FileManager.default.temporaryDirectory.appendingPathComponent("projects-preview-\(UUID())")
    static let store: ProjectStore = {
        let store = ProjectStore(file: root.appendingPathComponent("projects.json"))
        let id = try! store.addProject("FocusFix", color: "#168B80")
        for title in ["Design the new task checklist", "Review session time assignments", "Polish the completion animation", "Test keyboard navigation", "Prepare the next release"] {
            try! store.addTask(title, project: id)
        }
        let first = store.projects.first { $0.id == id }!.tasks[0].id
        try! store.updateTaskDetails(first, project: id, description: "Explore the task layout and interactions.", estimate: 2.5)
        try! store.completeTask(store.projects.first { $0.id == id }!.tasks.last!.id, project: id, at: Date().addingTimeInterval(-10))
        for index in 1...5 { try! store.addTask("Extra task \(index)", project: id) }
        _ = try! store.addProject("CS 600", color: "#7963CF")
        for index in 1...7 { _ = try! store.addProject("Extra project \(index)", color: SessionTags.palette[index % SessionTags.palette.count]) }
        return store
    }()
}

struct ProjectsPreview: View {
    @StateObject private var tracker = ActivityTracker()
    @State private var dark = false
    @State private var reducedMotion = false
    @State private var panel = false
    @State private var tasks = true
    @State private var showingGuide = false
    var body: some View {
        HStack(spacing: 0) {
            VStack(alignment: .leading, spacing: 20) {
                VStack(alignment: .leading, spacing: 20) {
                    HStack { Text("FocusFix").font(.title2.weight(.semibold)); Spacer(); Button("Placement guide") { showingGuide = true }; Button("Appearance") { dark.toggle() } }
                    Text("Synthetic preview · no recording").font(.caption).foregroundStyle(.secondary)
                    VStack {
                        Text("17:04").font(.system(size: 46, weight: .light, design: .rounded))
                        Button { tasks = true } label: { Label("Task", systemImage: "doc.text") }
                        Label("Work target", systemImage: "scope").font(.caption)
                            .padding(.horizontal, 8).padding(.vertical, 4)
                            .background(Color.primary.opacity(0.06), in: Capsule())
                        HStack(spacing: 8) {
                            Text(tracker.workAssignment.summary).font(.caption).lineLimit(2)
                            if tracker.isWorking, tracker.workAssignment.taskID != nil {
                                Button { tracker.finishCurrentTask() } label: {
                                    Label("Finished task", systemImage: "checkmark").font(.caption)
                                        .padding(.horizontal, 8).padding(.vertical, 4).foregroundStyle(.green)
                                        .background(Color.green.opacity(0.06), in: Capsule())
                                        .overlay { Capsule().stroke(Color.green.opacity(0.75), lineWidth: 1) }
                                }.buttonStyle(.plain)
                            }
                        }
                    }.frame(maxWidth: .infinity).frame(height: 350)
                        .background(TagTintBackground(colors: [tracker.workAssignment.projectColor].compactMap { $0 }))
                        .clipShape(RoundedRectangle(cornerRadius: 16))
                    HStack {
                        Button(tracker.isWorking ? "End work" : "Start work") { tracker.isWorking.toggle(); tracker.workAssignment = .none }
                            .buttonStyle(.borderedProminent).tint(.teal).frame(maxWidth: .infinity)
                        Toggle("Reduce Motion", isOn: $reducedMotion).toggleStyle(.checkbox)
                    }
                }
                .opacity(tasks ? 0 : 1).allowsHitTesting(!tasks).accessibilityHidden(tasks)
                .overlay {
                    ProjectsView(store: PreviewProjects.store, tracker: tracker, close: { tasks = false }, reduceMotionOverride: reducedMotion)
                        .opacity(tasks ? 1 : 0).allowsHitTesting(tasks).accessibilityHidden(!tasks)
                }
                HStack { Button("Groups") { panel.toggle() }; Spacer(); Button("Analytics") { panel.toggle() } }
            }.padding(30).frame(width: 490)
            if panel { Divider(); Text("Independent side panel").frame(width: 280) }
        }.preferredColorScheme(dark ? .dark : .light)
            .overlay {
                if showingGuide { ReorderingGuidePreview(close: { showingGuide = false }).padding(30).background(Color(nsColor: .windowBackgroundColor)) }
            }
    }
}

// Deterministic hover fixture renders the production row modifier before any drop.
private struct ReorderingGuidePreview: View {
    let close: () -> Void
    private static let a = UUID(uuidString: "00000000-0000-4000-8000-000000000001")!
    private static let b = UUID(uuidString: "00000000-0000-4000-8000-000000000002")!
    @State private var source: ChecklistDragItem? = .project(a)
    @State private var insertion = ChecklistInsertion(source: .project(a), target: .project(b), y: 0, rowHeight: 44)
    @State private var lastDrop = "No drop yet"
    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            HStack { Text("Insertion guide preview").font(.title2); Spacer(); Button("Close", action: close) }
            Text("The actual drag-row modifier renders the placement line before release.").font(.caption).foregroundStyle(.secondary)
            VStack(spacing: 0) {
                Text("Dragged row").frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
                    .modifier(ChecklistReorderRow(item: .project(Self.a), source: $source, insertion: $insertion) { _, after in lastDrop = "Dropped \(after ? "after" : "before") dragged row" })
                Text("Target row").frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
                    .modifier(ChecklistReorderRow(item: .project(Self.b), source: $source, insertion: $insertion) { _, after in lastDrop = "Dropped \(after ? "after" : "before") target row" })
                Text("Next row").frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
            }
            HStack {
                Button("Before target") { source = .project(Self.a); insertion = ChecklistInsertion(source: source, target: .project(Self.b), y: 0, rowHeight: 44) }
                Button("After target") { source = .project(Self.a); insertion = ChecklistInsertion(source: source, target: .project(Self.b), y: 44, rowHeight: 44) }
                Button("Cancel drag") { source = nil; insertion = nil }
            }
            Text(lastDrop).font(.caption)
            Text(source == nil ? "No active drag" : "Active drag: \(source!.token)").font(.caption)
            Spacer()
        }.frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

final class ProjectsPreviewDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.regular); NSApp.activate(ignoringOtherApps: true)
    }
    func applicationWillTerminate(_ notification: Notification) { try? FileManager.default.removeItem(at: PreviewProjects.root) }
}
@main struct ProjectsPreviewApp: App {
    @NSApplicationDelegateAdaptor(ProjectsPreviewDelegate.self) private var delegate
    var body: some Scene { WindowGroup("FocusFix Projects Preview") { ProjectsPreview() }.windowResizability(.contentSize) }
}
