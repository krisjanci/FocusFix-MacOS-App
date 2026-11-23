// Isolated synthetic preview: this stub never links the recorder or account services.
import SwiftUI
import AppKit

@MainActor final class ActivityTracker: ObservableObject {
    @Published var isWorking = false
    @Published var declaredWorkSeconds = 1024.0
    @Published var workAssignment = WorkAssignment.none
    func workOn(project: WorkProject?, task: ProjectTask? = nil) throws {
        isWorking = true
        workAssignment = WorkAssignment(projectID: project?.id, projectName: project?.name,
            projectColor: project?.color, taskID: task?.id, taskTitle: task?.title)
    }
    func reconcileWorkAssignment(projects: [WorkProject]) {
        guard isWorking, let id = workAssignment.projectID else { return }
        let project = projects.first { $0.id == id }
        let task = project?.tasks.first { $0.id == workAssignment.taskID && $0.completedAt == nil }
        try? workOn(project: project, task: task)
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
        try! store.completeTask(store.projects[0].tasks.last!.id, project: id, at: Date().addingTimeInterval(-10))
        _ = try! store.addProject("CS 600", color: "#7963CF")
        return store
    }()
}

struct ProjectsPreview: View {
    @StateObject private var tracker = ActivityTracker()
    @State private var dark = false
    @State private var panel = false
    @State private var tasks = true
    var body: some View {
        HStack(spacing: 0) {
            VStack(alignment: .leading, spacing: 20) {
                HStack { Text("FocusFix").font(.title2.weight(.semibold)); Spacer(); Button("Appearance") { dark.toggle() } }
                HStack { Text("Synthetic preview · no recording").font(.caption).foregroundStyle(.secondary); Spacer() }
                ZStack {
                    VStack {
                        Text("17:04").font(.system(size: 46, weight: .light, design: .rounded))
                        Button { tasks = true } label: { Label("Task", systemImage: "doc.text") }
                        Text(tracker.workAssignment.summary).font(.caption)
                    }.frame(maxWidth: .infinity, maxHeight: .infinity)
                        .background(TagTintBackground(colors: [tracker.workAssignment.projectColor].compactMap { $0 }))
                        .clipShape(RoundedRectangle(cornerRadius: 16))
                        .opacity(tasks ? 0 : 1).allowsHitTesting(!tasks)
                    ProjectsView(store: PreviewProjects.store, tracker: tracker, close: { tasks = false })
                        .opacity(tasks ? 1 : 0).allowsHitTesting(tasks)
                }.frame(height: 350)
                HStack {
                    Button(tracker.isWorking ? "End work" : "Start work") { tracker.isWorking.toggle(); tracker.workAssignment = .none }
                        .buttonStyle(.borderedProminent).tint(.teal).frame(maxWidth: .infinity)
                    Text("Uses system Reduce Motion").font(.caption).foregroundStyle(.secondary)
                }
                HStack { Button("Groups") { panel.toggle() }; Spacer(); Button("Analytics") { panel.toggle() } }
            }.padding(30).frame(width: 490)
            if panel { Divider(); Text("Independent side panel").frame(width: 280) }
        }.preferredColorScheme(dark ? .dark : .light)
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
