import Foundation

public struct DisplayIdentity: Sendable, Equatable {
    public let runtimeID: String
    public let stableID: String
    public init(runtimeID: String, stableID: String) {
        self.runtimeID = runtimeID
        self.stableID = stableID
    }
}

/// Retain the selected physical monitor across temporary disappearance and
/// runtime-ID changes. An explicit user selection starts a new association.
public struct DisplaySelectionTracker: Sendable {
    private var selection: String?
    private var stableID: String?
    public init() {}
    public mutating func resolve(_ requested: String, displays: [DisplayIdentity]) -> String? {
        if requested != selection {
            stableID = nil
            selection = requested
        }
        let matches: [DisplayIdentity]
        if let stableID {
            matches = displays.filter { $0.stableID == stableID }
        } else if requested.isEmpty {
            matches = Array(displays.prefix(1))
        } else {
            matches = displays.filter { $0.runtimeID == requested || $0.stableID == requested }
        }
        guard matches.count == 1, let display = matches.first else { return nil }
        stableID = display.stableID
        selection = display.runtimeID
        return display.runtimeID
    }
}
