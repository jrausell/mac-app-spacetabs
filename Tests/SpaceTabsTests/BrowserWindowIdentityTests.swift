import Foundation
import SpaceTabsCore
import Testing

@testable import SpaceTabs

@MainActor @Test func changingTheActiveBrowserPagePreservesLiveZoneMembershipAndRecoveryState() throws {
    let model = AppModel()
    model.configurationBlocked = true
    let id = UUID()
    let original = OriginalWindowState(frame: .init(x: 0, y: 0, width: 900, height: 700), minimized: false)
    let before = WindowSnapshot(
        id: id, pid: 42, appName: "Browser",
        identity: WindowIdentity(bundleID: "test.browser", title: "Closed page", document: "https://example.test/old"),
        state: original, windowNumber: 101)
    let after = WindowSnapshot(
        id: id, pid: 42, appName: "Browser",
        identity: WindowIdentity(
            bundleID: "test.browser", title: "Remaining page", document: "https://example.test/new"),
        state: original, windowNumber: 101)
    model.windows = [before]
    model.tabs.assign(id, to: .b)
    model.originals[id] = original
    model.applyDiscovery(ScanResult(windows: [after], warnings: [], removed: [], focused: nil))
    #expect(model.tabs.selected[.b] == id && model.tabs.zone(of: id) == .b)
    #expect(model.originals[id] == original)
    #expect(model.windows == [after] && model.titles[id] == after.label)
    #expect(model.operationTask == nil)
    let state = try JSONDecoder().decode(SettingsState.self, from: JSONEncoder().encode(SettingsState(model)))
    let helper = AppModel()
    state.apply(to: helper)
    #expect(helper.windows.first?.windowNumber == 101)
    #expect(helper.tabs.selected[.b] == id)
}
