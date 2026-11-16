import Foundation
import Testing

@testable import SpaceTabs

@MainActor @Test func workspaceSettingsPacketOnlyPresentsAnOpenWindowAndNeverReopensClosedSettings() throws {
    let model = AppModel()
    var raised = 0
    let presentation = SettingsWindowPresentation { raised += 1 }
    let remote = RemoteSettingsModel(model: model, sendPacket: { _ in })
    remote.presentIfOpen = { presentation.showIfOpen() }
    model.openSettings = { presentation.show() }
    let packet = try JSONDecoder().decode(
        SettingsPacket.self, from: JSONEncoder().encode(SettingsPacket(kind: .presentIfOpen)))
    remote.receive(packet)
    #expect(raised == 0)
    remote.receive(SettingsPacket(kind: .show))
    #expect(raised == 1)
    remote.receive(packet)
    #expect(raised == 2)
    #expect(presentation.isOpen)
    // A delayed workspace request received after closing must leave Settings closed.
    presentation.closed()
    remote.receive(packet)
    #expect(raised == 2)
    #expect(!presentation.isOpen)
    remote.receive(SettingsPacket(kind: .show))
    #expect(raised == 3)
    #expect(presentation.isOpen)
}

@MainActor @Test func workspaceActivationCanPresentExistingSettingsWithoutManagedWindowsOrAccess() {
    let model = AppModel()
    model.trusted = false
    var completed = 0
    model.presentSelectedWindows(source: "test") { completed += 1 }
    #expect(completed == 1)
    model.paused = true
    model.presentSelectedWindows(source: "test") { completed += 1 }
    #expect(completed == 2)
    model.terminating = true
    model.presentSelectedWindows(source: "test") { completed += 1 }
    #expect(completed == 2)
}

@MainActor @Test func workspaceSettingsPresentationWaitsForRestorationAndSurvivesUnavailableWindows() async {
    let model = AppModel()
    model.trusted = true
    model.configurationBlocked = true
    let missingWindow = UUID()
    model.tabs.assign(missingWindow, to: .b)
    var completed = false
    model.presentSelectedWindows(source: "test") {
        #expect(!model.busy)
        #expect(!model.switchingTabs)
        #expect(model.workspacePresentationRevision == nil)
        #expect(model.message != nil)
        completed = true
    }
    #expect(!completed)
    await model.tabSelectionRunner.wait()
    #expect(completed)
    // No real AX window or app is accessed: the synthetic ID has no owner.
    #expect(model.tabs.selected[.b] == missingWindow)
    model.refreshTask?.cancel()
}

@MainActor @Test func newerUserActionCancelsPendingSettingsPresentationAlongWithWorkspaceRestore() async {
    let model = AppModel()
    model.trusted = true
    model.tabs.assign(UUID(), to: .b)
    model.busy = true
    var completed = false
    model.presentSelectedWindows(source: "test") { completed = true }
    await Task.yield()
    model.noteUserInteraction()
    model.busy = false
    await model.tabSelectionRunner.wait()
    #expect(!completed)
    #expect(!model.busy)
}

@MainActor @Test func visualGuideRequestReachesSettingsWithoutChangingTheWorkspace() throws {
    let manager = AppModel()
    manager.workspaceID = UUID()
    manager.workspaceName = "Synthetic workspace"
    var presentations = 0
    manager.openSettings = { presentations += 1 }
    let host = SettingsHost(model: manager)
    let command = SettingsCommandEnvelope(workspaceID: try #require(manager.workspaceID), command: .openHowTo)
    host.receive(try JSONEncoder().encode(command))
    #expect(presentations == 1)
    #expect(manager.howToRequest == 1)
    let helper = AppModel()
    let remote = RemoteSettingsModel(model: helper, sendPacket: { _ in })
    remote.receive(SettingsPacket(kind: .state, data: try JSONEncoder().encode(SettingsState(manager))))
    #expect(helper.howToRequest == 1)
    #expect(helper.workspaceID == manager.workspaceID)
    #expect(helper.workspaceName == "Synthetic workspace")
    // A request sent by a stale Settings context cannot navigate the newly selected workspace.
    host.receive(try JSONEncoder().encode(SettingsCommandEnvelope(workspaceID: UUID(), command: .openHowTo)))
    #expect(presentations == 1)
    #expect(manager.howToRequest == 1)
}
