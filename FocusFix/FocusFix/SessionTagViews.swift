import SwiftUI

@MainActor
struct SessionTagEditor: View {
    @ObservedObject var library: SessionTagLibrary
    @Environment(\.dismiss) private var dismiss
    @State private var selection: [String]
    @State private var notice: String?
    @State private var managing = false
    let save: ([String]) throws -> Void

    init(tags: [String], library: SessionTagLibrary? = nil, save: @escaping ([String]) throws -> Void) {
        self.library = library ?? .shared
        _selection = State(initialValue: tags)
        self.save = save
    }

    private var available: [String] {
        var seen = Set<String>()
        // Keep older labels editable even after they have been removed/renamed in the library.
        return (library.names + selection).filter { seen.insert(SessionTags.key($0)).inserted }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                Text("Session tags").font(.title2.weight(.semibold))
                Spacer()
                Button("Manage tags…") { managing = true }
            }
            Text("Choose any that fit. Tags are optional and included when you export this session.")
                .font(.callout).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
            ScrollView {
                VStack(alignment: .leading, spacing: 12) {
                    ForEach(available, id: \.self) { name in
                        Toggle(name, isOn: Binding(get: {
                            selection.contains { SessionTags.key($0) == SessionTags.key(name) }
                        }, set: { enabled in
                            if enabled {
                                guard selection.count < SessionTags.maximumPerSession else {
                                    notice = "Choose up to \(SessionTags.maximumPerSession) tags."
                                    return
                                }
                                selection.append(name)
                            } else { selection.removeAll { SessionTags.key($0) == SessionTags.key(name) } }
                            notice = nil
                        })).toggleStyle(.checkbox)
                    }
                }.frame(maxWidth: .infinity, alignment: .leading).padding(4)
            }.frame(height: 240)
            TagCreationRow(library: library) { name in
                if selection.count < SessionTags.maximumPerSession,
                   !selection.contains(where: { SessionTags.key($0) == SessionTags.key(name) }) {
                    selection.append(name)
                }
            }
            TagLibraryNotice(library: library)
            if let notice { Text(notice).font(.caption).foregroundStyle(.red) }
            HStack {
                Button("Cancel") { dismiss() }.keyboardShortcut(.cancelAction)
                Button("Clear selection") { selection = []; notice = nil }.disabled(selection.isEmpty)
                Spacer()
                Button("Save tags") {
                    do {
                        try save(SessionTags.validated(selection))
                        dismiss()
                    } catch { notice = error.localizedDescription }
                }.buttonStyle(.borderedProminent)
            }
        }.padding(24).frame(width: 460).tint(.teal)
        .sheet(isPresented: $managing) { ManageSessionTagsView(library: library) }
    }
}

struct ManageSessionTagsView: View {
    @ObservedObject var library: SessionTagLibrary = .shared
    @Environment(\.dismiss) private var dismiss
    @State private var editing: String?
    @State private var replacement = ""
    @State private var notice: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Manage tags").font(.title2.weight(.semibold))
            Text("This list is remembered on this Mac. Renaming or removing a tag changes the list; saved sessions keep their labels until you edit their tags.")
                .font(.callout).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
            ScrollView {
                VStack(alignment: .leading, spacing: 12) {
                    ForEach(library.names, id: \.self) { name in
                        HStack {
                            if editing == name {
                                TextField("Tag name", text: $replacement).textFieldStyle(.roundedBorder)
                                Button("Save") {
                                    do { try library.rename(name, to: replacement); editing = nil; notice = nil }
                                    catch { notice = error.localizedDescription }
                                }
                                Button("Cancel") { editing = nil; notice = nil }
                            } else {
                                Text(name).frame(maxWidth: .infinity, alignment: .leading)
                                Button("Rename") { editing = name; replacement = name; notice = nil }
                                    .accessibilityLabel("Rename \(name)")
                                Button(role: .destructive) {
                                    do { try library.remove(name); notice = nil }
                                    catch { notice = error.localizedDescription }
                                } label: { Image(systemName: "trash") }
                                    .accessibilityLabel("Remove \(name) from tag list")
                            }
                        }
                    }
                    if library.names.isEmpty { Text("Add a tag below to start your list.").foregroundStyle(.secondary) }
                }.padding(4).disabled(!library.loaded)
            }.frame(height: 280)
            TagCreationRow(library: library) { _ in }
            TagLibraryNotice(library: library)
            if let notice { Text(notice).font(.caption).foregroundStyle(.red) }
            HStack { Spacer(); Button("Done") { dismiss() }.keyboardShortcut(.cancelAction) }
        }.padding(24).frame(width: 500).tint(.teal)
    }
}

private struct TagCreationRow: View {
    @ObservedObject var library: SessionTagLibrary
    let created: (String) -> Void
    @State private var name = ""
    @State private var notice: String?
    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                TextField("New tag (up to 40 characters)", text: $name)
                    .textFieldStyle(.roundedBorder).accessibilityLabel("New tag name")
                    .onSubmit { add() }
                Button("Add tag") { add() }
                    .disabled(!library.loaded || (try? SessionTags.name(name)) == nil)
            }
            if let notice { Text(notice).font(.caption).foregroundStyle(.red) }
        }
    }
    private func add() {
        do { created(try library.add(name)); name = ""; notice = nil }
        catch { notice = error.localizedDescription }
    }
}

private struct TagLibraryNotice: View {
    @ObservedObject var library: SessionTagLibrary
    var body: some View {
        if let notice = library.notice {
            Text(notice).font(.caption).foregroundStyle(.secondary)
            Button("Reload tag list") { library.reload() }
        }
    }
}
