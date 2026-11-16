import AppKit
import SpaceTabsCore

extension AppModel {
    func assign(
        _ id: UUID, to zone: Zone, requestFocus: Bool = true, duringDiscovery: Bool = false,
        replacingPending savedID: UUID? = nil
    ) {
        if let savedID {
            if sendToManager(.synchronizePendingWindow(savedID, id)) { return }
            guard let saved = pendingTabs.first(where: { $0.id == savedID }), saved.zone == zone,
                windows.contains(where: { $0.id == id && $0.identity.bundleID == saved.identity.bundleID })
            else { return }
        } else if sendToManager(.assign(id, zone)) {
            return
        }
        guard activeZones.contains(zone), windows.first(where: { $0.id == id }).map(eligibleWindow) ?? demo else {
            return
        }
        if demo {
            tabs.assign(id, to: zone)
            layoutChanged()
            showTabBarsAfterInteraction()
            return
        }
        guard tabs.zone(of: id) == nil else { return }
        suppressAutomaticAssignment(for: id)
        let revision = userChoseWindow(in: zone)
        let desktop = desktopRevision
        let placementInput = PlacementInputSnapshot.capture()
        perform(duringDiscovery: duringDiscovery) {
            guard self.windows.first(where: { $0.id == id }).map(self.eligibleWindow) == true else {
                throw CancellationError()
            }
            let original = try await self.windowManager.state(of: id)
            if savedID != nil {
                guard self.desktopRevision == desktop, !self.managementSuspended else { throw CancellationError() }
            }
            var candidate = self.tabs
            candidate.assign(id, to: zone)
            var originalStates = self.originals
            originalStates[id] = original
            let matches = WindowReconciler.matches(
                saved: self.pendingTabs, windows: self.windows, launchDates: self.runningLaunchDates)
            let replaced = savedID.map { Set([$0]) } ?? Set(matches.filter { $0.value == id }.keys)
            let oldOrder = self.savedTabOrder
            do {
                if let savedID { self.savedTabOrder = oldOrder.map { $0 == savedID ? id : $0 } }
                try self.checkpoint(tabs: candidate, originals: originalStates, excludingPending: replaced)
                let frame = try self.targetFrame(zone)
                if self.needsPlacementSettlement(id, recovering: savedID != nil) {
                    try await self.windowManager.placeSettling(id, frame: frame) { [weak self] in
                        await MainActor.run {
                            self?.placementIsCurrent(
                                zone: zone, target: frame, desktop: desktop, interaction: revision,
                                input: placementInput)
                                == true
                        }
                    }
                } else {
                    try await self.windowManager.place(id, frame: frame)
                }
            } catch {
                if !(error is CancellationError) { DiagnosticLog.shared.failure(error, operation: #function) }
                if let failure = error as? WindowError, !failure.recoveryStates.isEmpty {
                    self.originals = originalStates
                    self.tabs = candidate
                    if let savedID {
                        self.pendingTabs.removeAll { $0.id == savedID }
                    } else {
                        self.removePendingMatch(for: id)
                    }
                } else {
                    self.savedTabOrder = oldOrder
                }
                throw error
            }
            self.originals[id] = original
            self.tabs.assign(id, to: zone)
            if let savedID {
                self.pendingTabs.removeAll { $0.id == savedID }
                self.pendingWindowChoices[savedID] = nil
                try await self.windowManager.raise(id, focus: false)
            } else {
                self.removePendingMatch(for: id)
            }
            self.activeZone = zone
            // Configuration places the window without activating its app.
            self.layoutChanged()
            self.showTabBarsAfterInteraction()
            if requestFocus { try await self.focus(id, revision: revision) }
        }
    }

    func assignDraggedWindow(_ snapshot: WindowSnapshot, to destination: Zone) {
        guard eligibleWindow(snapshot) else {
            message = L10n.tr("This window belongs to another workspace or is not available on this desktop.")
            return
        }
        guard activeZones.contains(destination), !busy,
            !managementSuspended, !terminating, !demo, trusted
        else {
            message = L10n.tr("The window was not assigned. Wait for the current operation or resume SpaceTabs.")
            return
        }
        if let index = windows.firstIndex(where: { $0.id == snapshot.id }) {
            windows[index] = snapshot
        } else {
            windows.append(snapshot)
        }
        titles[snapshot.id] = snapshot.label
        guard let source = tabs.zone(of: snapshot.id) else {
            assign(snapshot.id, to: destination, duringDiscovery: true)
            return
        }
        if source != destination {
            move(snapshot.id, to: destination, duringDiscovery: true)
            return
        }
        let revision = userChoseWindow(in: destination)
        perform(duringDiscovery: true) {
            try await self.windowManager.place(snapshot.id, frame: self.targetFrame(destination))
            self.tabs.select(snapshot.id, in: destination)
            self.activeZone = destination
            try await self.focus(snapshot.id, revision: revision)
        }
    }

    func move(_ id: UUID, to destination: Zone, before other: UUID? = nil, duringDiscovery: Bool = false) {
        guard activeZones.contains(destination), let source = tabs.zone(of: id), source != destination else { return }
        if demo {
            tabs.assign(id, to: destination)
            activeZone = destination
            return
        }
        suppressAutomaticAssignment(for: id)
        let revision = userChoseWindow(in: destination)
        perform(duringDiscovery: duringDiscovery) {
            var next = self.tabs
            next.assign(id, to: destination)
            next.reorder(id, in: destination, before: other)
            let replacement = self.tabs.selected[source] == id ? next.selected[source] : nil
            try await self.windowManager.move(
                id, frame: self.targetFrame(destination),
                sourceReplacement: replacement, sourceFrame: self.targetFrame(source))
            self.tabs = next
            self.activeZone = destination
            try await self.focus(id, revision: revision)
        }
    }

    func release(_ id: UUID) {
        if sendToManager(.release(id)) { return }
        if demo {
            tabs.remove(id)
            return
        }
        guard let original = originals[id], let zone = tabs.zone(of: id) else { return }
        suppressAutomaticAssignment(for: id)
        perform(allowPaused: true) {
            var next = self.tabs
            next.remove(id)
            let replacement = self.tabs.selected[zone] == id && !self.paused ? next.selected[zone] : nil
            let frame = try replacement.map { _ in try self.targetFrame(zone) }
            try await self.windowManager.restore(id, state: self.safeRestoration(original))
            self.originals[id] = nil
            self.tabs = next
            if let replacement, let frame {
                do {
                    try await self.windowManager.place(replacement, frame: frame)
                    try await self.windowManager.raise(replacement, focus: false)
                } catch {
                    if !(error is CancellationError) { DiagnosticLog.shared.failure(error, operation: #function) }
                    self.paused = true
                    throw WindowError(
                        message:
                            L10n.tr(
                                "The window was released, but the next tab could not be shown: \(error.localizedDescription)"
                            )
                    )
                }
            }
        }
    }

    func releaseAll() {
        if sendToManager(.releaseAll) { return }
        if !demo && originals.isEmpty {
            applicationAssignments = []
            saveLayout()
            layoutChanged()
            return
        }
        if demo {
            stopDemo()
            return
        }
        perform(allowPaused: true) {
            self.applicationAssignments = []
            var errors: [String] = []
            for (id, original) in self.originals {
                do {
                    try await self.windowManager.restore(id, state: self.safeRestoration(original))
                    self.originals[id] = nil
                    self.tabs.remove(id)
                } catch {
                    if !(error is CancellationError) { DiagnosticLog.shared.failure(error, operation: #function) }
                    errors.append(error.localizedDescription)
                }
            }
            if !errors.isEmpty {
                self.paused = true
                throw WindowError(message: errors.joined(separator: "\n"))
            }
        }
    }
}
