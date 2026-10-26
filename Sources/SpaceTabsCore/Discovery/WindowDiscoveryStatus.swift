/// A missing permission is different from a completed search with no matches.
public enum WindowDiscoveryStatus: Equatable, Sendable {
    case permissionRequired
    case waiting
    case searching
    case ready

    public init(trusted: Bool, searching: Bool, completed: Bool) {
        if !trusted {
            self = .permissionRequired
        } else if searching {
            self = .searching
        } else if !completed {
            self = .waiting
        } else {
            self = .ready
        }
    }

    public var canReportMatches: Bool { self == .ready }
}
