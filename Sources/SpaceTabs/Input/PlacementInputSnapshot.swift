import CoreGraphics

/// Compare counters only during bounded startup placement; do not install an
/// event monitor or retain user input. A completed short drag must cancel too.
struct PlacementInputSnapshot: Equatable, Sendable {
    private let counters: [UInt32]
    static func capture() -> Self {
        Self(
            counters: [CGEventType.leftMouseDown, .rightMouseDown, .otherMouseDown, .keyDown, .scrollWheel].map {
                CGEventSource.counterForEventType(.combinedSessionState, eventType: $0)
            })
    }
}
