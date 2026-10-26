import Foundation

public struct ShortcutBinding: Codable, Equatable, Hashable, Sendable {
    public var enabled: Bool
    public var key: UInt32
    /// Carbon modifier mask, limited to Command, Option, Control and Shift.
    public var modifiers: UInt32
    public init(key: UInt32, modifiers: UInt32, enabled: Bool = true) {
        self.key = key
        self.modifiers = modifiers
        self.enabled = enabled
    }
    private enum CodingKeys: String, CodingKey { case key, modifiers, enabled }
    public init(from decoder: any Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        key = try values.decode(UInt32.self, forKey: .key)
        modifiers = try values.decode(UInt32.self, forKey: .modifiers)
        enabled = try values.decodeIfPresent(Bool.self, forKey: .enabled) ?? true
    }
    public var isValid: Bool {
        key <= 126 && modifiers & ~UInt32(256 | 512 | 2048 | 4096) == 0 && modifiers & UInt32(256 | 2048 | 4096) != 0
    }
}
