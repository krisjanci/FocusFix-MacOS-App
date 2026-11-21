import SwiftUI

struct SessionConditionSummary: View {
    let conditions: [SessionCondition]
    var body: some View {
        ConditionChipLayout(spacing: 5) {
            ForEach(conditions) { value in
                Text("\(value.category): \(value.label)")
                    .font(.caption).foregroundStyle(.secondary)
                    .padding(.horizontal, 8).padding(.vertical, 4)
                    .background(Color.primary.opacity(0.06), in: Capsule())
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }
}

@MainActor
struct SessionConditionEditor: View {
    @ObservedObject var library: SessionConditionLibrary
    @Environment(\.dismiss) private var dismiss
    @State private var selection: [SessionCondition]
    @State private var editing = false
    @State private var notice: String?
    @State private var naming: ConditionNameRequest?
    let confirmationTitle: String
    let save: ([SessionCondition]) throws -> Void

    init(conditions: [SessionCondition], library: SessionConditionLibrary? = nil,
         confirmationTitle: String = "Done", save: @escaping ([SessionCondition]) throws -> Void) {
        self.library = library ?? .shared
        _selection = State(initialValue: conditions)
        self.confirmationTitle = confirmationTitle
        self.save = save
    }

    private var unavailable: [SessionCondition] {
        selection.filter { value in
            !library.categories.contains { category in
                category.id == value.categoryID && category.labels.contains { $0.id == value.labelID }
            }
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                Text("Conditions").font(.system(size: 28, weight: .bold, design: .rounded))
                Spacer()
                Button(editing ? "Done editing" : "Edit") { editing.toggle() }
                    .buttonPressFeedback().buttonStyle(.plain)
                    .font(.callout.weight(.semibold)).foregroundStyle(.teal)
                    .padding(.horizontal, 12).padding(.vertical, 7)
                    .background(.teal.opacity(0.08), in: Capsule())
            }
            Text("Choose one label in each category. All are optional.")
                .font(.callout).foregroundStyle(.secondary)
            ScrollView {
                VStack(alignment: .leading, spacing: 24) {
                    ForEach(library.categories) { category in
                        categorySection(category)
                    }
                    if library.categories.isEmpty {
                        Text("Choose Edit to add categories like place, music, or surroundings.").foregroundStyle(.secondary)
                    }
                    if !unavailable.isEmpty {
                        VStack(alignment: .leading, spacing: 8) {
                            Text("Saved conditions").font(.headline)
                            Text("These labels are no longer in your reusable list.").font(.caption).foregroundStyle(.secondary)
                            ForEach(unavailable) { value in
                                HStack {
                                    SessionConditionSummary(conditions: [value])
                                    Spacer()
                                    Button("Clear") { selection.removeAll { $0.categoryID == value.categoryID } }
                                        .buttonPressFeedback()
                                }
                            }
                        }
                    }
                }.padding(.vertical, 4)
            }.frame(height: 350)
            if let message = notice ?? library.notice {
                Text(message).font(.caption).foregroundStyle(.red)
            }
            if !library.loaded { Button("Reload condition list") { library.reload() }.buttonPressFeedback() }
            if editing {
                Button { naming = ConditionNameRequest() } label: {
                    Image(systemName: "plus.circle")
                        .font(.system(size: 22, weight: .regular))
                        .frame(width: 32, height: 32).contentShape(Circle())
                }.buttonPressFeedback().buttonStyle(.plain).foregroundStyle(.teal)
                    .disabled(!library.loaded)
                    .accessibilityLabel("Add category").help("Add category")
            }
            Divider()
            HStack {
                Button("Cancel") { dismiss() }.buttonPressFeedback().keyboardShortcut(.cancelAction)
                if !selection.isEmpty { Button("Clear all") { selection = [] }.buttonPressFeedback() }
                Spacer()
                Button(confirmationTitle) {
                    do { try save(SessionConditions.validated(selection)); dismiss() }
                    catch { notice = error.localizedDescription }
                }.buttonPressFeedback().buttonStyle(.borderedProminent)
            }
        }.padding(24).frame(width: 430).tint(.teal)
        .sheet(item: $naming) { request in
            ConditionNameEditor(request: request) { name in
                if let categoryID = request.categoryID {
                    try library.saveLabel(categoryID: categoryID, id: request.labelID, name: name)
                } else { try library.saveCategory(id: request.existingCategoryID, name: name) }
            }
        }
    }

    private func categorySection(_ category: ConditionCategory) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text(category.name).font(.system(size: 17, weight: .semibold))
                Spacer()
                if editing {
                    Menu {
                        Button("Rename category…") {
                            naming = ConditionNameRequest(existingCategoryID: category.id, name: category.name)
                        }
                        Button("Remove category from list", role: .destructive) {
                            perform { try library.removeCategory(category.id) }
                        }
                    } label: { Image(systemName: "ellipsis") }
                        .menuStyle(.borderlessButton).menuIndicator(.hidden)
                        .frame(width: 28, height: 28)
                        .background(Color.primary.opacity(0.04), in: Circle())
                        .accessibilityLabel("Edit \(category.name)").disabled(!library.loaded)
                }
            }
            ConditionChipLayout(spacing: 8) {
                ForEach(category.labels) { label in
                    if editing, label.id == category.labels.last?.id {
                        HStack(spacing: 8) {
                            conditionOption(label, category: category)
                            addLabelButton(category)
                        }
                    } else {
                        conditionOption(label, category: category)
                    }
                }
                if editing, category.labels.isEmpty { addLabelButton(category) }
            }
        }
    }

    private func conditionOption(_ label: ConditionLabel, category: ConditionCategory) -> some View {
        let selected = selection.contains { $0.categoryID == category.id && $0.labelID == label.id }
        HStack(spacing: 2) {
            Button {
                selection.removeAll { $0.categoryID == category.id }
                if !selected {
                    guard selection.count < 20 else { notice = "Choose up to 20 categories."; return }
                    selection.append(SessionCondition(categoryID: category.id, labelID: label.id,
                                                      category: category.name, label: label.name))
                }
                notice = nil
            } label: {
                HStack(spacing: 4) {
                    if selected { Image(systemName: "checkmark").font(.caption2.bold()) }
                    Text(label.name).fixedSize(horizontal: false, vertical: true)
                }.font(.callout.weight(selected ? .medium : .regular))
                    .padding(.horizontal, 12).padding(.vertical, 8)
                    .foregroundStyle(selected ? Color.teal : Color.primary)
                    .background(selected ? Color.teal.opacity(0.10) : Color.primary.opacity(0.025), in: Capsule())
                    .overlay {
                        Capsule().strokeBorder(selected ? Color.teal.opacity(0.65) : Color.primary.opacity(0.14),
                                               lineWidth: selected ? 1.5 : 1)
                    }
            }.buttonStyle(.plain).buttonPressFeedback()
                .accessibilityLabel("\(category.name): \(label.name)")
                .accessibilityValue(selected ? "Selected" : "Not selected")
            if editing {
                Menu {
                    Button("Rename label…") {
                        naming = ConditionNameRequest(categoryID: category.id, labelID: label.id, name: label.name)
                    }
                    Button("Remove label from list", role: .destructive) {
                        perform { try library.removeLabel(label.id, categoryID: category.id) }
                    }
                } label: { Image(systemName: "ellipsis") }
                    .menuStyle(.borderlessButton).menuIndicator(.hidden).frame(width: 20)
                    .accessibilityLabel("Edit \(label.name)").disabled(!library.loaded)
            }
        }
    }

    private func addLabelButton(_ category: ConditionCategory) -> some View {
        Button { naming = ConditionNameRequest(categoryID: category.id) } label: {
            Image(systemName: "plus.circle")
                .font(.system(size: 22, weight: .regular))
                .frame(width: 32, height: 32).contentShape(Circle())
        }.buttonPressFeedback().buttonStyle(.plain).foregroundStyle(.teal)
            .disabled(!library.loaded)
            .accessibilityLabel("Add label to \(category.name)")
            .help("Add label to \(category.name)")
    }

    private func perform(_ action: () throws -> Void) {
        do { try action(); notice = nil } catch { notice = error.localizedDescription }
    }
}

private struct ConditionNameRequest: Identifiable {
    let id = UUID()
    var categoryID: UUID?
    var labelID: UUID?
    var existingCategoryID: UUID?
    var name = ""
    var title: String {
        let kind = categoryID == nil ? "category" : "label"
        return "\(name.isEmpty ? "New" : "Rename") \(kind)"
    }
}

private struct ConditionNameEditor: View {
    let request: ConditionNameRequest
    let save: (String) throws -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var name: String
    @State private var notice: String?
    init(request: ConditionNameRequest, save: @escaping (String) throws -> Void) {
        self.request = request; self.save = save
        _name = State(initialValue: request.name)
    }
    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text(request.title).font(.headline)
            TextField("Name", text: $name).textFieldStyle(.roundedBorder)
            if let notice { Text(notice).font(.caption).foregroundStyle(.red) }
            HStack {
                Button("Cancel") { dismiss() }.buttonPressFeedback().keyboardShortcut(.cancelAction)
                Spacer()
                Button("Save") {
                    do { try save(SessionTags.name(name)); dismiss() }
                    catch { notice = error.localizedDescription }
                }.buttonPressFeedback().buttonStyle(.borderedProminent).keyboardShortcut(.defaultAction)
                    .disabled((try? SessionTags.name(name)) == nil)
            }
        }.padding(20).frame(width: 320).tint(.teal)
    }
}

// Measure each chip at its intrinsic width, constraining only oversized labels.
// Placement uses the same sizes so compact chips sit together instead of filling columns.
struct ConditionChipLayout: Layout {
    var spacing: CGFloat = 8
    private struct Placement {
        let point: CGPoint
        let size: CGSize
    }
    private func arrangement(_ subviews: Subviews, width: CGFloat) -> (CGSize, [Placement]) {
        let width = max(0, width)
        var placements: [Placement] = []
        var x: CGFloat = 0
        var y: CGFloat = 0
        var rowHeight: CGFloat = 0
        var usedWidth: CGFloat = 0
        for view in subviews {
            let ideal = view.sizeThatFits(.unspecified)
            let size = ideal.width <= width ? ideal : view.sizeThatFits(ProposedViewSize(width: width, height: nil))
            if x > 0 && x + size.width > width {
                y += rowHeight + spacing; x = 0; rowHeight = 0
            }
            placements.append(Placement(point: CGPoint(x: x, y: y), size: size))
            usedWidth = max(usedWidth, x + size.width)
            x += size.width + spacing
            rowHeight = max(rowHeight, size.height)
        }
        return (CGSize(width: usedWidth, height: y + rowHeight), placements)
    }
    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        arrangement(subviews, width: proposal.width ?? 430).0
    }
    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        let placements = arrangement(subviews, width: bounds.width).1
        for (view, placement) in zip(subviews, placements) {
            view.place(at: CGPoint(x: bounds.minX + placement.point.x, y: bounds.minY + placement.point.y),
                       proposal: ProposedViewSize(placement.size))
        }
    }
}
