import Foundation
import SpaceTabsCore
import Testing

@testable import SpaceTabs

@MainActor @Test func windowChoicesRoundTripOverSettingsAndDismissWithoutLosingSavedAssignments() throws {
    let model = AppModel()
    model.configurationBlocked = true
    let saved = SavedTab(
        id: UUID(), identity: WindowIdentity(bundleID: "test.browser", title: "Old page"), zone: .b, selected: false)
    let choices = [UUID(), UUID()]
    model.pendingTabs = [saved]
    model.pendingWindowChoices[saved.id] = choices
    model.pendingWindowMessages[saved.id] = "A synchronization failure"
    let helper = AppModel()
    let state = try JSONDecoder().decode(SettingsState.self, from: JSONEncoder().encode(SettingsState(model)))
    state.apply(to: helper)
    #expect(helper.pendingWindowChoices[saved.id] == choices)
    #expect(helper.pendingWindowMessages[saved.id] == "A synchronization failure")
    SettingsHost(model: model).receive(try JSONEncoder().encode(SettingsCommand.dismissPendingWindowChoice(saved.id)))
    #expect(model.pendingWindowChoices.isEmpty && model.pendingWindowMessages.isEmpty && model.pendingTabs == [saved])
    model.pendingWindowChoices[saved.id] = choices
    model.cancelPendingReopens()
    #expect(model.pendingWindowChoices.isEmpty && model.pendingTabs == [saved])
    #expect(model.operationTask == nil && model.pendingReopenTasks.isEmpty)
}

@MainActor @Test func invalidOrPausedWindowChoiceCommandsNeverStartWindowOperations() throws {
    let model = AppModel()
    model.trusted = true
    let saved = SavedTab(
        id: UUID(), identity: WindowIdentity(bundleID: "test.mail", title: "Inbox"), zone: .b, selected: false)
    model.pendingTabs = [saved]
    let host = SettingsHost(model: model)
    host.receive(try JSONEncoder().encode(SettingsCommand.synchronizePendingWindow(UUID(), UUID())))
    #expect(model.pendingReopenTasks.isEmpty && model.operationTask == nil)
    model.paused = true
    host.receive(try JSONEncoder().encode(SettingsCommand.synchronizePendingWindow(saved.id, UUID())))
    #expect(model.pendingReopenTasks.isEmpty && model.operationTask == nil && model.pendingTabs == [saved])
}
