import SwiftUI
import AppKit

extension Color {
    init(tagHex: String) {
        let value = Int(tagHex.dropFirst(), radix: 16) ?? 0x168B80
        self.init(.sRGB, red: Double((value >> 16) & 255) / 255,
                  green: Double((value >> 8) & 255) / 255, blue: Double(value & 255) / 255, opacity: 1)
    }
    var tagHex: String {
        guard let rgb = NSColor(self).usingColorSpace(.sRGB) else { return SessionTags.palette[0] }
        func channel(_ value: CGFloat) -> Int { Int((min(1, max(0, value)) * 255).rounded()) }
        return String(format: "#%02X%02X%02X", channel(rgb.redComponent), channel(rgb.greenComponent), channel(rgb.blueComponent))
    }
}

// Repeated stops create sharp diagonal boundaries instead of blended colors.
struct TagTintBackground: View {
    let colors: [String]
    var opacity: Double = 0.15
    var body: some View {
        if colors.isEmpty { Color.teal.opacity(0.04).accessibilityHidden(true) }
        else {
            GeometryReader { geometry in
                // Project onto x+y so boundaries stay at 45° even on wide session rows.
                let span = (geometry.size.width + geometry.size.height) / 2
                LinearGradient(stops: colors.enumerated().flatMap { index, hex in
                    [Gradient.Stop(color: Color(tagHex: hex), location: Double(index) / Double(colors.count)),
                     Gradient.Stop(color: Color(tagHex: hex), location: Double(index + 1) / Double(colors.count))]
                }, startPoint: .topLeading,
                   endPoint: UnitPoint(x: span / max(1, geometry.size.width), y: span / max(1, geometry.size.height)))
            }.opacity(opacity).allowsHitTesting(false).accessibilityHidden(true)
        }
    }
}

struct SessionTagChips: View {
    let tags: [String]
    let colors: [String: String]
    var body: some View {
        HStack(spacing: 5) {
            ForEach(Array(tags.prefix(2)), id: \.self) { name in
                HStack(spacing: 4) {
                    Circle().fill(Color(tagHex: colors[name] ?? SessionTags.defaultColor(for: name))).frame(width: 7, height: 7)
                    Text(name).lineLimit(1)
                }.font(.caption).padding(.horizontal, 8).padding(.vertical, 4)
                    .background(Color.primary.opacity(0.06), in: Capsule())
            }
            if tags.count > 2 { Text("+\(tags.count - 2)").font(.caption).foregroundStyle(.secondary) }
        }.help(tags.joined(separator: ", "))
    }
}

// The timer and library use the same direct chip interaction and empty state.
struct SessionTagButton: View {
    let tags: [String]
    let colors: [String: String]
    let action: () -> Void
    var body: some View {
        Button(action: action) {
            if tags.isEmpty {
                Label("Add tags", systemImage: "plus").font(.caption)
                    .padding(.horizontal, 8).padding(.vertical, 4)
                    .background(Color.primary.opacity(0.06), in: Capsule())
            } else { SessionTagChips(tags: tags, colors: colors) }
        }.buttonStyle(.plain)
            .help("Click to change this session's tags and colors")
            .accessibilityLabel(tags.isEmpty ? "Add tags" : "Edit tags: \(tags.joined(separator: ", "))")
    }
}

@MainActor
struct SessionTagEditor: View {
    @ObservedObject var library: SessionTagLibrary
    @Environment(\.dismiss) private var dismiss
    @State private var selection: [String]
    @State private var colors: [String: String]
    @State private var notice: String?
    @State private var search = ""
    @State private var editing: TagEditRequest?
    let managingOnly: Bool
    let save: ([String], [String: String]) throws -> Void

    init(tags: [String], colors: [String: String] = [:], library: SessionTagLibrary? = nil,
         managingOnly: Bool = false, save: @escaping ([String], [String: String]) throws -> Void) {
        self.library = library ?? .shared
        _selection = State(initialValue: tags)
        _colors = State(initialValue: colors)
        self.managingOnly = managingOnly
        self.save = save
    }
    private var available: [String] {
        var seen = Set<String>()
        return (library.names + selection).filter { seen.insert(SessionTags.key($0)).inserted }
    }
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("Tags").font(.title3.weight(.semibold))
                Spacer()
                if !managingOnly { Button("Cancel") { dismiss() }.keyboardShortcut(.cancelAction) }
            }
            if available.count > 6 { TextField("Find a tag", text: $search).textFieldStyle(.roundedBorder) }
            ScrollView {
                VStack(spacing: 4) {
                    ForEach(available.filter { search.isEmpty || $0.localizedCaseInsensitiveContains(search) }, id: \.self) { name in
                        HStack(spacing: 4) {
                            Button {
                                if managingOnly { edit(name) } else { toggle(name) }
                            } label: {
                                HStack(spacing: 10) {
                                    Circle().fill(Color(tagHex: library.color(for: name, saved: colors))).frame(width: 12, height: 12)
                                    Text(name).lineLimit(2).frame(maxWidth: .infinity, alignment: .leading)
                                    if !managingOnly, selection.contains(name) { Image(systemName: "checkmark").font(.caption.weight(.semibold)) }
                                }.padding(9).contentShape(Rectangle())
                            }.buttonStyle(.plain).accessibilityLabel(name)
                                .accessibilityValue(managingOnly ? "Edit tag" : selection.contains(name) ? "Selected" : "Not selected")
                            Menu {
                                Button("Edit name and color…") { edit(name) }
                                if library.names.contains(name) {
                                    Button("Remove from list", role: .destructive) {
                                        do { try library.remove(name); selection.removeAll { $0 == name }; colors.removeValue(forKey: name) }
                                        catch { notice = error.localizedDescription }
                                    }
                                }
                            } label: { Image(systemName: "ellipsis") }
                            .menuStyle(.borderlessButton).frame(width: 24).accessibilityLabel("Options for \(name)")
                        }.background(selection.contains(name) && !managingOnly
                            ? Color(tagHex: library.color(for: name, saved: colors)).opacity(0.1) : Color.clear,
                                     in: RoundedRectangle(cornerRadius: 7))
                    }
                    if available.isEmpty { Text("Create your first tag below.").font(.callout).foregroundStyle(.secondary) }
                }
            }.frame(height: CGFloat(min(max(available.count, 1), 6)) * 42)
            if let message = notice ?? library.notice {
                Text(message).font(.caption).foregroundStyle(.red).fixedSize(horizontal: false, vertical: true)
                if !library.loaded { Button("Reload tag list") { library.reload() } }
            }
            Divider()
            HStack {
                Button { editing = TagEditRequest(name: nil, color: SessionTags.palette[0]) } label: { Label("New tag", systemImage: "plus") }
                    .disabled(!library.loaded)
                if !managingOnly, !selection.isEmpty { Button("Clear") { selection = []; colors = [:]; notice = nil } }
                Spacer()
                Button("Done") {
                    do {
                        if !managingOnly {
                            let valid = try SessionTags.validated(selection)
                            try save(valid, library.resolvedColors(for: valid, saved: colors))
                        }
                        dismiss()
                    } catch { notice = error.localizedDescription }
                }.buttonStyle(.borderedProminent)
            }
        }.padding(18).frame(width: 360).tint(.teal)
        .sheet(item: $editing) { request in
            TagDetailsEditor(name: request.name ?? "", color: request.color, isNew: request.name == nil) { name, color in
                if let old = request.name, library.names.contains(old) {
                    try library.rename(old, to: name, color: color)
                    selection = selection.map { $0 == old ? name : $0 }
                    colors.removeValue(forKey: old)
                } else {
                    guard !library.names.contains(where: { SessionTags.key($0) == SessionTags.key(name) }) else {
                        throw SessionTags.TagError("A tag with that name already exists.")
                    }
                    _ = try library.add(name, color: color)
                    if !managingOnly, selection.count < SessionTags.maximumPerSession { selection.append(name) }
                    if let old = request.name { selection.removeAll { $0 == old } }
                }
                colors[name] = color
                notice = nil
            }
        }
    }
    private func edit(_ name: String) { editing = TagEditRequest(name: name, color: library.color(for: name, saved: colors)) }
    private func toggle(_ name: String) {
        if selection.contains(name) { selection.removeAll { $0 == name } }
        else if selection.count < SessionTags.maximumPerSession { selection.append(name) }
        else { notice = "Choose up to \(SessionTags.maximumPerSession) tags."; return }
        notice = nil
    }
}

private struct TagEditRequest: Identifiable {
    let id = UUID()
    let name: String?
    let color: String
}

struct ManageSessionTagsView: View {
    @ObservedObject var library: SessionTagLibrary = .shared
    var body: some View { SessionTagEditor(tags: [], library: library, managingOnly: true) { _, _ in } }
}

private struct TagDetailsEditor: View {
    @Environment(\.dismiss) private var dismiss
    @State var name: String
    @State var color: String
    let isNew: Bool
    let save: (String, String) throws -> Void
    @State private var notice: String?
    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text(isNew ? "New tag" : "Edit tag").font(.title3.weight(.semibold))
            TextField("Tag name", text: $name).textFieldStyle(.roundedBorder)
            ColorPicker("Color", selection: Binding(get: { Color(tagHex: color) }, set: { color = $0.tagHex }), supportsOpacity: false)
            HStack(spacing: 9) {
                ForEach(SessionTags.palette, id: \.self) { hex in
                    Button { color = hex } label: {
                        Circle().fill(Color(tagHex: hex)).frame(width: 23, height: 23)
                            .overlay { if color == hex { Image(systemName: "checkmark").font(.caption2.bold()).foregroundStyle(.white) } }
                    }.buttonStyle(.plain).accessibilityLabel("Choose color \(hex)")
                }
            }
            if let notice { Text(notice).font(.caption).foregroundStyle(.red) }
            HStack {
                Button("Cancel") { dismiss() }.keyboardShortcut(.cancelAction)
                Spacer()
                Button("Save") {
                    do { try save(SessionTags.name(name), SessionTags.color(color)); dismiss() }
                    catch { notice = error.localizedDescription }
                }.buttonStyle(.borderedProminent).disabled((try? SessionTags.name(name)) == nil)
            }
        }.padding(20).frame(width: 320).tint(.teal)
    }
}
