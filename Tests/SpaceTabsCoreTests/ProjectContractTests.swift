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
    #expect(app["CFBundleIdentifier"] as? String == SpaceTabsIdentity.appBundleID)
    #expect(settings["CFBundleIdentifier"] as? String == SpaceTabsIdentity.settingsBundleID)
    #expect(settings["CFBundleName"] as? String == SpaceTabsIdentity.settingsAppName)
    #expect(app["CFBundleShortVersionString"] as? String == settings["CFBundleShortVersionString"] as? String)
    #expect(app["CFBundleVersion"] as? String == settings["CFBundleVersion"] as? String)
    let languages = Set(AppLanguage.allCases.filter { $0 != .automatic }.map(\.rawValue))
    for metadata in [app, settings] {
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
