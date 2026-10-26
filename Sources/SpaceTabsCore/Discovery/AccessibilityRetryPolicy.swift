import Foundation

/// Event-driven retries only: callers consult deadlines when new work arrives.
/// No timer or background discovery is scheduled by this policy.
public struct AccessibilityRetryPolicy: Sendable {
    private struct Failure: Sendable {
        var count: Int
        var deadline: TimeInterval
    }
    private var failures: [String: Failure] = [:]
    public init() {}
    public func canAttempt(_ key: String, now: TimeInterval) -> Bool {
        failures[key].map { now >= $0.deadline } ?? true
    }
    public mutating func failed(_ key: String, now: TimeInterval, unsupported: Bool = false) {
        let count = min(5, (failures[key]?.count ?? 0) + 1)
        failures[key] = Failure(count: count, deadline: unsupported ? .infinity : now + min(30, pow(2, Double(count))))
    }
    public mutating func succeeded(_ key: String) { failures[key] = nil }
    public mutating func reset(prefix: String? = nil) {
        if let prefix { failures = failures.filter { !$0.key.hasPrefix(prefix) } } else { failures.removeAll() }
    }
}
