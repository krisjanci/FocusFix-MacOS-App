import Foundation

// Expansion always retains the beginning of the checklist.
nonisolated struct ChecklistExpansion: Equatable {
    let size: Int
    private(set) var batches = 1

    init(size: Int) { precondition(size > 0); self.size = size }
    private func maximumBatches(total: Int) -> Int { max(1, (max(0, total) - 1) / size + 1) }
    func range(total: Int) -> Range<Int> {
        let count = max(0, total)
        let visible = batches >= maximumBatches(total: count) ? count : batches * size
        return 0..<visible
    }
    func hasMore(total: Int) -> Bool { range(total: total).upperBound < max(0, total) }
    var isExpanded: Bool { batches > 1 }
    mutating func expand(total: Int) {
        clamp(total: total)
        if hasMore(total: total) { batches += 1 }
    }
    mutating func collapse() { batches = 1 }
    mutating func clamp(total: Int) { batches = min(batches, maximumBatches(total: total)) }
    mutating func reveal(itemAt position: Int, total: Int) {
        let position = max(0, min(position, max(0, max(0, total) - 1)))
        batches = max(batches, position / size + 1)
    }

    // Base rows fill the viewport; expansion keeps their height and adds content below.
    func rowHeight(available: Double, reserved: Double, divider: Double = 0) -> Double {
        max(40, (available - reserved) / Double(size) - divider)
    }
}
