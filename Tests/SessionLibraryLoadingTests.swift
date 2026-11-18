import Foundation

@main @MainActor struct SessionLibraryLoadingTests {
    // The counter crosses worker/main boundaries only through this lock.
    final class Counter: @unchecked Sendable {
        let lock = NSLock()
        private var count = 0
        func increment() { lock.lock(); count += 1; lock.unlock() }
        var value: Int { lock.lock(); defer { lock.unlock() }; return count }
    }
    static func main() async throws {
        let fm = FileManager.default
        let root = fm.temporaryDirectory.appendingPathComponent("library-loading-\(UUID())")
        try fm.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? fm.removeItem(at: root) }
        let loader = SessionLibraryLoader(), scans = Counter()
        var completions = 0
        for _ in 0..<200 {
            loader.load(root: root, inspect: { root in scans.increment(); return try SessionFiles.inspect(in: root) }) { result in
                precondition((try? result.get().sessions.count) == 0)
                completions += 1
            }
        }
        for _ in 0..<1000 { if completions > 0 { break }; try await Task.sleep(for: .milliseconds(1)) }
        precondition(scans.value == 1 && completions == 1, "Superseded requests started redundant scans")
        let started = Counter(), cancelled = Counter()
        loader.load(root: root, inspect: { _ in
            started.increment()
            do { while true { try Task.checkCancellation(); Thread.sleep(forTimeInterval: 0.001) } }
            catch { cancelled.increment(); throw error }
        }) { _ in preconditionFailure("Cancelled scan published a result") }
        while started.value == 0 { await Task.yield() }
        loader.load(root: root) { _ in completions += 1 }
        for _ in 0..<1000 { if cancelled.value > 0 && completions == 2 { break }; try await Task.sleep(for: .milliseconds(1)) }
        precondition(cancelled.value == 1 && completions == 2)
        var fixtures: [SavedSession] = []
        for index in 0..<200 {
            let folder = root.appendingPathComponent("session-\(index)")
            try fm.createDirectory(at: folder, withIntermediateDirectories: false)
            fixtures.append(try SavedSession(folder: folder))
        }
        var moves = 0
        do {
            _ = try SessionFiles.deleteSelected(fixtures, root: root, active: fixtures.last!.folder) { _ in moves += 1 }
            preconditionFailure("Active selection was accepted")
        } catch { precondition(moves == 0) }
        let result = try SessionFiles.deleteSelected(fixtures, root: root, active: nil) { folder in
            if folder == fixtures[50].folder { throw CocoaError(.fileWriteNoPermission) }
            moves += 1
        }
        precondition(result.deleted.count == 199 && result.failures.count == 1 && moves == 199)
        let scanTask = Task.detached { () throws -> Void in
            withUnsafeCurrentTask { $0?.cancel() }
            _ = try SessionFiles.inspect(in: root)
        }
        do { try await scanTask.value; preconditionFailure("Cancelled scan read the library") }
        catch is CancellationError { }
        print("PASS: 200 rapid refreshes coalesce, running scan cancellation, large batch partial deletion and active protection")
    }
}
