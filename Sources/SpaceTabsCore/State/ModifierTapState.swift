/// Recognizes one clean modifier chord, firing only after every modifier is released.
public struct ModifierTapState: Sendable {
    private var seen: UInt32 = 0
    private var matched: UInt32?
    private var cancelled = false

    public init() {}

    public mutating func cancel() { cancelled = true }

    public mutating func update(modifiers: UInt32, targets: Set<UInt32>, interrupted: Bool = false) -> UInt32? {
        if interrupted { cancelled = true }
        if modifiers == 0 {
            let result = cancelled ? nil : matched
            self = Self()
            return result
        }
        seen |= modifiers
        if targets.contains(modifiers), seen == modifiers { matched = modifiers }
        if !targets.contains(where: { $0 & seen == seen }) { cancelled = true }
        return nil
    }
}
