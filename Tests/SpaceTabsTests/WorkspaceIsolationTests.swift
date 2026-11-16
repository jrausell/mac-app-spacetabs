import Foundation
import SpaceTabsCore
import Testing

@testable import SpaceTabs

@MainActor private final class FakeWorkspaceAnchor: WorkspaceDesktopAnchor {
    var isOnActiveSpace = true
    func close() { isOnActiveSpace = false }
}

@MainActor @Test func workspacesLoadClosedAfterRestartAndCheckpointOnlyTheirOwnAssignments() throws {
    let folder = FileManager.default.temporaryDirectory.appendingPathComponent("WorkspaceIsolation-\(UUID())")
    defer { try? FileManager.default.removeItem(at: folder) }
    let store = WorkspaceStore(url: folder.appendingPathComponent("workspaces.json"))
    let tab = SavedTab(
        id: UUID(), identity: WindowIdentity(bundleID: "test.editor", title: "Work"), zone: .b, selected: true)
    let first = WorkspaceRecord(name: "Work", displayID: "one", layout: PersistedLayout(tabs: [tab]))
    let second = WorkspaceRecord(name: "Personal", displayID: "two")
    try store.save(WorkspaceDocument(records: [first, second]))
    let discovery = AppModel(
        preferencesStore: UserPreferencesStore(url: folder.appendingPathComponent("preferences.json")),
        persistence: PersistenceStore(url: folder.appendingPathComponent("legacy.json")))
    let coordinator = WorkspaceCoordinator(discovery: discovery, store: store)
    coordinator.start()
    defer { coordinator.stop() }
    let work = try #require(coordinator.runtimes[first.id]?.model)
    let personal = try #require(coordinator.runtimes[second.id]?.model)
    #expect(!work.workspaceDesktopAvailable && !personal.workspaceDesktopAvailable)
    #expect(work.pendingTabs == [tab] && personal.pendingTabs.isEmpty)
    #expect(work.windowManager === personal.windowManager)
    #expect(work.windowManager === discovery.windowManager)
    #expect(work.workspaceSummaries.allSatisfy { !$0.isOpen && !$0.isHere })
    #expect(discovery.pendingTabs.isEmpty && !discovery.workspaceDesktopAvailable)
    personal.ratio = 0.6
    personal.preferences.zoneNames[.a] = "Personal"
    try personal.checkpoint(tabs: personal.tabs, originals: personal.originals)
    let saved = try #require(try store.load())
    #expect(saved.records[0] == first)
    #expect(saved.records[1].layout.ratio == 0.6)
    #expect(saved.records[1].layout.tabs.isEmpty)
    #expect(saved.records[1].zoneNames[.a] == "Personal")
    #expect(work.preferences.zoneNames[.a] == nil)
}

@MainActor @Test func legacyMigrationCopiesPendingIntentWithoutOverwritingLegacySession() throws {
    let folder = FileManager.default.temporaryDirectory.appendingPathComponent("WorkspaceMigration-\(UUID())")
    defer { try? FileManager.default.removeItem(at: folder) }
    let legacy = PersistenceStore(url: folder.appendingPathComponent("layout.json"))
    let tab = SavedTab(
        id: UUID(), identity: WindowIdentity(bundleID: "test.editor", title: "Closed"), zone: .a, selected: true)
    let layout = PersistedLayout(screenID: "not-a-connected-display", tabs: [tab], autoHideTabBars: false)
    try legacy.save(layout)
    let model = AppModel(
        preferencesStore: UserPreferencesStore(url: folder.appendingPathComponent("preferences.json")),
        persistence: legacy)
    model.loadConfiguration()
    let store = WorkspaceStore(url: folder.appendingPathComponent("workspaces.json"))
    let coordinator = WorkspaceCoordinator(discovery: model, store: store)
    coordinator.start()
    defer { coordinator.stop() }
    #expect(coordinator.document.records.count == 1)
    #expect(coordinator.document.records[0].layout.tabs == [tab])
    #expect(!coordinator.document.records[0].layout.autoHideTabBars)
    #expect(try legacy.load() == layout)
    #expect(try store.load() == coordinator.document)
}

@MainActor @Test func aWindowAndItsAXAliasCannotBeClaimedByTwoOpenWorkspaces() throws {
    let folder = FileManager.default.temporaryDirectory.appendingPathComponent("WorkspaceOwnership-\(UUID())")
    defer { try? FileManager.default.removeItem(at: folder) }
    let store = WorkspaceStore(url: folder.appendingPathComponent("workspaces.json"))
    let records = [WorkspaceRecord(name: "First", displayID: "one"), WorkspaceRecord(name: "Second", displayID: "two")]
    try store.save(WorkspaceDocument(records: records))
    let coordinator = WorkspaceCoordinator(discovery: AppModel(), store: store)
    coordinator.start()
    defer { coordinator.stop() }
    let first = try #require(coordinator.runtimes[records[0].id])
    let second = try #require(coordinator.runtimes[records[1].id])
    first.anchor = FakeWorkspaceAnchor()
    second.anchor = FakeWorkspaceAnchor()
    first.model.workspaceDesktopAvailable = true
    second.model.workspaceDesktopAvailable = true
    let state = OriginalWindowState(frame: CGRect(x: 20, y: 20, width: 800, height: 700), minimized: false)
    let window = WindowSnapshot(
        id: UUID(), pid: 123, appName: "Editor", identity: WindowIdentity(bundleID: "test.editor", title: "Work"),
        state: state, windowNumber: 42)
    let alias = WindowSnapshot(
        id: UUID(), pid: 123, appName: "Editor", identity: window.identity, state: state, windowNumber: 42)
    first.model.windows = [window]
    second.model.windows = [window, alias]
    var tabs = TabManager()
    tabs.assign(window.id, to: .b)
    // The pre-placement checkpoint reserves ownership before an awaited AX write.
    try first.model.checkpoint(tabs: tabs, originals: [window.id: state])
    #expect(!second.model.eligibleWindow(window))
    #expect(!second.model.eligibleWindow(alias))
    var otherTabs = TabManager()
    otherTabs.assign(alias.id, to: .a)
    let before = try store.load()
    #expect(throws: (any Error).self) { try second.model.checkpoint(tabs: otherTabs, originals: [alias.id: state]) }
    #expect(try store.load() == before)
    // A remembered unavailable slot alone does not claim the other workspace's window.
    second.model.pendingTabs = [
        SavedTab(id: window.id, identity: window.identity, zone: .a, selected: true, original: state)
    ]
    try second.model.checkpoint(tabs: TabManager(), originals: [:])
    #expect(second.reserved.isEmpty)
    #expect(first.reserved == [window.id])
}

@MainActor @Test func settingsRejectCommandsFromThePreviouslySelectedWorkspace() throws {
    let folder = FileManager.default.temporaryDirectory.appendingPathComponent("WorkspaceSettings-\(UUID())")
    defer { try? FileManager.default.removeItem(at: folder) }
    let preferences = UserPreferencesStore(url: folder.appendingPathComponent("preferences.json"))
    let first = AppModel(preferencesStore: preferences)
    let second = AppModel(preferencesStore: preferences)
    first.workspaceID = UUID()
    second.workspaceID = UUID()
    let host = SettingsHost(model: first)
    let data = try JSONEncoder().encode(
        SettingsCommandEnvelope(workspaceID: try #require(first.workspaceID), command: .zoneName(.b, "Work")))
    host.receive(data)
    #expect(first.preferences.zoneNames[.b] == "Work")
    host.useModel(second)
    host.receive(data)
    host.receive(try JSONEncoder().encode(SettingsCommand.zoneName(.b, "Unscoped")))
    #expect(second.preferences.zoneNames[.b] == nil)
    let scoped = try JSONEncoder().encode(
        SettingsCommandEnvelope(workspaceID: try #require(second.workspaceID), command: .zoneName(.b, "Personal")))
    host.receive(scoped)
    #expect(second.preferences.zoneNames[.b] == "Personal")
    #expect(first.preferences.zoneNames[.b] == "Work")
}

@MainActor @Test func desktopMembershipHidesOtherWorkspaceWithoutChangingTabsOrClearingPause() throws {
    let folder = FileManager.default.temporaryDirectory.appendingPathComponent("WorkspaceDesktops-\(UUID())")
    defer { try? FileManager.default.removeItem(at: folder) }
    let store = WorkspaceStore(url: folder.appendingPathComponent("workspaces.json"))
    let records = [
        WorkspaceRecord(name: "Work", displayID: "one"), WorkspaceRecord(name: "Personal", displayID: "one"),
    ]
    try store.save(WorkspaceDocument(records: records))
    let coordinator = WorkspaceCoordinator(discovery: AppModel(), store: store)
    coordinator.start()
    defer { coordinator.stop() }
    let work = try #require(coordinator.runtimes[records[0].id])
    let personal = try #require(coordinator.runtimes[records[1].id])
    let workAnchor = FakeWorkspaceAnchor()
    let personalAnchor = FakeWorkspaceAnchor()
    work.anchor = workAnchor
    personal.anchor = personalAnchor
    workAnchor.isOnActiveSpace = true
    personalAnchor.isOnActiveSpace = false
    let workTab = UUID()
    let personalTab = UUID()
    work.model.tabs.assign(workTab, to: .b)
    personal.model.tabs.assign(personalTab, to: .a)
    work.model.paused = true
    coordinator.updateContexts(connectedDisplays: ["one"], selectVisible: true)
    #expect(work.model.workspaceDesktopAvailable && !personal.model.workspaceDesktopAvailable)
    #expect(coordinator.selectedID == records[0].id)
    workAnchor.isOnActiveSpace = false
    personalAnchor.isOnActiveSpace = true
    coordinator.updateContexts(connectedDisplays: ["one"], selectVisible: true)
    #expect(!work.model.workspaceDesktopAvailable && personal.model.workspaceDesktopAvailable)
    #expect(coordinator.selectedID == records[1].id)
    #expect(work.model.tabs.windows[.b] == [workTab])
    #expect(personal.model.tabs.windows[.a] == [personalTab])
    #expect(work.model.paused)
    personalAnchor.isOnActiveSpace = false
    coordinator.updateContexts(connectedDisplays: ["one"], selectVisible: true)
    #expect(coordinator.models.allSatisfy { !$0.workspaceDesktopAvailable })
    #expect(coordinator.selected.workspaceSummaries.allSatisfy { $0.isOpen && !$0.isHere })
    #expect(coordinator.models.allSatisfy { $0.operationTask == nil })
}
