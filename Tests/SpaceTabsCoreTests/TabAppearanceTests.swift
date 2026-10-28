import Foundation
import Testing

@testable import SpaceTabsCore

@Test func automaticTabThemeAlwaysOpposesSystemAndExplicitModesStayFixed() {
    var appearance = TabAppearance()
    #expect(appearance.palette(systemIsDark: false).background == .black)
    #expect(appearance.palette(systemIsDark: true).background == .white)
    appearance.mode = .light
    #expect(appearance.palette(systemIsDark: false).foreground == .black)
    #expect(appearance.palette(systemIsDark: true).background == .white)
    appearance.mode = .dark
    #expect(appearance.palette(systemIsDark: false).foreground == .white)
    #expect(appearance.palette(systemIsDark: true).background == .black)
}

@Test func customBackgroundAndAccentsKeepReadableForegrounds() {
    var appearance = TabAppearance()
    for background in [TabColor.black, .white, TabColor(0.1, 0.2, 0.4), TabColor(0.9, 0.8, 0.3)] {
        appearance.backgroundOverride = background
        appearance.colorA = background
        appearance.colorB = TabColor(0.1, 0.2, 0.5)
        let palette = appearance.palette(systemIsDark: true)
        #expect(palette.foreground.contrast(with: background) >= 4.5)
        #expect(appearance.accent(for: .a, systemIsDark: true).contrast(with: background) >= 4.5)
        #expect(appearance.accent(for: .b, systemIsDark: true).contrast(with: background) >= 4.5)
    }
}

@Test func tabAppearancePersistsAndInvalidColorsAreRejected() throws {
    let url = FileManager.default.temporaryDirectory.appendingPathComponent("SpaceTabsTheme-\(UUID()).json")
    defer { try? FileManager.default.removeItem(at: url) }
    let store = PersistenceStore(url: url)
    var appearance = TabAppearance()
    appearance.mode = .dark
    appearance.backgroundOverride = TabColor(0.2, 0.1, 0.4)
    appearance.backgroundOpacity = 0.35
    appearance.keepFixedBarsBehindWindows = false
    appearance.revealAllBarsOnClick = false
    appearance.colorA = TabColor(0.8, 0.5, 0.2)
    appearance.dragBorderColor = TabColor(0.2, 0.7, 0.4)
    var layout = PersistedLayout(tabAppearance: appearance)
    try store.save(layout)
    #expect(try store.load() == layout)
    layout.tabAppearance.dragBorderColor.red = 2
    #expect(throws: (any Error).self) { try store.save(layout) }
    try Data(#"{"version":1,"ratio":0.3,"screenID":"","tabs":[]}"#.utf8).write(to: url)
    let legacy = try store.load()
    #expect(legacy?.tabAppearance == TabAppearance())
}

@Test func tabBackgroundOpacityDefaultsForOlderThemesAndRejectsInvalidValues() throws {
    let appearance = TabAppearance()
    var object = try #require(JSONSerialization.jsonObject(with: JSONEncoder().encode(appearance)) as? [String: Any])
    object.removeValue(forKey: "backgroundOpacity")
    let legacy = try JSONDecoder().decode(TabAppearance.self, from: JSONSerialization.data(withJSONObject: object))
    #expect(legacy.backgroundOpacity == 0.9 && legacy == appearance)

    let url = FileManager.default.temporaryDirectory.appendingPathComponent("SpaceTabsOpacity-\(UUID()).json")
    defer { try? FileManager.default.removeItem(at: url) }
    let store = PersistenceStore(url: url)
    for opacity in [0.0, 0.35, 1.0] {
        var layout = PersistedLayout()
        layout.tabAppearance.backgroundOpacity = opacity
        try store.save(layout)
        #expect(try store.load()?.tabAppearance.backgroundOpacity == opacity)
    }
    for opacity in [-0.01, 1.01, Double.nan, .infinity] {
        var invalid = appearance
        invalid.backgroundOpacity = opacity
        #expect(!invalid.isValid)
        #expect(throws: (any Error).self) { try store.save(PersistedLayout(tabAppearance: invalid)) }
    }
    object["backgroundOpacity"] = 1.5
    let invalid = try JSONDecoder().decode(TabAppearance.self, from: JSONSerialization.data(withJSONObject: object))
    #expect(!invalid.isValid)
}

@Test func existingThemesKeepTheirColorsAndDefaultToWhiteDragBorders() throws {
    var appearance = TabAppearance()
    appearance.backgroundOverride = TabColor(0.3, 0.2, 0.1)
    appearance.colorC = TabColor(0.6, 0.2, 0.8)
    let data = try JSONEncoder().encode(appearance)
    var object = try #require(JSONSerialization.jsonObject(with: data) as? [String: Any])
    object.removeValue(forKey: "dragBorderColor")
    object.removeValue(forKey: "keepFixedBarsBehindWindows")
    object.removeValue(forKey: "revealAllBarsOnClick")
    let legacyData = try JSONSerialization.data(withJSONObject: object)
    #expect(try JSONDecoder().decode(TabAppearance.self, from: legacyData) == appearance)
    #expect(appearance.keepFixedBarsBehindWindows)
    #expect(appearance.revealAllBarsOnClick)
    for color in [
        TabColor.white, .black, TabColor(0.5, 0.5, 0.5), TabColor(1, 0, 0), TabColor(0, 1, 0), TabColor(0, 0, 1),
    ] {
        let foreground: TabColor = color.usesLightText ? .white : .black
        #expect(foreground.contrast(with: color) >= 4.5)
    }
}
