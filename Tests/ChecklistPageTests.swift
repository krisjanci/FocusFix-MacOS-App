import Foundation

@main struct ChecklistPageTests {
    static func main() {
        for size in [8, 7] {
            for total in [0, size - 1, size, size + 1, size * 2, size * 2 + 1, 97] {
                var list = ChecklistExpansion(size: size)
                var previous = list.range(total: total)
                precondition(previous == 0..<min(size, total))
                while list.hasMore(total: total) {
                    list.expand(total: total)
                    let visible = list.range(total: total)
                    precondition(visible.lowerBound == 0 && visible.upperBound > previous.upperBound)
                    precondition(visible.upperBound == min(total, previous.upperBound + size))
                    precondition(Set(previous).isSubset(of: Set(visible)), "Expanding must retain every existing row")
                    previous = visible
                }
                precondition(previous == 0..<total)
                let end = list
                list.expand(total: total)
                precondition(list == end)
                list.collapse()
                precondition(!list.isExpanded && list.range(total: total) == 0..<min(size, total))
            }
        }
        var tasks = ChecklistExpansion(size: 7)
        tasks.reveal(itemAt: 8, total: 10)
        precondition(tasks.range(total: 10) == 0..<10)
        tasks.reveal(itemAt: 0, total: 10)
        precondition(tasks.range(total: 10) == 0..<10, "Revealing a row must not hide already revealed rows")
        tasks.clamp(total: 6)
        precondition(!tasks.isExpanded && tasks.range(total: 6) == 0..<6)
        precondition(tasks.range(total: Int.min).isEmpty)
        tasks.reveal(itemAt: Int.max, total: Int.max)
        precondition(tasks.range(total: Int.max) == 0..<Int.max)
        tasks.expand(total: Int.max)
        precondition(tasks.range(total: Int.max).upperBound == Int.max)
        var single = ChecklistExpansion(size: 1)
        single.reveal(itemAt: Int.max, total: Int.max)
        single.expand(total: Int.max)
        precondition(single.range(total: Int.max).upperBound == Int.max)
        for (size, reserved, divider) in [(8, 60.0, 1.0), (7, 94.0, 0.0)] {
            let list = ChecklistExpansion(size: size)
            for height in [410.0, 450.0, 600.0, 900.0] {
                let row = list.rowHeight(available: height, reserved: reserved, divider: divider)
                precondition(row >= 40)
                precondition(abs((row + divider) * Double(size) + reserved - height) < 0.001,
                             "A full initial list must fill its available canvas")
            }
            precondition(list.rowHeight(available: 100, reserved: reserved, divider: divider) == 40)
        }
        print("Checklist expansion passed: cumulative reveal, eight/seven initial limits, collapse, deletion, new-row reveal, safe bounds and canvas-filling row heights")
    }
}
