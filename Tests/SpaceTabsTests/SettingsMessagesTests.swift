import Foundation
import SpaceTabsCore
import Testing

@testable import SpaceTabs

@MainActor @Test func settingsSnapshotPreservesSelectionsAndPreferencesWithoutStartingManager() throws {
    let host = AppModel()
    let a = UUID()
    let b = UUID()
    host.tabs.assign(a, to: .a)
    host.tabs.assign(b, to: .b)
    host.ratio = 0.22
    host.autoHideTabBars = false
    host.tabAppearance.dragBorderColor = TabColor(0.2, 0.8, 0.3)
    host.workspacePresentationStatus = "Recovered"
    host.assignmentZone = .b
    host.assignmentRequest = 4
    let data = try JSONEncoder().encode(SettingsState(host))
    let decoded = try JSONDecoder().decode(SettingsState.self, from: data)
    let ui = AppModel()
    decoded.apply(to: ui)
    #expect(ui.tabs == host.tabs)
    #expect(ui.ratio == 0.22)
    #expect(ui.tabAppearance == host.tabAppearance)
    #expect(!ui.autoHideTabBars)
    #expect(ui.workspacePresentationStatus == "Recovered")
    #expect(ui.assignmentZone == .b && ui.assignmentRequest == 4)
    #expect(!ui.tabSelectionRunner.isPending)
}

@MainActor @Test func settingsCommandsAreDataAndLayoutBoundsRemainValidated() throws {
    let model = AppModel()
    let valid = SettingsLayoutPreferences(model)
    #expect(valid.isValid)
    let data = try JSONEncoder().encode(SettingsCommand.layout(valid))
    guard case .layout(let restored) = try JSONDecoder().decode(SettingsCommand.self, from: data) else {
        Issue.record("Wrong command")
        return
    }
    #expect(restored == valid)
    model.ratio = 0.1
    #expect(!SettingsLayoutPreferences(model).isValid)
    model.ratio = .nan
    #expect(!SettingsLayoutPreferences(model).isValid)
    #expect(throws: (any Error).self) {
        try JSONDecoder().decode(SettingsCommand.self, from: Data(#"{"execute":{"command":"anything"}}"#.utf8))
    }
}

@MainActor @Test func workspaceRecoveryAlwaysEndsInMainZoneBAcrossTemplatesAndPreviousFocus() {
    let model = AppModel()
    let a = UUID()
    let b = UUID()
    let c = UUID()
    let backgroundB = UUID()
    model.tabs.assign(a, to: .a)
    model.tabs.assign(b, to: .b)
    model.tabs.assign(backgroundB, to: .b, selecting: false)
    model.tabs.assign(c, to: .c)
    let selections = model.tabs.selected
    for template in LayoutTemplate.allCases {
        model.layoutTemplate = template
        for previous in Zone.allCases {
            model.activeZone = previous
            for ratio in [0.2, 0.25, 0.8] {
                model.ratio = ratio
                #expect(model.selectedWindowsForPresentation == (template == .twoColumns ? [a, b] : [a, c, b]))
                #expect(model.tabs.selected == selections)
            }
        }
    }
    model.tabs.remove(b)
    model.tabs.remove(backgroundB)
    #expect(model.selectedWindowsForPresentation == [a, c])
}

@MainActor @Test func customPreferencesAndLoginStateReachIndependentSettingsProcess() throws {
    let host = AppModel()
    host.preferences.zoneNames = [.b: "Main"]
    host.preferences.shortcuts = [8: ShortcutBinding(key: 0, modifiers: 4096 | 2048)]
    host.preferences.profiles = [
        WorkspaceProfile(
            name: "Work", layout: PersistedLayout(ratio: 0.75, template: .splitRight), zoneNames: [.b: "Main"])
    ]
    host.loginNeedsApproval = true
    host.preferencesBlocked = true
    let state = try JSONDecoder().decode(SettingsState.self, from: JSONEncoder().encode(SettingsState(host)))
    let helper = AppModel()
    state.apply(to: helper)
    #expect(helper.preferences == host.preferences)
    #expect(helper.loginNeedsApproval && !helper.loginEnabled)
    #expect(helper.preferencesBlocked)
    #expect(helper.operationTask == nil && helper.scanTask == nil)
}

@MainActor @Test func shortcutOverridesRejectCollisionsWithUnchangedDefaultsAndRetainReadableLabels() throws {
    try ShortcutManager.validateBindings([:])
    let action = ShortcutManager.Action.showTabs
    let binding = ShortcutBinding(key: 0, modifiers: 4096 | 2048 | 512)
    try ShortcutManager.validateBindings([action.rawValue: binding])
    #expect(binding.display == "⌃⌥⇧A")
    #expect(action.defaultBinding.display == "⌃⌥T")
    #expect(throws: (any Error).self) {
        try ShortcutManager.validateBindings([action.rawValue: ShortcutManager.Action.focusA.defaultBinding])
    }
    #expect(throws: (any Error).self) {
        try ShortcutManager.validateBindings([action.rawValue: ShortcutBinding(key: 0, modifiers: 512)])
    }
}

@MainActor @Test func knownTabChoiceDoesNotWaitForUnrelatedDiscovery() async {
    let model = AppModel()
    let first = UUID()
    let second = UUID()
    model.tabs.assign(first, to: .b)
    model.tabs.assign(second, to: .b, selecting: false)
    model.scanning = true
    model.refreshInFlight = true
    model.configurationBlocked = true  // Never write the user's configuration.
    model.select(second, zone: .b, requestFocus: false)
    for _ in 0..<50 {
        if model.tabs.selected[.b] == second { break }
        try? await Task.sleep(for: .milliseconds(5))
    }
    #expect(model.tabs.selected[.b] == second)
    #expect(model.scanning && model.refreshInFlight)
    #expect(model.selectionTimings.count == 1)
    model.tabSelectionRunner.cancel()
}

@MainActor @Test func newShortcutDefaultsNeverTakeOverAnExistingCustomBinding() throws {
    let custom = ShortcutBinding(key: 49, modifiers: 4096 | 2048)
    let migrated = ShortcutManager.migratedBindings([ShortcutManager.Action.showTabs.rawValue: custom])
    #expect(migrated[ShortcutManager.Action.showTabs.rawValue] == custom)
    #expect(migrated[ShortcutManager.Action.quickSwitcher.rawValue]?.enabled == false)
    try ShortcutManager.validateBindings(migrated)
    #expect(ShortcutManager.migratedBindings(migrated) == migrated)
    try ShortcutManager.validateBindings([:])
    let old = Data(#"{"key":17,"modifiers":6144}"#.utf8)
    #expect(try JSONDecoder().decode(ShortcutBinding.self, from: old).enabled)
}

@MainActor @Test func staleDiscoveryCannotDiscardAWindowAdoptedByTheUserDuringTheScan() {
    let model = AppModel()
    model.configurationBlocked = true
    let id = UUID()
    let window = WindowSnapshot(
        id: id, pid: 12345, appName: "Editor", identity: WindowIdentity(bundleID: "test.editor", title: "Adopted"),
        state: OriginalWindowState(frame: .init(x: 0, y: 0, width: 500, height: 600), minimized: false))
    model.windows = [window]
    model.tabs.assign(id, to: .b)
    model.applyDiscovery(ScanResult(windows: [], warnings: [], removed: [], focused: nil))
    #expect(model.windows.map(\.id) == [id] && model.tabs.selected[.b] == id)
    model.paused = true
    model.applyDiscovery(ScanResult(windows: [], warnings: [], removed: [id], focused: nil))
    #expect(model.windows.isEmpty && model.tabs.zone(of: id) == nil)
}

@MainActor @Test func registeredActionIDsRemainInsideThePersistedShortcutSchema() {
    let ids = Set(ShortcutManager.Action.allCases.map(\.rawValue))
    #expect(ids.count == ShortcutManager.Action.allCases.count)
    #expect(ids.allSatisfy { (1...UInt32(PreferenceLimits.shortcutActions)).contains($0) })
}

@MainActor @Test func languageChoiceUsesTheTypedSettingsCommandAndSnapshot() throws {
    let command = try JSONDecoder().decode(
        SettingsCommand.self, from: JSONEncoder().encode(SettingsCommand.language(.spanish)))
    guard case .language(let language) = command else {
        Issue.record("Expected a language command")
        return
    }
    #expect(language == .spanish)
    // Change the wire payload rather than process-global localization, so this
    // test can run beside other app tests without changing their language.
    let state = SettingsState(AppModel())
    var payload = try #require(JSONSerialization.jsonObject(with: JSONEncoder().encode(state)) as? [String: Any])
    var preferences = try #require(payload["preferences"] as? [String: Any])
    preferences["language"] = "es"
    payload["preferences"] = preferences
    let decoded = try JSONDecoder().decode(
        SettingsState.self, from: JSONSerialization.data(withJSONObject: payload))
    #expect(decoded.preferences.language == .spanish)
    #expect(SettingsSection.general.title == L10n.text("General"))
}
