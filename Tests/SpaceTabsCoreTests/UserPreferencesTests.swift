import Foundation
import Testing

@testable import SpaceTabsCore

@Test func preferencesRoundTripProfilesAndRejectUnsafeOrOversizedDataWithoutOverwriting() throws {
    let directory = FileManager.default.temporaryDirectory.appendingPathComponent("SpaceTabsPreferences-\(UUID())")
    defer { try? FileManager.default.removeItem(at: directory) }
    let store = UserPreferencesStore(url: directory.appendingPathComponent("preferences.json"))
    #expect(try store.load() == UserPreferences())
    var preferences = UserPreferences()
    preferences.zoneNames = [.b: "Work", .a: "Messages"]
    preferences.shortcuts = [8: ShortcutBinding(key: 17, modifiers: 4096 | 2048 | 512)]
    let saved = SavedTab(
        id: UUID(), identity: WindowIdentity(bundleID: "test.editor", title: "Document"), zone: .b, selected: true)
    preferences.profiles = [
        WorkspaceProfile(
            name: "Desarrollo", layout: PersistedLayout(ratio: 0.75, tabs: [saved], template: .splitRight),
            zoneNames: preferences.zoneNames)
    ]
    try store.save(preferences)
    #expect(try store.load() == preferences)
    let before = try Data(contentsOf: store.url)
    var invalid = preferences
    invalid.zoneNames[.a] = String(repeating: "a", count: 33)
    #expect(throws: (any Error).self) { try store.save(invalid) }
    invalid = preferences
    invalid.shortcuts[1] = ShortcutBinding(key: 0, modifiers: 512)
    #expect(throws: (any Error).self) { try store.save(invalid) }
    invalid = preferences
    invalid.profiles[0].layout.ratio = 0.1
    #expect(throws: (any Error).self) { try store.save(invalid) }
    invalid = preferences
    invalid.profiles.append(preferences.profiles[0])
    #expect(throws: (any Error).self) { try store.save(invalid) }
    invalid = preferences
    invalid.shortcuts[1] = invalid.shortcuts[8]
    #expect(throws: (any Error).self) { try store.save(invalid) }
    #expect(try Data(contentsOf: store.url) == before)
}

@Test func profileResolvesDocumentsAndSelectionsWhilePreservingUnlistedWindowsAndAmbiguity() throws {
    func window(_ title: String, document: String? = nil) -> WindowSnapshot {
        WindowSnapshot(
            id: UUID(), pid: 100, appName: "Editor",
            identity: WindowIdentity(bundleID: "test.editor", title: title, document: document),
            state: OriginalWindowState(frame: .init(x: 0, y: 0, width: 600, height: 600), minimized: false))
    }
    let a = window("New title", document: "file:///doc.txt")
    let b = window("Other")
    let c = window("Duplicate")
    let d = window("Duplicate")
    let savedA = SavedTab(
        id: UUID(), identity: WindowIdentity(bundleID: "test.editor", title: "Before", document: "file:///doc.txt"),
        zone: .b, selected: true)
    let ambiguous = SavedTab(id: UUID(), identity: c.identity, zone: .a, selected: true)
    let profile = WorkspaceProfile(
        name: "Work", layout: PersistedLayout(ratio: 0.75, tabs: [savedA, ambiguous], template: .splitRight),
        zoneNames: [:])
    var current = TabManager()
    current.assign(a.id, to: .a)
    current.assign(b.id, to: .c)
    let plan = profile.resolve(tabs: current, windows: [a, b, c, d], applicationURLs: [:])
    #expect(plan.tabs.selected[.b] == a.id)
    #expect(plan.tabs.zone(of: b.id) == .c)
    #expect(plan.tabs.zone(of: c.id) == nil && plan.tabs.zone(of: d.id) == nil)
    #expect(plan.pending == [ambiguous])
    #expect(plan.matches == [savedA.id: a.id])
    #expect(current.zone(of: a.id) == .a)
}

@Test func profileRulesMoveManagedWindowsButWindowDestinationsTakePriority() {
    let url = URL(fileURLWithPath: "/Applications/Editor.app")
    let id = UUID()
    let window = WindowSnapshot(
        id: id, pid: 100, appName: "Editor", identity: WindowIdentity(bundleID: "test.editor", title: "Doc"),
        state: OriginalWindowState(frame: .init(x: 0, y: 0, width: 500, height: 500), minimized: false))
    let rule = ApplicationAssignment(url: url, name: "Editor", bundleID: "test.editor", zone: .b)
    var profile = WorkspaceProfile(
        name: "Work", layout: PersistedLayout(applicationAssignments: [rule], template: .splitRight), zoneNames: [:])
    var tabs = TabManager()
    tabs.assign(id, to: .a)
    #expect(profile.resolve(tabs: tabs, windows: [window], applicationURLs: [100: url]).tabs.zone(of: id) == .b)
    profile.layout.tabs = [SavedTab(id: UUID(), identity: window.identity, zone: .c, selected: true)]
    #expect(profile.resolve(tabs: tabs, windows: [window], applicationURLs: [100: url]).tabs.zone(of: id) == .c)
    #expect(profile.resolve(tabs: tabs, windows: [], applicationURLs: [:]).tabs.zone(of: id) == .a)
}
