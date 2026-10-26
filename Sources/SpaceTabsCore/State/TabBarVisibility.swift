import CoreGraphics
import Foundation

/// Clock-independent visibility policy; no polling or window discovery required.
public struct TabBarVisibility: Sendable {
    public private(set) var isVisible = false
    public private(set) var deadline: TimeInterval?
    private var hovered = false
    private var trackingMenu = false
    public private(set) var autoHide = true
    public let duration: TimeInterval
    public init(duration: TimeInterval = 5) { self.duration = duration }

    public mutating func reveal(at now: TimeInterval) {
        isVisible = true
        deadline = autoHide ? now + duration : nil
    }
    public mutating func setAutoHide(_ value: Bool, at now: TimeInterval) {
        guard autoHide != value else { return }
        autoHide = value
        if value { hide() } else { reveal(at: now) }
    }
    public mutating func setHovered(_ value: Bool, at now: TimeInterval) {
        guard hovered != value else { return }
        hovered = value
        if isVisible && autoHide { deadline = now + duration }
    }
    public mutating func setMenuTracking(_ value: Bool, at now: TimeInterval) {
        guard trackingMenu != value else { return }
        trackingMenu = value
        if isVisible && autoHide { deadline = now + duration }
    }
    public var canExpire: Bool { autoHide && isVisible && !hovered && !trackingMenu }
    public mutating func expire(at now: TimeInterval) {
        if canExpire, let deadline, now >= deadline { hide() }
    }
    public mutating func hide() {
        isVisible = false
        deadline = nil
        hovered = false
        trackingMenu = false
    }
    public mutating func pointerDown(at point: CGPoint, interactiveFrames: [CGRect]) {
        guard autoHide, isVisible, !interactiveFrames.contains(where: { $0.contains(point) }) else { return }
        // Explicit dismissal overrides both hover and menu-based timeout holds.
        hide()
    }
    public static func atTopEdge(_ point: CGPoint, screen: CGRect, dragging: Bool) -> Bool {
        !dragging && point.x >= screen.minX && point.x < screen.maxX && point.y >= screen.maxY - 3
            && point.y <= screen.maxY
    }
}
