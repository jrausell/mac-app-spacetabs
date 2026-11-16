import AppKit
import SpaceTabsCore

extension AppModel {
    func loadConfiguration() {
        do {
            if var saved = try loadWorkspaceLayout.map({ try $0() }) ?? persistence.load() {
                saved.adapt(to: saved.template)
                tabAppearance = saved.tabAppearance
                applicationAssignments = saved.applicationAssignments
                revealTabsAtTopEdge = saved.revealTabsAtTopEdge
                autoHideTabBars = saved.autoHideTabBars
                appliedAutoHideTabBars = saved.autoHideTabBars
                layoutTemplate = saved.template
                rowRatio = saved.rowRatio
                appliedRowRatio = rowRatio
                ratio = saved.ratio
                selectedScreenID = saved.screenID
                pendingTabs = saved.tabs
                savedTabOrder = saved.tabs.map(\.id)
                appliedRatio = ratio
                appliedScreenID = selectedScreenID
            }
        } catch {
            if !(error is CancellationError) { DiagnosticLog.shared.failure(error, operation: #function) }
            configurationBlocked = true
            message =
                L10n.tr(
                    "The existing configuration has not been changed: \(error.localizedDescription) You can reset it from this panel."
                )
        }
    }

    func sessionManifest(tabs: TabManager, originals: [UUID: OriginalWindowState], excludingPending: Set<UUID> = [])
        -> PersistedLayout
    {
        let live = Zone.allCases.flatMap { zone in
            tabs.windows[zone, default: []].compactMap { id -> SavedTab? in
                guard let snapshot = windows.first(where: { $0.id == id }) else { return nil }
                return SavedTab(
                    id: id, identity: snapshot.identity, zone: zone, selected: tabs.selected[zone] == id,
                    original: originals[id], processID: snapshot.pid,
                    launchDate: NSRunningApplication(processIdentifier: snapshot.pid)?.launchDate,
                    windowNumber: snapshot.windowNumber)
            }
        }
        let pending = pendingTabs.filter { saved in
            !excludingPending.contains(saved.id) && !live.contains { $0.id == saved.id }
        }
        // A recovered window can have a new runtime UUID. Keep its saved slot
        // position when the caller retires the corresponding pending record.
        var matches = WindowReconciler.matches(
            saved: pendingTabs.filter { excludingPending.contains($0.id) }, windows: windows,
            launchDates: runningLaunchDates)
        for (slot, window) in explicitPendingMatches() where excludingPending.contains(slot) && matches[slot] == nil {
            if !matches.values.contains(window) { matches[slot] = window }
        }
        let order = savedTabOrder.map { matches[$0] ?? $0 }
        let savedTabs = SavedTabManifest.merge(live: live, pending: pending, order: order)
        return PersistedLayout(
            ratio: ratio, screenID: selectedScreenID, tabs: savedTabs, autoHideTabBars: autoHideTabBars,
            revealTabsAtTopEdge: revealTabsAtTopEdge, applicationAssignments: applicationAssignments,
            tabAppearance: tabAppearance, template: layoutTemplate, rowRatio: rowRatio)
    }

    func persistLayout(_ layout: PersistedLayout, claims: Set<UUID> = []) throws {
        if let saveWorkspaceLayout { try saveWorkspaceLayout(layout, claims) } else { try persistence.save(layout) }
    }

    func eligibleWindow(_ window: WindowSnapshot) -> Bool {
        windowIsEligible?(window) ?? true
    }

    func eligibleAutomaticWindow(_ window: WindowSnapshot) -> Bool {
        guard eligibleWindow(window) else { return false }
        guard workspaceID != nil, tabs.zone(of: window.id) == nil else { return true }
        guard let screen, let primary = NSScreen.screens.first else { return false }
        let frame = LayoutEngine.appKitFrame(from: window.state.frame, primaryDisplayTop: primary.frame.maxY)
        return screen.frame.contains(CGPoint(x: frame.midX, y: frame.midY))
    }

    func checkpoint(tabs: TabManager, originals: [UUID: OriginalWindowState], excludingPending: Set<UUID> = []) throws {
        guard !configurationBlocked else {
            throw ConfigurationError(L10n.tr("Reset the damaged configuration before managing new windows."))
        }
        let saved = sessionManifest(tabs: tabs, originals: originals, excludingPending: excludingPending)
        try persistLayout(saved, claims: Set(originals.keys))
        savedTabOrder = saved.tabs.map(\.id)
    }

    func retainUnavailableAssignments(_ removed: Set<UUID>) {
        guard !demo, !removed.isEmpty else { return }
        // Capture before discovery drops the snapshots and live tab membership.
        let saved = sessionManifest(tabs: tabs, originals: originals)
        let existing = Set(pendingTabs.map(\.id))
        pendingTabs.append(contentsOf: saved.tabs.filter { removed.contains($0.id) && !existing.contains($0.id) })
        savedTabOrder = saved.tabs.map(\.id)
    }

    func profileLayout() -> PersistedLayout {
        var layout = sessionManifest(tabs: tabs, originals: originals)
        layout.screenID = screen.map { Self.stableDisplayID($0) } ?? selectedScreenID
        layout.tabs = SavedTabManifest.profileTabs(layout.tabs)
        return layout
    }

    func saveLayout() {
        if sendLayoutPreferences() { return }
        guard !demo, !configurationBlocked else { return }
        do { try checkpoint(tabs: tabs, originals: originals) } catch {
            if !(error is CancellationError) { DiagnosticLog.shared.failure(error, operation: #function) }
            message = L10n.tr("Could not save the layout: \(error.localizedDescription)")
        }
    }

    func resetConfiguration() {
        if sendToManager(.reset) { return }
        guard originals.isEmpty, !busy else { return }
        do {
            // Preserve the old file for inspection rather than deleting it.
            if FileManager.default.fileExists(atPath: persistence.url.path) {
                let backup = persistence.url.deletingLastPathComponent().appendingPathComponent(
                    "layout.backup-\(UUID()).json")
                try FileManager.default.copyItem(at: persistence.url, to: backup)
            }
            try persistLayout(
                PersistedLayout(
                    ratio: ratio, screenID: selectedScreenID, autoHideTabBars: autoHideTabBars,
                    revealTabsAtTopEdge: revealTabsAtTopEdge, applicationAssignments: applicationAssignments,
                    tabAppearance: tabAppearance, template: layoutTemplate, rowRatio: rowRatio))
            configurationBlocked = false
            pendingTabs = []
            savedTabOrder = []
            message = L10n.tr("Configuration reset. A copy of the previous file was kept, if one existed.")
        } catch {
            if !(error is CancellationError) { DiagnosticLog.shared.failure(error, operation: #function) }
            message = L10n.tr("Could not reset the configuration: \(error.localizedDescription)")
        }
    }

    var runningLaunchDates: [Int32: Date] {
        Dictionary(
            uniqueKeysWithValues: Set(windows.map(\.pid)).compactMap { pid in
                NSRunningApplication(processIdentifier: pid)?.launchDate.map { (pid, $0) }
            })
    }

    var pendingSessionMatches: [UUID: UUID] {
        var matches = WindowReconciler.matches(
            saved: pendingTabs,
            windows: windows.filter { tabs.zone(of: $0.id) == nil && $0.compatible && eligibleWindow($0) },
            launchDates: runningLaunchDates)
        for (slot, window) in explicitPendingMatches() where matches[slot] == nil {
            if !matches.values.contains(window) { matches[slot] = window }
        }
        return matches
    }

    var restorableCount: Int { pendingSessionMatches.count }

    func removePendingMatch(for id: UUID) {
        let matches = WindowReconciler.matches(saved: pendingTabs, windows: windows, launchDates: runningLaunchDates)
        pendingTabs.removeAll { matches[$0.id] == id }
    }

    func forgetPending() {
        if sendToManager(.forget) { return }
        cancelPendingReopens()
        pendingTabs = []
        saveLayout()
    }

    func restoreSavedSession(automatically: Bool = false) {
        if sendToManager(.restore) { return }
        if automatically {
            if applyAutomaticProfileIfReady() { return }
            guard !pendingTabs.isEmpty, !tabSelectionRunner.isPending, !busy, !scanning, !refreshInFlight,
                !managementSuspended, !demo, !terminating, !configurationBlocked, discoveryStatus.canReportMatches
            else { return }
        }
        guard discoveryStatus.canReportMatches else {
            recheckPermission()
            return
        }
        let matches =
            automatically
            ? sessionRestoration.takeMatches(
                saved: pendingTabs,
                windows: windows.filter { tabs.zone(of: $0.id) == nil && $0.compatible && eligibleWindow($0) },
                launchDates: runningLaunchDates, explicitMatches: explicitPendingMatches())
            : pendingSessionMatches
        guard !matches.isEmpty else {
            if automatically { return }
            message =
                L10n.tr(
                    "No unique matches were found. Open the saved windows or assign them manually. Duplicate titles are not restored automatically."
                )
            return
        }
        let revision = presentationRevision
        let desktop = desktopRevision
        let placementInput = PlacementInputSnapshot.capture()
        let explicit = Set(matches.keys.filter { pendingReopens[$0] != nil })
        perform {
            self.restoringTabZones = Set(self.pendingTabs.filter { matches[$0.id] != nil }.map(\.zone))
            defer { self.restoringTabZones.removeAll() }
            var next = self.tabs
            var originalStates = self.originals
            for saved in self.pendingTabs {
                guard let id = matches[saved.id], let live = self.windows.first(where: { $0.id == id }) else {
                    continue
                }
                next.assign(id, to: saved.zone, selecting: !automatically || self.tabs.selected[saved.zone] == nil)
                // Reuse the recovery frame only for a uniquely matched document
                // in the exact same running application instance.
                let sameProcess =
                    !explicit.contains(saved.id) && saved.processID == live.pid && saved.launchDate != nil
                    && saved.launchDate == NSRunningApplication(processIdentifier: live.pid)?.launchDate
                let documentKnown = !(saved.identity.document ?? "").isEmpty
                originalStates[id] = sameProcess && documentKnown ? (saved.original ?? live.state) : live.state
            }
            for saved in self.pendingTabs
            where saved.selected && (!automatically || self.explicitSelectionRevision[saved.zone, default: 0] == 0) {
                if let id = matches[saved.id] { next.select(id, in: saved.zone) }
            }
            next.restoreOrder(self.savedTabOrder.map { matches[$0] ?? $0 })
            if !explicit.isEmpty {
                guard self.desktopRevision == desktop, !self.managementSuspended,
                    explicit.allSatisfy({ self.pendingReopens[$0] != nil })
                else { throw CancellationError() }
            }
            let previousOrder = self.savedTabOrder
            try self.checkpoint(tabs: next, originals: originalStates, excludingPending: Set(matches.keys))
            var frames: [UUID: CGRect] = [:]
            for saved in self.pendingTabs {
                if let id = matches[saved.id] { frames[id] = try self.targetFrame(saved.zone) }
            }
            do {
                let selected = self.activeZones.compactMap { next.selected[$0] }
                let settling = Set(
                    matches.compactMap { slot, window in
                        self.needsPlacementSettlement(window, recovering: explicit.contains(slot)) ? window : nil
                    })
                let settlingTargets = self.pendingTabs.compactMap { saved -> (Zone, CGRect)? in
                    guard let id = matches[saved.id], settling.contains(id), let frame = frames[id] else {
                        return nil
                    }
                    return (saved.zone, frame)
                }
                try await self.windowManager.applyLayout(frames: frames, selected: selected, settling: settling) {
                    [weak self] in
                    await MainActor.run {
                        guard let self else { return false }
                        return settlingTargets.allSatisfy { zone, frame in
                            self.placementIsCurrent(
                                zone: zone, target: frame, desktop: desktop, interaction: revision,
                                input: placementInput)
                        }
                    }
                }
                if !automatically || revision == 0 { try await self.raiseSelections(selected, revision: revision) }
            } catch {
                if !(error is CancellationError) { DiagnosticLog.shared.failure(error, operation: #function) }
                if let failure = error as? WindowError, !failure.recoveryStates.isEmpty {
                    self.tabs = next
                    self.originals = originalStates
                    self.pendingTabs.removeAll { matches[$0.id] != nil }
                } else {
                    self.savedTabOrder = previousOrder
                }
                throw error
            }
            self.tabs = next
            self.originals = originalStates
            self.pendingTabs.removeAll { matches[$0.id] != nil }
            for id in matches.values { self.suppressAutomaticAssignment(for: id) }
            self.message =
                self.pendingTabs.isEmpty
                ? L10n.tr("Session restored\(automatically ? L10n.tr(" automatically") : "").")
                : L10n.tr(
                    "Restored \(matches.count) windows. \(self.pendingTabs.count) remain pending and will be checked when available."
                )
        }
    }
}
