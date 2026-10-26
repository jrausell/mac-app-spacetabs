import AppKit
import SpaceTabsCore

extension AppModel {
    func openAssignment(for zone: Zone) {
        assignmentZone = zone
        settingsShowsApplications = true
        assignmentRequest += 1
        openSettings()
    }

    func requestPermission() {
        if sendToManager(.permission) { return }
        checkEnvironment()
        guard !trusted else { return }
        PermissionService.openSettings()
    }

    func recheckPermission() {
        if sendToManager(.recheck) { return }
        checkEnvironment()
        if trusted && !hasCompletedDiscovery && !refreshInFlight { startInitialDiscovery() }
    }
}
