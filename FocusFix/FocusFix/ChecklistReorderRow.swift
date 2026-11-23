import SwiftUI
import UniformTypeIdentifiers

private let checklistDragType = UTType(exportedAs: "io.github.krisjanci.focusfix.checklist-item", conformingTo: .data)

struct ChecklistReorderRow: ViewModifier {
    let item: ChecklistDragItem
    var enabled = true
    @Binding var source: ChecklistDragItem?
    @Binding var insertion: ChecklistInsertion?
    let move: (ChecklistDragItem, Bool) -> Void
    @State private var height: CGFloat = 44
    private let teal = Color(red: 0.02, green: 0.60, blue: 0.54)

    @ViewBuilder func body(content: Content) -> some View {
        if enabled {
            content
                .contentShape(Rectangle())
                .background(GeometryReader { geometry in
                    Color.clear.onAppear { height = geometry.size.height }
                        .onChange(of: geometry.size.height) { _, value in height = value }
                })
                .overlay(alignment: insertion?.after == true ? .bottom : .top) {
                    if insertion?.target == item {
                        HStack(spacing: 0) {
                            Circle().fill(teal).frame(width: 6, height: 6)
                            Rectangle().fill(teal).frame(height: 2)
                        }
                        .accessibilityHidden(true).allowsHitTesting(false)
                    }
                }
                .onDrag {
                    source = item; insertion = nil
                    let provider = NSItemProvider()
                    provider.registerDataRepresentation(forTypeIdentifier: checklistDragType.identifier, visibility: .all) { completion in
                        completion(Data(item.token.utf8), nil); return nil
                    }
                    return provider
                }
                .onDrop(of: [checklistDragType], delegate: ChecklistRowDropDelegate(item: item, height: height,
                    source: $source, insertion: $insertion, move: move))
        } else { content }
    }
}

private struct ChecklistRowDropDelegate: DropDelegate {
    let item: ChecklistDragItem
    let height: CGFloat
    @Binding var source: ChecklistDragItem?
    @Binding var insertion: ChecklistInsertion?
    let move: (ChecklistDragItem, Bool) -> Void

    func validateDrop(info: DropInfo) -> Bool {
        source?.canMove(to: item) == true && info.hasItemsConforming(to: [checklistDragType])
    }
    func dropEntered(info: DropInfo) { update(info) }
    func dropUpdated(info: DropInfo) -> DropProposal? {
        update(info)
        return DropProposal(operation: validateDrop(info: info) ? .move : .forbidden)
    }
    func dropExited(info: DropInfo) {
        if insertion?.target == item { insertion = nil }
    }
    func performDrop(info: DropInfo) -> Bool {
        defer { source = nil; insertion = nil }
        guard validateDrop(info: info), let dragging = source,
              let placement = ChecklistInsertion(source: dragging, target: item, y: info.location.y, rowHeight: height),
              let provider = info.itemProviders(for: [checklistDragType]).first else { return false }
        provider.loadDataRepresentation(forTypeIdentifier: checklistDragType.identifier) { data, _ in
            guard data == Data(dragging.token.utf8) else { return }
            Task { @MainActor in move(dragging, placement.after) }
        }
        return true
    }
    private func update(_ info: DropInfo) {
        guard validateDrop(info: info) else { return }
        insertion = ChecklistInsertion(source: source, target: item, y: info.location.y, rowHeight: height)
    }
}
