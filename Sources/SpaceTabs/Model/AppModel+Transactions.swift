import AppKit
import SpaceTabsCore

extension AppModel {
    func perform(
        allowPaused: Bool = false, duringDiscovery: Bool = false, _ work: @escaping @MainActor () async throws -> Void
    ) {
        guard !terminating else { return }
        guard !busy, !scanning || duringDiscovery else {
            message = L10n.tr("Wait for the current operation to finish.")
            return
        }
        guard !spaceTransitioning else {
            message = L10n.tr("Wait for the desktop transition to finish.")
            return
        }
        guard allowPaused || !paused else {
            message = L10n.tr("Resume SpaceTabs to arrange windows.")
            return
        }
        trusted = PermissionService.trusted
        guard trusted else {
            message = L10n.tr("Grant Accessibility access to continue.")
            return
        }
        busy = true
        operationTask = Task {
            do {
                try await restoreZoom()
                try await work()
            } catch is CancellationError {} catch {
                if let failure = error as? WindowError, !failure.recoveryStates.isEmpty { paused = true }
                message = error.localizedDescription
            }
            busy = false
            saveLayout()
            if !terminating {
                layoutChanged()
                scheduleRefresh()
                restoreSavedSession(automatically: true)
                applyApplicationAssignments()
            }
        }
    }
}
