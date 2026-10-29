/// A single outstanding heartbeat avoids piling work onto a stalled UI queue.
/// Times are monotonic seconds. Long monitor gaps (sleep/scheduling) reset the sample.
public struct ResponsivenessState: Sendable {
    public enum Event: Equatable, Sendable {
        case stalled
        case recovered(Double)
    }
    private var pendingSince: Double?
    private var lastTick: Double?
    private var reported = false
    public init() {}

    public mutating func tick(at now: Double) -> (sendHeartbeat: Bool, event: Event?) {
        if let lastTick, now - lastTick > 2.5 {
            pendingSince = nil
            reported = false
        }
        lastTick = now
        guard let pendingSince else {
            self.pendingSince = now
            return (true, nil)
        }
        if !reported, now - pendingSince >= 3 {
            reported = true
            return (false, .stalled)
        }
        return (false, nil)
    }

    public mutating func acknowledge(at now: Double) -> Event? {
        defer {
            pendingSince = nil
            reported = false
        }
        guard reported, let pendingSince else { return nil }
        return .recovered(max(0, now - pendingSince))
    }
}
