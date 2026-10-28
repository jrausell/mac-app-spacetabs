import AppKit
import SpaceTabsCore

extension AppModel {
    func loadConfiguration() {
        do {
            if var saved = try persistence.load() {
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
                appliedRatio = ratio
                appliedScreenID = selectedScreenID
            }
        } catch {
            configurationBlocked = true
            message =
                L10n.tr(
                    "The existing configuration has not been changed: \(error.localizedDescription) You can reset it from this panel."
                )
        }
    }

    private func manifest(tabs: TabManager, originals: [UUID: OriginalWindowState], excludingPending: Set<UUID> = [])
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
        // A pending selected tab must not compete with a live selection in the same zone.
        let pending = pendingTabs.filter { saved in
            !excludingPending.contains(saved.id) && !live.contains { $0.id == saved.id }
        }.map { saved in
            SavedTab(
                id: saved.id, identity: saved.identity, zone: saved.zone,
                selected: saved.selected && !live.contains(where: { $0.zone == saved.zone && $0.selected }),
                original: saved.original, processID: saved.processID, launchDate: saved.launchDate,
                windowNumber: saved.windowNumber)
        }
        return PersistedLayout(
            ratio: ratio, screenID: selectedScreenID, tabs: live + pending, autoHideTabBars: autoHideTabBars,
            revealTabsAtTopEdge: revealTabsAtTopEdge, applicationAssignments: applicationAssignments,
            tabAppearance: tabAppearance, template: layoutTemplate, rowRatio: rowRatio)
    }

    func checkpoint(tabs: TabManager, originals: [UUID: OriginalWindowState], excludingPending: Set<UUID> = []) throws {
        guard !configurationBlocked else {
            throw ConfigurationError(L10n.tr("Reset the damaged configuration before managing new windows."))
        }
        try persistence.save(manifest(tabs: tabs, originals: originals, excludingPending: excludingPending))
    }

    func saveLayout() {
        if sendLayoutPreferences() { return }
        guard !demo, !configurationBlocked else { return }
        do { try checkpoint(tabs: tabs, originals: originals) } catch {
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
            try persistence.save(
                PersistedLayout(
                    ratio: ratio, screenID: selectedScreenID, autoHideTabBars: autoHideTabBars,
                    revealTabsAtTopEdge: revealTabsAtTopEdge, applicationAssignments: applicationAssignments,
                    tabAppearance: tabAppearance, template: layoutTemplate, rowRatio: rowRatio))
            configurationBlocked = false
            pendingTabs = []
            message = L10n.tr("Configuration reset. A copy of the previous file was kept, if one existed.")
        } catch { message = L10n.tr("Could not reset the configuration: \(error.localizedDescription)") }
    }

    var runningLaunchDates: [Int32: Date] {
        Dictionary(
            uniqueKeysWithValues: Set(windows.map(\.pid)).compactMap { pid in
                NSRunningApplication(processIdentifier: pid)?.launchDate.map { (pid, $0) }
            })
    }

    var pendingSessionMatches: [UUID: UUID] {
        WindowReconciler.matches(
            saved: pendingTabs,
            windows: windows.filter { tabs.zone(of: $0.id) == nil && $0.compatible }, launchDates: runningLaunchDates)
    }

    var restorableCount: Int { pendingSessionMatches.count }

    func removePendingMatch(for id: UUID) {
        let matches = WindowReconciler.matches(saved: pendingTabs, windows: windows, launchDates: runningLaunchDates)
        pendingTabs.removeAll { matches[$0.id] == id }
    }

    func forgetPending() {
        if sendToManager(.forget) { return }
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
                windows: windows.filter { tabs.zone(of: $0.id) == nil && $0.compatible },
                launchDates: runningLaunchDates)
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
                    saved.processID == live.pid && saved.launchDate != nil
                    && saved.launchDate == NSRunningApplication(processIdentifier: live.pid)?.launchDate
                let documentKnown = !(saved.identity.document ?? "").isEmpty
                originalStates[id] = sameProcess && documentKnown ? (saved.original ?? live.state) : live.state
            }
            for saved in self.pendingTabs
            where saved.selected && (!automatically || self.explicitSelectionRevision[saved.zone, default: 0] == 0) {
                if let id = matches[saved.id] { next.select(id, in: saved.zone) }
            }
            try self.checkpoint(tabs: next, originals: originalStates, excludingPending: Set(matches.keys))
            var frames: [UUID: CGRect] = [:]
            for saved in self.pendingTabs {
                if let id = matches[saved.id] { frames[id] = try self.targetFrame(saved.zone) }
            }
            do {
                let selected = self.activeZones.compactMap { next.selected[$0] }
                try await self.windowManager.applyLayout(frames: frames, selected: selected)
                if !automatically || revision == 0 { try await self.raiseSelections(selected, revision: revision) }
            } catch {
                if let failure = error as? WindowError, !failure.recoveryStates.isEmpty {
                    self.tabs = next
                    self.originals = originalStates
                    self.pendingTabs.removeAll { matches[$0.id] != nil }
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
