import CoreGraphics
import Foundation

/// A Control/right-button chord is captured from down through up, including
/// after cancellation, so an orphan mouse-up cannot open an app context menu.
public struct RightDragState: Sendable {
    public private(set) var origin: CGPoint?
    public private(set) var pointer = CGPoint.zero
    public private(set) var cancelled = false
    public private(set) var dragged = false
    public var tracking: Bool { origin != nil }
    public var isVisible: Bool { tracking && dragged && !cancelled }
    public init() {}
    public static let eventTypes: [CGEventType] = [
        .rightMouseDown, .rightMouseDragged, .mouseMoved, .rightMouseUp, .flagsChanged,
    ]
    /// A filtered mouse-down can leave motion classified as mouseMoved.
    /// Samples must come from Quartz, not AppKit's cached mouse location.
    @discardableResult public mutating func receiveMotion(_ type: CGEventType, pointer: CGPoint, controlHeld: Bool)
        -> Bool
    {
        guard tracking, type == .rightMouseDragged || type == .mouseMoved else { return false }
        update(at: pointer, controlHeld: controlHeld)
        return true
    }
    public mutating func begin(at point: CGPoint) {
        self = Self()
        origin = point
        pointer = point
    }
    public mutating func update(at point: CGPoint, controlHeld: Bool) {
        guard let origin else { return }
        pointer = point
        if !controlHeld { cancelled = true }
        if hypot(point.x - origin.x, point.y - origin.y) >= 6 { dragged = true }
    }
    public mutating func cancel() { if tracking { cancelled = true } }
    public mutating func end(controlHeld: Bool, zones: [Zone: CGRect]) -> Zone? {
        let destination = isVisible && controlHeld ? Zone.allCases.first { zones[$0]?.contains(pointer) == true } : nil
        self = Self()
        return destination
    }
    public mutating func reset() { self = Self() }
}

/// An AX capture may finish after mouse-up. Keep its lease only for the same
/// accepted drop; a cancellation or a newer gesture invalidates late replies.
public struct RightDragCaptureLease: Sendable {
    public private(set) var generation = UUID()
    public private(set) var pendingDrop = false
    private var valid = false
    public init() {}
    @discardableResult public mutating func begin() -> UUID {
        generation = UUID()
        pendingDrop = false
        valid = true
        return generation
    }
    public func accepts(_ ticket: UUID) -> Bool { valid && generation == ticket }
    public mutating func dropped() { if valid { pendingDrop = true } }
    public mutating func invalidate() {
        generation = UUID()
        pendingDrop = false
        valid = false
    }
}
