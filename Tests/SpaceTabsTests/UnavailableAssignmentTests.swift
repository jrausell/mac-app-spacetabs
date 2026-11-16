import Foundation
import SpaceTabsCore
import Testing

@testable import SpaceTabs

@MainActor @Test func discoveryKeepsClosedWindowAssignmentsAndProfileSnapshotsAcrossRestart() throws {
    let model = AppModel()
    // Block production writes and external window operations in this fixture.
    model.configurationBlocked = true
    model.paused = true
    let original = OriginalWindowState(frame: CGRect(x: 40, y: 60, width: 800, height: 700), minimized: false)
    let windows = ["First", "Closed", "Last"].map { title in
        WindowSnapshot(
            id: UUID(), pid: 123, appName: "Editor",
            identity: WindowIdentity(bundleID: "test.editor", title: title), state: original, windowNumber: nil)
    }
    model.windows = windows
    for window in windows {
        model.tabs.assign(window.id, to: .b)
        model.originals[window.id] = original
    }
    let closed = windows[1]
    model.applyDiscovery(
        ScanResult(windows: [windows[0], windows[2]], warnings: [], removed: [closed.id], focused: nil))
    #expect(model.pendingTabs.map(\.id) == [closed.id])
    #expect(model.tabs.windows[.b] == [windows[0].id, windows[2].id])
    let first = model.sessionManifest(tabs: model.tabs, originals: model.originals)
    #expect(first.tabs.map(\.id) == windows.map(\.id))
    let closedProfile = model.profileLayout()
    #expect(closedProfile.tabs.map(\.id) == windows.map(\.id))
    #expect(closedProfile.tabs.allSatisfy { $0.original == nil && $0.processID == nil && $0.windowNumber == nil })
    model.applyDiscovery(ScanResult(windows: [], warnings: [], removed: Set(windows.map(\.id)), focused: nil))
    #expect(model.tabs.windows[.b, default: []].isEmpty)
    #expect(Set(model.pendingTabs.map(\.id)) == Set(windows.map(\.id)))
    #expect(model.operationTask == nil)

    let folder = FileManager.default.temporaryDirectory.appendingPathComponent("UnavailableAssignments-\(UUID())")
    defer { try? FileManager.default.removeItem(at: folder) }
    let store = PersistenceStore(url: folder.appendingPathComponent("layout.json"))
    try store.save(model.sessionManifest(tabs: model.tabs, originals: model.originals))
    let loaded = try #require(try store.load())
    #expect(loaded.tabs.map(\.id) == windows.map(\.id))
    #expect(loaded.tabs.map(\.identity) == windows.map(\.identity))
    model.forgetPending()
    #expect(model.pendingTabs.isEmpty)
    #expect(model.sessionManifest(tabs: model.tabs, originals: model.originals).tabs.isEmpty)
}

@MainActor @Test func discoveryDoesNotTurnUnmanagedWindowsIntoSavedAssignments() {
    let model = AppModel()
    model.configurationBlocked = true
    model.paused = true
    let window = WindowSnapshot(
        id: UUID(), pid: 123, appName: "Editor", identity: WindowIdentity(bundleID: "test.editor", title: "Unmanaged"),
        state: OriginalWindowState(frame: CGRect(x: 0, y: 0, width: 800, height: 700), minimized: false))
    model.windows = [window]
    model.applyDiscovery(ScanResult(windows: [], warnings: [], removed: [window.id], focused: nil))
    #expect(model.pendingTabs.isEmpty && model.savedTabOrder.isEmpty)
    #expect(model.profileLayout().tabs.isEmpty)
}

@MainActor @Test func restoringARuntimeUUIDPreservesItsSavedPositionAndExplicitReleaseDoesNotResurrectIt() {
    let model = AppModel()
    model.configurationBlocked = true
    let previous = UUID()
    let live = WindowSnapshot(
        id: UUID(), pid: 123, appName: "Editor", identity: WindowIdentity(bundleID: "test.editor", title: "Document"),
        state: OriginalWindowState(frame: CGRect(x: 0, y: 0, width: 800, height: 700), minimized: false))
    let other = SavedTab(
        id: UUID(), identity: WindowIdentity(bundleID: "test.other", title: "Other"), zone: .b, selected: false)
    model.windows = [live]
    model.tabs.assign(live.id, to: .b)
    model.pendingTabs = [SavedTab(id: previous, identity: live.identity, zone: .b, selected: false), other]
    model.savedTabOrder = [previous, other.id]
    let manifest = model.sessionManifest(tabs: model.tabs, originals: [:], excludingPending: [previous])
    #expect(manifest.tabs.map(\.id) == [live.id, other.id])
    model.pendingTabs.removeAll { $0.id == previous }
    model.tabs.remove(live.id)
    let released = model.sessionManifest(tabs: model.tabs, originals: [:])
    #expect(released.tabs.map(\.id) == [other.id])
}
