import Foundation
import SpaceTabsCore
import Testing

@testable import SpaceTabs

@MainActor @Test func profileRenameUsesTypedSettingsAndKeepsItsSavedRecipeAndLinks() throws {
    let folder = FileManager.default.temporaryDirectory.appendingPathComponent("ProfileRename-\(UUID())")
    defer { try? FileManager.default.removeItem(at: folder) }
    let store = UserPreferencesStore(url: folder.appendingPathComponent("preferences.json"))
    let manager = AppModel(preferencesStore: store)
    let savedTab = SavedTab(
        id: UUID(), identity: WindowIdentity(bundleID: "test.editor", title: "Draft"), zone: .b, selected: true)
    let profile = WorkspaceProfile(
        name: "Work", layout: PersistedLayout(ratio: 0.33, tabs: [savedTab]), zoneNames: [.b: "Code"],
        openAssignedApps: true)
    let other = WorkspaceProfile(name: "Personal", layout: PersistedLayout(), zoneNames: [:])
    manager.preferences.profiles = [profile, other]
    manager.preferences.displayProfiles = ["test-display": profile.id]
    try store.save(manager.preferences)
    manager.ratio = 0.7
    manager.workspaceID = UUID()
    manager.workspaceName = "Independent workspace"
    manager.paused = true
    var profileSaves = 0
    manager.profileSaved = { _ in profileSaves += 1 }
    let helper = AppModel()
    var packets: [SettingsPacket] = []
    let remote = RemoteSettingsModel(model: helper, sendPacket: { packets.append($0) })
    helper.remoteSettings = remote
    remote.receive(SettingsPacket(kind: .state, data: try JSONEncoder().encode(SettingsState(manager))))
    helper.renameProfile(profile.id, name: "  Trabajo · José 🧭  ")
    #expect(manager.preferences.profiles[0] == profile)
    SettingsHost(model: manager).receive(try #require(packets.last).data)
    var expected = profile
    expected.name = "Trabajo · José 🧭"
    #expect(manager.preferences.profiles == [expected, other])
    #expect(try store.load().profiles == [expected, other])
    #expect(manager.preferences.displayProfiles == ["test-display": profile.id])
    #expect(manager.workspaceName == "Independent workspace")
    #expect(manager.ratio == 0.7 && manager.paused)
    #expect(profileSaves == 0)
    #expect(manager.profileLaunchTask == nil && manager.operationTask == nil)
    remote.receive(SettingsPacket(kind: .state, data: try JSONEncoder().encode(SettingsState(manager))))
    #expect(helper.preferences.profiles[0] == expected)
}

@MainActor @Test func profileRenameRejectsInvalidNamesUnknownIDsAndBlockedPreferences() throws {
    let folder = FileManager.default.temporaryDirectory.appendingPathComponent("ProfileRenameValidation-\(UUID())")
    defer { try? FileManager.default.removeItem(at: folder) }
    let store = UserPreferencesStore(url: folder.appendingPathComponent("preferences.json"))
    let model = AppModel(preferencesStore: store)
    let profile = WorkspaceProfile(name: "Original", layout: PersistedLayout(), zoneNames: [:])
    model.preferences.profiles = [profile]
    try store.save(model.preferences)
    for invalid in ["", " \n ", String(repeating: "x", count: PreferenceLimits.profileNameCharacters + 1)] {
        model.renameProfile(profile.id, name: invalid)
        #expect(model.preferences.profiles == [profile])
        #expect(try store.load().profiles == [profile])
    }
    model.renameProfile(UUID(), name: "Unknown")
    model.preferencesBlocked = true
    model.renameProfile(profile.id, name: "Blocked")
    #expect(model.preferences.profiles == [profile])
    #expect(try store.load().profiles == [profile])
    model.preferencesBlocked = false
    let boundary = String(repeating: "é", count: PreferenceLimits.profileNameCharacters)
    model.renameProfile(profile.id, name: boundary)
    #expect(try store.load().profiles[0].name == boundary)
}

@MainActor @Test func failedProfileRenameKeepsTheLastSavedAndPublishedName() throws {
    let folder = FileManager.default.temporaryDirectory.appendingPathComponent("ProfileRenameFailure-\(UUID())")
    defer { try? FileManager.default.removeItem(at: folder) }
    let store = UserPreferencesStore(url: folder.appendingPathComponent("preferences.json"))
    let model = AppModel(preferencesStore: store)
    let profile = WorkspaceProfile(name: "Original", layout: PersistedLayout(), zoneNames: [:])
    model.preferences.profiles = [profile]
    try store.save(model.preferences)
    let backup = folder.appendingPathComponent("saved.json")
    try FileManager.default.moveItem(at: store.url, to: backup)
    try FileManager.default.createDirectory(at: store.url, withIntermediateDirectories: false)
    model.renameProfile(profile.id, name: "Unsaved")
    #expect(model.preferences.profiles == [profile])
    #expect(try UserPreferencesStore(url: backup).load().profiles == [profile])
    #expect(model.message != nil)
}

@MainActor @Test func workspaceRenamePersistsIndependentlyAndRefreshesAllSettingsSummaries() throws {
    let folder = FileManager.default.temporaryDirectory.appendingPathComponent("WorkspaceRename-\(UUID())")
    defer { try? FileManager.default.removeItem(at: folder) }
    let preferences = UserPreferencesStore(url: folder.appendingPathComponent("preferences.json"))
    let store = WorkspaceStore(url: folder.appendingPathComponent("workspaces.json"))
    let profile = WorkspaceProfile(name: "Saved recipe", layout: PersistedLayout(), zoneNames: [:])
    let discovery = AppModel(preferencesStore: preferences)
    discovery.preferences.profiles = [profile]
    try preferences.save(discovery.preferences)
    let savedTab = SavedTab(
        id: UUID(), identity: WindowIdentity(bundleID: "test.editor", title: "Closed"), zone: .b, selected: true)
    let first = WorkspaceRecord(
        name: "First", profileID: profile.id, displayID: "one", layout: PersistedLayout(tabs: [savedTab]),
        zoneNames: [.b: "Code"])
    let second = WorkspaceRecord(name: "Second", displayID: "two")
    try store.save(WorkspaceDocument(records: [first, second]))
    let coordinator = WorkspaceCoordinator(discovery: discovery, store: store)
    coordinator.start()
    defer { coordinator.stop() }
    let work = try #require(coordinator.runtimes[first.id]?.model)
    let personal = try #require(coordinator.runtimes[second.id]?.model)
    work.paused = true
    let host = SettingsHost(model: work)
    let wrongTarget = try JSONEncoder().encode(
        SettingsCommandEnvelope(workspaceID: first.id, command: .renameWorkspace(second.id, "Wrong target")))
    host.receive(wrongTarget)
    #expect(personal.workspaceName == second.name)
    let command = try JSONEncoder().encode(
        SettingsCommandEnvelope(workspaceID: first.id, command: .renameWorkspace(first.id, "  Equipo · José 🧭  ")))
    host.receive(command)
    var expected = first
    expected.name = "Equipo · José 🧭"
    #expect(coordinator.document.records == [expected, second])
    #expect(try store.load()?.records == [expected, second])
    #expect(work.workspaceName == expected.name && work.paused)
    #expect(work.pendingTabs == [savedTab])
    #expect(personal.workspaceSummaries.first?.name == expected.name)
    #expect(!work.workspaceDesktopAvailable && work.operationTask == nil)
    #expect(work.preferences.profiles == [profile])
    let helper = AppModel()
    let snapshot = try JSONDecoder().decode(SettingsState.self, from: JSONEncoder().encode(SettingsState(work)))
    snapshot.apply(to: helper)
    #expect(helper.workspaceName == expected.name)
    #expect(helper.workspaceSummaries.first?.name == expected.name)
    // Later checkpoints and a restart must not restore the original name captured at startup.
    try work.checkpoint(tabs: work.tabs, originals: work.originals)
    let restarted = WorkspaceCoordinator(discovery: AppModel(preferencesStore: preferences), store: store)
    restarted.start()
    defer { restarted.stop() }
    #expect(restarted.runtimes[first.id]?.model.workspaceName == expected.name)
    // A delayed command from a previously selected Settings context is rejected.
    host.useModel(personal)
    let stale = try JSONEncoder().encode(
        SettingsCommandEnvelope(workspaceID: first.id, command: .renameWorkspace(first.id, "Stale request")))
    host.receive(stale)
    #expect(personal.workspaceName == second.name)
    #expect(coordinator.document.records[0].name == expected.name)
    // Profile renaming also propagates, without rebinding or renaming this workspace.
    work.renameProfile(profile.id, name: "Renamed recipe")
    #expect(personal.preferences.profiles[0].name == "Renamed recipe")
    #expect(coordinator.document.records[0].name == expected.name)
    #expect(coordinator.document.records[0].profileID == profile.id)
}

@MainActor @Test func workspaceRenameRejectsInvalidNamesAndDoesNotPublishFailedWrites() throws {
    let folder = FileManager.default.temporaryDirectory.appendingPathComponent("WorkspaceRenameFailure-\(UUID())")
    defer { try? FileManager.default.removeItem(at: folder) }
    let store = WorkspaceStore(url: folder.appendingPathComponent("workspaces.json"))
    let record = WorkspaceRecord(name: "Original", displayID: "display")
    let original = WorkspaceDocument(records: [record])
    try store.save(original)
    let coordinator = WorkspaceCoordinator(discovery: AppModel(), store: store)
    coordinator.start()
    defer { coordinator.stop() }
    let model = try #require(coordinator.runtimes[record.id]?.model)
    for invalid in ["", " \n ", String(repeating: "x", count: PreferenceLimits.profileNameCharacters + 1)] {
        coordinator.rename(record.id, name: invalid)
        #expect(coordinator.document == original)
        #expect(try store.load() == original)
    }
    coordinator.rename(UUID(), name: "Unknown")
    #expect(coordinator.document == original)
    let backup = folder.appendingPathComponent("saved.json")
    try FileManager.default.moveItem(at: store.url, to: backup)
    try FileManager.default.createDirectory(at: store.url, withIntermediateDirectories: false)
    coordinator.rename(record.id, name: "Unsaved")
    #expect(coordinator.document == original)
    #expect(model.workspaceName == record.name)
    #expect(model.workspaceSummaries.first?.name == record.name)
    #expect(try WorkspaceStore(url: backup).load() == original)
    #expect(model.message != nil)
}
