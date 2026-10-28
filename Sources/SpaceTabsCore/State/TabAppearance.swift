import Foundation

public enum TabBarMode: String, Codable, CaseIterable, Sendable {
    case automatic, light, dark
}

public struct TabColor: Codable, Equatable, Sendable {
    public var red: Double
    public var green: Double
    public var blue: Double
    public init(_ red: Double, _ green: Double, _ blue: Double) {
        self.red = red
        self.green = green
        self.blue = blue
    }
    public static let black = TabColor(0, 0, 0)
    public static let white = TabColor(1, 1, 1)
    public var isValid: Bool { [red, green, blue].allSatisfy { $0.isFinite && (0...1).contains($0) } }
    public var luminance: Double {
        func linear(_ x: Double) -> Double { x <= 0.04045 ? x / 12.92 : pow((x + 0.055) / 1.055, 2.4) }
        return 0.2126 * linear(red) + 0.7152 * linear(green) + 0.0722 * linear(blue)
    }
    public var usesLightText: Bool { luminance < 0.179 }
    public func contrast(with other: TabColor) -> Double {
        let a = luminance
        let b = other.luminance
        return (max(a, b) + 0.05) / (min(a, b) + 0.05)
    }
    /// Keep the selected hue, making it readable against the chosen background.
    public func readable(on background: TabColor) -> TabColor {
        let target: Double = background.usesLightText ? 1 : 0
        for step in 0...10 {
            let fraction = Double(step) / 10
            let color = TabColor(
                red + (target - red) * fraction, green + (target - green) * fraction, blue + (target - blue) * fraction)
            if color.contrast(with: background) >= 4.5 { return color }
        }
        return background.usesLightText ? .white : .black
    }
}

public struct TabPalette: Equatable, Sendable {
    public let background: TabColor
    public let foreground: TabColor
    public var isDark: Bool { background.usesLightText }
}

public struct TabAppearance: Codable, Equatable, Sendable {
    public var mode: TabBarMode = .automatic
    public var backgroundOverride: TabColor?
    public var backgroundOpacity = 0.9
    public var keepFixedBarsBehindWindows = true
    public var revealAllBarsOnClick = true
    public var colorA = TabColor(1, 0.48, 0.05)
    public var colorB = TabColor(0.12, 0.46, 0.95)
    public var colorC = TabColor(0.15, 0.65, 0.3)
    public var dragBorderColor: TabColor = .white
    public init() {}
    private enum CodingKeys: String, CodingKey {
        case mode, backgroundOverride, backgroundOpacity, keepFixedBarsBehindWindows, revealAllBarsOnClick, colorA,
            colorB, colorC,
            dragBorderColor
    }
    public init(from decoder: any Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        mode = try values.decode(TabBarMode.self, forKey: .mode)
        backgroundOverride = try values.decodeIfPresent(TabColor.self, forKey: .backgroundOverride)
        backgroundOpacity = try values.decodeIfPresent(Double.self, forKey: .backgroundOpacity) ?? 0.9
        keepFixedBarsBehindWindows = try values.decodeIfPresent(Bool.self, forKey: .keepFixedBarsBehindWindows) ?? true
        revealAllBarsOnClick = try values.decodeIfPresent(Bool.self, forKey: .revealAllBarsOnClick) ?? true
        colorA = try values.decode(TabColor.self, forKey: .colorA)
        colorB = try values.decode(TabColor.self, forKey: .colorB)
        colorC = try values.decodeIfPresent(TabColor.self, forKey: .colorC) ?? TabColor(0.15, 0.65, 0.3)
        dragBorderColor = try values.decodeIfPresent(TabColor.self, forKey: .dragBorderColor) ?? .white
    }
    public var isValid: Bool {
        dragBorderColor.isValid && colorA.isValid && colorB.isValid && colorC.isValid
            && (backgroundOverride?.isValid ?? true)
            && backgroundOpacity.isFinite && (0...1).contains(backgroundOpacity)
    }
    public func palette(systemIsDark: Bool) -> TabPalette {
        let dark: Bool =
            switch mode {
            case .automatic: !systemIsDark
            case .light: false
            case .dark: true
            }
        let background = backgroundOverride ?? (dark ? .black : .white)
        return TabPalette(background: background, foreground: background.usesLightText ? .white : .black)
    }
    public func accent(for zone: Zone, systemIsDark: Bool) -> TabColor {
        (zone == .a ? colorA : zone == .b ? colorB : colorC).readable(
            on: palette(systemIsDark: systemIsDark).background)
    }
}
