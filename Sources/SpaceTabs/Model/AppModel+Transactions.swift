import AppKit
import SpaceTabsCore

extension AppModel {
    func perform(
        allowPaused: Bool = false, duringDiscovery: Bool = false,
        file: String = #fileID, function: String = #function, line: Int = #line,
        _ work: @escaping @MainActor () async throws -> Void
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
            let trace = DiagnosticOperation(
                function, details: diagnosticContext, file: file, function: function, line: line)
            defer { trace.finish() }
            do {
                try await restoreZoom()
                try await work()
            } catch is CancellationError {
                DiagnosticLog.shared.record("operation.cancelled", details: ["operation": function])
            } catch {
                DiagnosticLog.shared.failure(
                    error, operation: function, details: diagnosticContext, file: file, function: function, line: line)
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
