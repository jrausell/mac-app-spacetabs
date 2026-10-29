import AppKit
import SpaceTabsCore

extension AppModel {
    func cancelWorkspacePresentation(activatedPID: Int32? = nil) {
        guard workspacePresentationRevision != nil else { return }
        // The verified focus sequence intentionally activates these processes.
        if let activatedPID, workspaceActivationPIDs.contains(activatedPID) { return }
        workspacePresentationStatus = L10n.tr("Cancelled by a newer user action")
        noteUserInteraction()
    }

    var selectedWindowsForPresentation: [UUID] {
        // B is the principal space, regardless of template, size or prior focus.
        let orderedZones = activeZones.filter { $0 != .b } + activeZones.filter { $0 == .b }
        return orderedZones.compactMap { tabs.selected[$0] }
    }

    func presentSelectedWindows(source: String) {
        workspacePresentationRequests += 1
        guard trusted, !managementSuspended, !terminating, !demo,
            activeZones.contains(where: { tabs.selected[$0] != nil })
        else {
            workspacePresentationStatus =
                L10n.tr(
                    "\(source): not run; access=\(trusted), paused=\(paused), quitting=\(terminating), selected=\(tabs.selected.count)"
                )
            return
        }
        noteUserInteraction()
        let revision = presentationRevision
        workspacePresentationRevision = revision
        workspacePresentationStatus = L10n.tr("\(source): waiting for pending operations")
        tabSelectionRunner.submit { [weak self] in
            guard let self else { return }
            defer {
                if workspacePresentationRevision == revision {
                    workspacePresentationRevision = nil
                    workspaceActivationPIDs = []
                }
            }
            while busy {
                if Task.isCancelled { return }
                do { try await Task.sleep(for: .milliseconds(20)) } catch { return }
            }
            guard !Task.isCancelled, presentationRevision == revision,
                !paused, !terminating
            else { return }
            let selected = selectedWindowsForPresentation
            workspacePresentationStatus = L10n.tr("\(source): restoring \(selected.count) windows")
            busy = true
            switchingTabs = true
            do {
                try await restoreZoom()
                let errors = try await WindowPresentationOperations(backend: windowManager).present(
                    selected,
                    willFocus: { [weak self] id in
                        await MainActor.run {
                            guard let self, self.workspacePresentationRevision == revision,
                                let pid = self.windows.first(where: { $0.id == id })?.pid
                            else { return }
                            self.workspaceActivationPIDs.insert(pid)
                        }
                    }
                ) { [weak self] in
                    await MainActor.run {
                        guard let self else { return false }
                        return self.presentationRevision == revision && !self.managementSuspended && !self.terminating
                    }
                }
                if let primary = tabs.selected[.b], await windowManager.windowIsFocused(primary) {
                    try Task.checkCancellation()
                    guard presentationRevision == revision else { throw CancellationError() }
                    activeZone = .b
                }
                message = errors.isEmpty ? nil : errors.joined(separator: "\n")
                workspacePresentationStatus = L10n.tr(
                    "\(source): finished; \(selected.count) selected, \(errors.count) errors")
            } catch is CancellationError {
                workspacePresentationStatus = L10n.tr("\(source): cancelled")
            } catch {
                if !(error is CancellationError) { DiagnosticLog.shared.failure(error, operation: #function) }
                message = error.localizedDescription
                workspacePresentationStatus = "\(source): \(error.localizedDescription)"
            }
            switchingTabs = false
            busy = false
            layoutChanged()
            scheduleRefresh()
        } onComplete: { [weak self] in
            self?.restoreSavedSession(automatically: true)
            self?.applyApplicationAssignments()
        }
    }
}
