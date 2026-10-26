import CoreGraphics
import Foundation

/// Pure drag policy. Only confirmed window movement can reveal drop targets.
public struct ZoneDragState: Sendable {
    public private(set) var tracking = false
    public private(set) var dragging = false
    public private(set) var modifierHeld = false
    public private(set) var confirmedWindowMove = false
    public private(set) var hovered: Zone?
    public var isVisible: Bool { tracking && dragging && modifierHeld && confirmedWindowMove }
    public init() {}
    public mutating func begin() {
        self = Self()
        tracking = true
    }
    public mutating func update(pointer: CGPoint, modifierHeld: Bool, windowMoved: Bool, zones: [Zone: CGRect]) {
        guard tracking else { return }
        dragging = true
        self.modifierHeld = modifierHeld
        confirmedWindowMove = confirmedWindowMove || windowMoved
        hovered = isVisible ? Zone.allCases.first { zones[$0]?.contains(pointer) == true } : nil
    }
    public mutating func modifiersChanged(held: Bool) {
        modifierHeld = held
        if !held { hovered = nil }
    }
    public mutating func end(modifierHeld: Bool) -> Zone? {
        let destination = isVisible && modifierHeld ? hovered : nil
        self = Self()
        return destination
    }
    public mutating func cancel() { self = Self() }

    public static func isWindowMove(from initial: CGRect, to current: CGRect) -> Bool {
        guard
            [
                initial.minX, initial.minY, initial.width, initial.height,
                current.minX, current.minY, current.width, current.height,
            ].allSatisfy(\.isFinite),
            initial.width > 0, initial.height > 0, current.width > 0, current.height > 0,
            abs(initial.width - current.width) <= 1, abs(initial.height - current.height) <= 1
        else { return false }
        return hypot(current.minX - initial.minX, current.minY - initial.minY) >= 2
    }
}
