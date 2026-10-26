import Foundation

/// AX calls are synchronous IPC. Keep them on bounded GCD-backed actors rather
/// than blocking threads of Swift's cooperative executor. The coordinator
/// limits discovery to three sessions; interactive commands keep their lane.
final class AXQueueExecutor: SerialExecutor {
    private let queue: DispatchQueue
    init(label: String) { queue = DispatchQueue(label: label, qos: .userInitiated) }
    func enqueue(_ job: UnownedJob) {
        let executor = asUnownedSerialExecutor()
        queue.async { job.runSynchronously(on: executor) }
    }
}
