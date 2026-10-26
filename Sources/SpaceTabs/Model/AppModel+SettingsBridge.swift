import AppKit
import SpaceTabsCore

@MainActor extension AppModel {
    @discardableResult func sendToManager(_ command: SettingsCommand) -> Bool {
        guard let remoteSettings else { return false }
        remoteSettings.send(command)
        return true
    }
    func sendLayoutPreferences() -> Bool {
        guard let remoteSettings else { return false }
        if let state = remoteSettings.state,
            state.ratio == ratio, state.rowRatio == rowRatio, state.selectedScreenID == selectedScreenID,
            state.autoHideTabBars == autoHideTabBars, state.revealTabsAtTopEdge == revealTabsAtTopEdge
        {
            return true
        }
        remoteSettings.send(.layout(SettingsLayoutPreferences(self)))
        return true
    }
    func clearAssignmentFilter() {
        if sendToManager(.filter(nil)) { return }
        assignmentZone = nil
    }
    func dismissMessage() {
        if sendToManager(.clearMessage) { return }
        message = nil
    }
    func revealApplication() {
        if sendToManager(.revealApplication) { return }
        PermissionService.revealCurrentApplication()
    }
}
