import Foundation
import Synchronization

extension Notification.Name {
    public static let spaceTabsLanguageDidChange = Notification.Name("SpaceTabs.LanguageDidChange")
}

/// Shared by the main app, Settings helper, and AX sessions. Catalogs load once.
public enum L10n {
    // App startup explicitly applies the saved preference. A deterministic default
    // keeps library use and policy tests independent of the developer's Mac language.
    private static let currentLanguage = Mutex<AppLanguage>(.english)
    public static var language: AppLanguage { currentLanguage.withLock { $0 } }

    public static func configure(_ preference: AppLanguage, preferredLanguages: [String] = Locale.preferredLanguages) {
        let resolved = preference.resolved(preferredLanguages: preferredLanguages)
        let changed = currentLanguage.withLock { current in
            guard current != resolved else { return false }
            current = resolved
            return true
        }
        if changed { NotificationCenter.default.post(name: .spaceTabsLanguageDidChange, object: nil) }
    }

    public static func tr(_ message: LocalizedMessage) -> String {
        text(message.key, arguments: message.arguments)
    }

    /// Use for known catalog keys held in enums, never external window titles or user names.
    public static func text(_ key: String, arguments: [String] = [], language: AppLanguage? = nil) -> String {
        let choice = language ?? Self.language
        let selected = choice == .automatic ? choice.resolved() : choice
        let value = catalogs[selected]?[key] ?? catalogs[.english]?[key] ?? key
        return interpolate(value, arguments: arguments)
    }

    /// Single-pass substitution prevents argument contents such as "{1}" from
    /// becoming another argument or a printf directive.
    static func interpolate(_ template: String, arguments: [String]) -> String {
        guard !arguments.isEmpty else { return template }
        var result = ""
        var cursor = template.startIndex
        while cursor < template.endIndex {
            if template[cursor] == "{", let end = template[cursor...].firstIndex(of: "}"),
                let index = Int(template[template.index(after: cursor)..<end]), arguments.indices.contains(index)
            {
                result += arguments[index]
                cursor = template.index(after: end)
            } else {
                result.append(template[cursor])
                cursor = template.index(after: cursor)
            }
        }
        return result
    }

    private static let catalogs: [AppLanguage: [String: String]] = {
        // Packaged apps carry their own copy. Bundle.module serves SwiftPM builds
        // and tests; a packaged app never depends on a developer's build directory.
        let packaged = Bundle.main.resourceURL?.appendingPathComponent("SpaceTabs_SpaceTabsCore.bundle")
        let bundle: Bundle?
        if Bundle.main.bundleURL.pathExtension == "app" {
            bundle = packaged.flatMap(Bundle.init(url:))
        } else {
            bundle = Bundle.module
        }
        return Dictionary(
            uniqueKeysWithValues: AppLanguage.allCases.filter { $0 != .automatic }.map { language in
                let url = bundle?.url(
                    forResource: "Localizable", withExtension: "strings", subdirectory: "\(language.rawValue).lproj")
                let values =
                    url.flatMap { try? Data(contentsOf: $0) }.flatMap {
                        try? PropertyListSerialization.propertyList(from: $0, format: nil) as? [String: String]
                    } ?? [:]
                return (language, values)
            })
    }()
}
