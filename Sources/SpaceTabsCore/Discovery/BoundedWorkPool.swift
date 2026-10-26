import Foundation

public enum BoundedWorkPool {
    public static func map<Input: Sendable, Output: Sendable>(
        _ inputs: [Input], limit: Int,
        operation: @escaping @Sendable (Input) async -> Output
    ) async -> [Output] {
        guard !inputs.isEmpty, !Task.isCancelled else { return [] }
        return await withTaskGroup(of: Output.self) { group in
            var next = 0
            for _ in 0..<min(max(1, limit), inputs.count) {
                let input = inputs[next]
                next += 1
                group.addTask(priority: .utility) { await operation(input) }
            }
            var result: [Output] = []
            for await value in group {
                result.append(value)
                if Task.isCancelled {
                    group.cancelAll()
                } else if next < inputs.count {
                    let input = inputs[next]
                    next += 1
                    group.addTask(priority: .utility) { await operation(input) }
                }
            }
            return result
        }
    }
}
