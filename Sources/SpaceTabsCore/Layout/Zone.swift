import Foundation

public enum Zone: String, Codable, CaseIterable, Sendable, Identifiable {
    case a, b, c
    public var id: String { rawValue }
    public var title: String { rawValue.uppercased() }
}

public enum LayoutTemplate: String, Codable, CaseIterable, Sendable, Identifiable {
    case twoColumns, splitLeft, splitRight
    public var id: String { rawValue }
    public var zones: [Zone] { self == .twoColumns ? [.a, .b] : [.a, .c, .b] }
    public var title: String {
        switch self {
        case .twoColumns: L10n.tr("Two Columns")
        case .splitLeft: L10n.tr("A/C on the Left")
        case .splitRight: L10n.tr("A/C on the Right")
        }
    }
    public var defaultRatio: Double { self == .splitRight ? 0.75 : 0.25 }
}
