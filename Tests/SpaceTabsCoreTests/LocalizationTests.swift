import Foundation
import Testing

@testable import SpaceTabsCore

@Test func automaticLanguageMatchesRegionalPreferencesAndFallsBackToEnglish() {
    #expect(AppLanguage.automatic.resolved(preferredLanguages: ["es-ES", "en-US"]) == .spanish)
    #expect(AppLanguage.automatic.resolved(preferredLanguages: ["es_MX"]) == .spanish)
    #expect(AppLanguage.automatic.resolved(preferredLanguages: ["EN-gb", "es"]) == .english)
    #expect(AppLanguage.automatic.resolved(preferredLanguages: ["fr-FR", "es-AR"]) == .spanish)
    #expect(AppLanguage.automatic.resolved(preferredLanguages: ["de-DE"]) == .english)
    #expect(AppLanguage.automatic.resolved(preferredLanguages: []) == .english)
    #expect(AppLanguage.english.resolved(preferredLanguages: ["es"]) == .english)
    #expect(AppLanguage.spanish.resolved(preferredLanguages: ["en"]) == .spanish)
}

@Test func translatedInterpolationPreservesUserTextAndAllowsReordering() {
    let name = "Notes {1} · 100% %@ 日本語"
    let message: LocalizedMessage = "Profile “\(name)” saved."
    #expect(message.key == "Profile “{0}” saved.")
    #expect(L10n.text(message.key, arguments: message.arguments, language: .english) == "Profile “\(name)” saved.")
    #expect(L10n.text(message.key, arguments: message.arguments, language: .spanish) == "Perfil «\(name)» guardado.")
    #expect(L10n.interpolate("{1} / {0} / {1}", arguments: ["{1}", "%s"]) == "%s / {1} / %s")
    #expect(L10n.interpolate("Missing {8} and literal %d", arguments: ["x"]) == "Missing {8} and literal %d")
    #expect(L10n.text("A future English fallback", language: .spanish) == "A future English fallback")
}

@Test func everySpanishTranslationLoadsAndPreservesTheEnglishPlaceholders() throws {
    let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent()
        .deletingLastPathComponent().deletingLastPathComponent()
    func catalog(_ language: String) throws -> [String: String] {
        let url = root.appendingPathComponent(
            "Sources/SpaceTabsCore/Localization/Resources/\(language).lproj/Localizable.strings")
        return try #require(
            PropertyListSerialization.propertyList(from: Data(contentsOf: url), format: nil) as? [String: String])
    }
    let english = try catalog("en")
    let spanish = try catalog("es")
    #expect(english.count > 400)
    #expect(Set(english.keys) == Set(spanish.keys))
    func placeholders(_ value: String) -> Set<String> {
        Set(value.matches(of: /\{\d+\}/).map { String($0.output) })
    }
    for (key, value) in english {
        let translation = try #require(spanish[key])
        #expect(value == key)
        #expect(!translation.isEmpty)
        #expect(placeholders(key) == placeholders(translation), "\(key)")
        // Exercise the actual resource bundle, not just the source files.
        #expect(L10n.text(key, language: .english) == value)
        #expect(L10n.text(key, language: .spanish) == translation)
    }
}

@Test func languagePreferenceDefaultsForOldFilesAndRoundTripsWithoutChangingNames() throws {
    let old = try JSONDecoder().decode(UserPreferences.self, from: Data("{}".utf8))
    #expect(old.language == .automatic)
    var preferences = old
    preferences.language = .spanish
    preferences.zoneNames = [.b: "My Main Zone · {0}"]
    let data = try JSONEncoder().encode(preferences)
    let decoded = try JSONDecoder().decode(UserPreferences.self, from: data)
    #expect(decoded == preferences)
    try decoded.validate()
    #expect(throws: (any Error).self) {
        try JSONDecoder().decode(UserPreferences.self, from: Data(#"{"language":"../../outside"}"#.utf8))
    }
}
