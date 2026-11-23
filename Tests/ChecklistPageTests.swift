import Foundation

@main struct ChecklistPageTests {
    static func main() {
        for size in [8, 7] {
            for total in [0, size - 1, size, size + 1, size * 2, size * 2 + 1, 97] {
                var page = ChecklistPage(size: size)
                var visited: [Int] = []
                while true {
                    let range = page.range(total: total)
                    precondition(range.count <= size && range.lowerBound >= 0 && range.upperBound <= total)
                    visited += Array(range)
                    if !page.hasNext(total: total) { break }
                    page.next(total: total)
                }
                precondition(visited == Array(0..<total), "Every row must remain reachable exactly once")
                let last = page
                page.next(total: total)
                precondition(page == last)
                while page.hasPrevious(total: total) { page.previous(total: total) }
                precondition(page.index == 0)
                page.previous(total: total)
                precondition(page.index == 0)
            }
        }
        var projects = ChecklistPage(size: 8)
        precondition(!projects.hasNext(total: 8) && projects.hasNext(total: 9))
        projects.next(total: 9)
        precondition(projects.range(total: 9) == 8..<9 && projects.hasPrevious(total: 9))
        projects.clamp(total: 8)
        precondition(projects.index == 0 && projects.range(total: 8) == 0..<8)
        var tasks = ChecklistPage(size: 7)
        precondition(!tasks.hasNext(total: 7) && tasks.hasNext(total: 8))
        tasks.reveal(itemAt: 7, total: 8)
        precondition(tasks.range(total: 8) == 7..<8)
        tasks.clamp(total: 7)
        precondition(tasks.range(total: 7) == 0..<7)
        tasks.reveal(itemAt: 999, total: 10)
        precondition(tasks.range(total: 10).contains(9))
        tasks.reveal(itemAt: -1, total: 10)
        precondition(tasks.index == 0)
        tasks.clamp(total: 0)
        precondition(tasks.range(total: 0).isEmpty && !tasks.hasPrevious(total: 0))
        precondition(tasks.range(total: -1).isEmpty)
        tasks.reveal(itemAt: Int.max, total: Int.max)
        precondition(tasks.range(total: Int.max).upperBound == Int.max)
        print("ChecklistPageTests passed: eight/seven-row limits, complete navigation, threshold arrows, deletion clamp and created-row reveal")
    }
}
