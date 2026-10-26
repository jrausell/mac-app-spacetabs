import Foundation

/// Stored values are language codes, independent of translated display names.
public enum AppLanguage: String, Codable, CaseIterable, Sendable, Identifiable {
    case automatic
    case english = "en"
    case spanish = "es"

    public var id: String { rawValue }

    public var displayName: String {
        switch self {
        case .automatic: L10n.tr("Automatic · System Language")
        case .english: "English"
        case .spanish: "Español"
        }
    }

    /// Match the user's preferred languages in order, including regional variants.
    /// English is the fallback when none of the installed languages match.
    public func resolved(preferredLanguages: [String] = Locale.preferredLanguages) -> AppLanguage {
        guard self == .automatic else { return self }
        for identifier in preferredLanguages {
            let code = identifier.replacingOccurrences(of: "_", with: "-").split(separator: "-").first?.lowercased()
            if let language = AppLanguage.allCases.first(where: { $0 != .automatic && $0.rawValue == code }) {
                return language
            }
        }
        return .english
    }
}
