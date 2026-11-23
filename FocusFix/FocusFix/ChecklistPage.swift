import Foundation

// Paging keeps the checklist compact without losing access to any saved rows.
nonisolated struct ChecklistPage: Equatable {
    let size: Int
    private(set) var index = 0

    init(size: Int) {
        precondition(size > 0)
        self.size = size
    }
    private func validIndex(total: Int) -> Int { min(index, max(0, (max(0, total) - 1) / size)) }
    func range(total: Int) -> Range<Int> {
        let count = max(0, total), start = validIndex(total: total) * size
        return start..<(start + min(size, count - start))
    }
    func hasNext(total: Int) -> Bool { range(total: total).upperBound < max(0, total) }
    func hasPrevious(total: Int) -> Bool { validIndex(total: total) > 0 }
    mutating func next(total: Int) { index = min(validIndex(total: total) + 1, max(0, (max(0, total) - 1) / size)) }
    mutating func previous(total: Int) { index = max(0, validIndex(total: total) - 1) }
    mutating func clamp(total: Int) { index = validIndex(total: total) }
    mutating func reveal(itemAt position: Int, total: Int) {
        index = max(0, min(position, max(0, total - 1))) / size
    }
}
