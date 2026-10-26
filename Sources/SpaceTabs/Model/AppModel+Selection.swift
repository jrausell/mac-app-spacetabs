import AppKit
import SpaceTabsCore

extension AppModel {
    func select(_ id: UUID, zone: Zone, requestFocus: Bool = true, fillZone: Bool = false) {
        tabClickCount += 1
        lastTabClick =
            L10n.tr(
                "\(zone.title) · \(windows.first(where: { $0.id == id })?.identity.bundleID ?? id.uuidString) · busy=\(busy) scanning=\(scanning) paused=\(paused)"
            )
        if demo {
            tabs.select(id, in: zone)
            activeZone = zone
            return
        }
        guard tabs.windows[zone, default: []].contains(id), !managementSuspended, !terminating else { return }
        let revision = userChoseWindow(in: zone)
        let selectionStarted = ContinuousClock.now
        tabSelectionRunner.submit { [weak self] in
            guard let self else { return }
            // Geometry/discovery may be in flight. Keep the user's last choice,
            // rather than dropping the click or starting parallel AX operations.
            while busy {
                if Task.isCancelled { return }
                if busy && !switchingTabs, let operationTask {
                    await operationTask.value
                } else {
                    do { try await Task.sleep(for: .milliseconds(20)) } catch { return }
                }
            }
            guard !Task.isCancelled, presentationRevision == revision, !paused, !terminating,
                tabs.windows[zone, default: []].contains(id)
            else { return }
            busy = true
            switchingTabs = true
            do {
                // Only an explicit double click resets manually adjusted geometry.
                // Serialize it with focus so a later click can replace this request.
                try await restoreZoom()
                if fillZone {
                    try await windowManager.place(id, frame: targetFrame(zone))
                    try Task.checkCancellation()
                    guard presentationRevision == revision else { throw CancellationError() }
                }
                if requestFocus { try await focus(id, revision: revision) }
                guard !Task.isCancelled, presentationRevision == revision else { throw CancellationError() }
                tabs.select(id, in: zone)
                activeZone = zone
                selectionTimings.record(selectionStarted.duration(to: .now))
                message = nil
            } catch is CancellationError {} catch {
                message = error.localizedDescription
                if let failure = error as? WindowError, !failure.recoveryStates.isEmpty { paused = true }
            }
            switchingTabs = false
            busy = false
            saveLayout()
            if !terminating {
                layoutChanged()
                scheduleRefresh()
            }
        } onComplete: { [weak self] in
            self?.restoreSavedSession(automatically: true)
            self?.applyApplicationAssignments()
        }
    }

    func noteUserInteraction() {
        workspacePresentationRevision = nil
        workspaceActivationPIDs = []
        presentationRevision += 1
        tabSelectionRunner.cancel()
    }

    func raiseSelections(_ ids: [UUID], revision: Int) async throws {
        for id in ids {
            guard presentationRevision == revision, !managementSuspended, !terminating else { return }
            try await windowManager.raise(id, focus: false)
        }
    }

    @discardableResult func userChoseWindow(in zone: Zone) -> Int {
        noteUserInteraction()
        explicitSelectionRevision[zone, default: 0] += 1
        return presentationRevision
    }

    func focus(_ id: UUID, revision: Int) async throws {
        try await WindowFocusOperations(backend: windowManager).focus(id) { [weak self] in
            await MainActor.run {
                guard let self else { return false }
                return self.presentationRevision == revision && !self.paused && !self.terminating
            }
        }
    }
}
