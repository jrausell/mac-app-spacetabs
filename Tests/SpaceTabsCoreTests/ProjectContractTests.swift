import Foundation
import Testing

@testable import SpaceTabsCore

@Test func bundleMetadataMatchesRuntimeIdentitiesAndSharedVersion() throws {
    let root = URL(fileURLWithPath: #filePath)
        .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
    func metadata(_ name: String) throws -> [String: Any] {
        let data = try Data(contentsOf: root.appendingPathComponent("Resources/\(name)"))
        return try #require(PropertyListSerialization.propertyList(from: data, format: nil) as? [String: Any])
    }
    let app = try metadata("Info.plist")
    let settings = try metadata("Settings-Info.plist")
    let finder = try metadata("Finder-Info.plist")
    #expect(finder["CFBundleIdentifier"] as? String == SpaceTabsIdentity.finderBundleID)
    #expect(finder["CFBundlePackageType"] as? String == "XPC!")
    let extensionInfo = try #require(finder["NSExtension"] as? [String: Any])
    #expect(extensionInfo["NSExtensionPointIdentifier"] as? String == "com.apple.FinderSync")
    #expect(extensionInfo["NSExtensionPrincipalClass"] as? String == "SpaceTabsFinder")
    #expect(finder["CFBundleShortVersionString"] as? String == app["CFBundleShortVersionString"] as? String)
    #expect(finder["CFBundleVersion"] as? String == app["CFBundleVersion"] as? String)
    let schemes = try #require(app["CFBundleURLTypes"] as? [[String: Any]])
    #expect(
        schemes.contains {
            ($0["CFBundleURLSchemes"] as? [String])?.contains(SpaceTabsIdentity.desktopMenuScheme) == true
        })
    let entitlements = try metadata("Finder.entitlements")
    #expect(entitlements["com.apple.security.app-sandbox"] as? Bool == true)
    #expect(
        entitlements["com.apple.security.temporary-exception.files.home-relative-path.read-only"] as? [String] == [
            "/Library/Application Support/SpaceTabs/Finder/"
        ])
    #expect(entitlements["com.apple.security.temporary-exception.files.home-relative-path.read-write"] == nil)
    #expect(entitlements["com.apple.security.network.client"] == nil)
    #expect(app["CFBundleIdentifier"] as? String == SpaceTabsIdentity.appBundleID)
    #expect(settings["CFBundleIdentifier"] as? String == SpaceTabsIdentity.settingsBundleID)
    #expect(settings["CFBundleName"] as? String == SpaceTabsIdentity.settingsAppName)
    #expect(app["CFBundleShortVersionString"] as? String == settings["CFBundleShortVersionString"] as? String)
    #expect(app["CFBundleVersion"] as? String == settings["CFBundleVersion"] as? String)
    #expect(app["LSUIElement"] as? Bool == false)
    #expect(settings["LSUIElement"] as? Bool == true)
    let languages = Set(AppLanguage.allCases.filter { $0 != .automatic }.map(\.rawValue))
    for metadata in [app, settings, finder] {
        #expect(metadata["CFBundleDevelopmentRegion"] as? String == "en")
        #expect(Set(metadata["CFBundleLocalizations"] as? [String] ?? []) == languages)
    }
}

@Test func preferenceFilesPreserveUnicodeNamesAndWindowIdentities() throws {
    let directory = FileManager.default.temporaryDirectory.appendingPathComponent("SpaceTabsUnicode-\(UUID())")
    defer { try? FileManager.default.removeItem(at: directory) }
    let store = UserPreferencesStore(url: directory.appendingPathComponent("preferences.json"))
    var preferences = UserPreferences()
    // Non-English text is intentional data, not a translated UI string.
    preferences.zoneNames[.b] = "工具 · Café"
    let window = SavedTab(
        id: UUID(),
        identity: WindowIdentity(bundleID: "test.editor", title: "Résumé · 文書", document: "file:///tmp/Café.txt"),
        zone: .b, selected: true)
    preferences.profiles = [
        WorkspaceProfile(name: "日本語 · Café", layout: PersistedLayout(tabs: [window]), zoneNames: preferences.zoneNames)
    ]
    try store.save(preferences)
    #expect(try store.load() == preferences)
}
