import SwiftUI
import UniformTypeIdentifiers

// Standard UTF-8 transport works across AppKit drag sessions; only matching local UUID tokens can move rows.
private let checklistDragType = ChecklistDragPayload.type

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
                .checklistPressFeedback(dragging: source == item) {
                    // Let AppKit deliver performDrop before clearing the local payload.
                    // The same cleanup handles releases outside any accepted target.
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                        if NSEvent.pressedMouseButtons & 1 == 0, source == item { source = nil; insertion = nil }
                    }
                }
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
                    return ChecklistDragPayload.provider(for: item)
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
            guard ChecklistDragPayload.matches(data, source: dragging) else { return }
            Task { @MainActor in move(dragging, placement.after) }
        }
        return true
    }
    private func update(_ info: DropInfo) {
        guard validateDrop(info: info) else { return }
        insertion = ChecklistInsertion(source: source, target: item, y: info.location.y, rowHeight: height)
    }
}
