import Foundation
import ServiceManagement
import SpaceTabsCore

extension AppModel {
    func refreshLoginStatus() {
        if sendToManager(.loginStatus) { return }
        loginEnabled = SMAppService.mainApp.status == .enabled
        loginNeedsApproval = SMAppService.mainApp.status == .requiresApproval
    }
    func setLoginEnabled(_ enabled: Bool) {
        if sendToManager(.login(enabled)) { return }
        do {
            if enabled { try SMAppService.mainApp.register() } else { try SMAppService.mainApp.unregister() }
            loginMessage = nil
        } catch {
            if !(error is CancellationError) { DiagnosticLog.shared.failure(error, operation: #function) }
            loginMessage = L10n.tr("Could not change launch at login: \(error.localizedDescription)")
        }
        refreshLoginStatus()
    }
    func openLoginSettings() {
        if sendToManager(.loginSettings) { return }
        SMAppService.openSystemSettingsLoginItems()
    }
}
