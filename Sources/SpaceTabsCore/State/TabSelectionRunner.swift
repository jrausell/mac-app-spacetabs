import Foundation

/// Serialize window focus requests, replacing an unfinished choice with the
/// latest click. Cancellation never starts a second focus operation in parallel.
@MainActor
public final class TabSelectionRunner {
    private var task: Task<Void, Never>?
    private var generation = 0
    public private(set) var isPending = false
    public init() {}
    public func submit(_ work: @escaping @MainActor () async -> Void, onComplete: @escaping @MainActor () -> Void = {})
    {
        generation += 1
        let token = generation
        isPending = true
        let previous = task
        previous?.cancel()
        task = Task {
            await previous?.value
            guard !Task.isCancelled, self.generation == token else { return }
            defer {
                if self.generation == token {
                    self.isPending = false
                    onComplete()
                }
            }
            await work()
        }
    }
    public func cancel() {
        generation += 1
        isPending = false
        task?.cancel()
    }
    public func wait() async { await task?.value }
}
