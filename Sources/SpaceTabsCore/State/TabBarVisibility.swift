import CoreGraphics
import Foundation

/// Clock-independent visibility policy; no polling or window discovery required.
public struct TabBarVisibility: Sendable {
    public private(set) var isVisible = false
    public private(set) var deadline: TimeInterval?
    private var hovered = false
    private var trackingMenu = false
    public private(set) var autoHide = true
    public private(set) var keepFixedBarsBehindWindows = true
    public var usesTemporaryReveal: Bool { autoHide || keepFixedBarsBehindWindows }
    public var isAboveWindows: Bool { autoHide || !keepFixedBarsBehindWindows || deadline != nil }
    public let duration: TimeInterval
    public init(duration: TimeInterval = 5) { self.duration = duration }

    public mutating func reveal(at now: TimeInterval) {
        isVisible = true
        deadline = usesTemporaryReveal ? now + duration : nil
    }
    public mutating func setAutoHide(_ value: Bool, at now: TimeInterval) {
        guard autoHide != value else { return }
        autoHide = value
        if value {
            hide()
        } else {
            isVisible = true
            deadline = nil
        }
    }
    public mutating func setKeepFixedBarsBehindWindows(_ value: Bool) {
        guard keepFixedBarsBehindWindows != value else { return }
        keepFixedBarsBehindWindows = value
        if !autoHide { deadline = nil }
    }
    public mutating func showFixed() {
        if !autoHide { isVisible = true }
    }
    public mutating func setHovered(_ value: Bool, at now: TimeInterval) {
        guard hovered != value else { return }
        hovered = value
        if isVisible && usesTemporaryReveal && deadline != nil { deadline = now + duration }
    }
    public mutating func setMenuTracking(_ value: Bool, at now: TimeInterval) {
        guard trackingMenu != value else { return }
        trackingMenu = value
        if isVisible && usesTemporaryReveal && deadline != nil { deadline = now + duration }
    }
    public var canExpire: Bool { usesTemporaryReveal && isVisible && deadline != nil && !hovered && !trackingMenu }
    public mutating func expire(at now: TimeInterval) {
        if canExpire, let deadline, now >= deadline { dismissReveal() }
    }
    public mutating func hide() {
        isVisible = false
        deadline = nil
        hovered = false
        trackingMenu = false
    }
    public mutating func pointerDown(at point: CGPoint, interactiveFrames: [CGRect]) {
        guard usesTemporaryReveal, isVisible, !interactiveFrames.contains(where: { $0.contains(point) }) else { return }
        // Explicit dismissal overrides both hover and menu-based timeout holds.
        dismissReveal()
    }
    private mutating func dismissReveal() {
        if autoHide {
            hide()
        } else {
            deadline = nil
            hovered = false
            trackingMenu = false
        }
    }
    public static func atTopEdge(_ point: CGPoint, screen: CGRect, dragging: Bool) -> Bool {
        !dragging && point.x >= screen.minX && point.x < screen.maxX && point.y >= screen.maxY - 3
            && point.y <= screen.maxY
    }
}
