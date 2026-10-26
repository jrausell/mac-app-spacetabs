import AppKit
import SpaceTabsCore

extension AppModel {
    func saveProfile(name: String, replacing id: UUID? = nil) {
        if sendToManager(.saveProfile(name, id)) { return }
        guard !busy, !resizingColumns, !preferencesBlocked, !configurationBlocked else { return }
        var value = preferences
        let savedWindows = activeZones.flatMap { zone in
            tabs.windows[zone, default: []].compactMap { id -> SavedTab? in
                guard let window = windows.first(where: { $0.id == id }) else { return nil }
                return SavedTab(id: id, identity: window.identity, zone: zone, selected: tabs.selected[zone] == id)
            }
        }
        let layout = PersistedLayout(
            ratio: ratio, screenID: screen.map { Self.stableDisplayID($0) } ?? selectedScreenID, tabs: savedWindows,
            autoHideTabBars: autoHideTabBars, revealTabsAtTopEdge: revealTabsAtTopEdge,
            applicationAssignments: applicationAssignments, tabAppearance: tabAppearance,
            template: layoutTemplate, rowRatio: rowRatio)
        let profile = WorkspaceProfile(
            id: id ?? UUID(), name: name.trimmingCharacters(in: .whitespacesAndNewlines), layout: layout,
            zoneNames: preferences.zoneNames)
        if let id, let index = value.profiles.firstIndex(where: { $0.id == id }) {
            value.profiles[index] = profile
        } else {
            value.profiles.append(profile)
        }
        if commitPreferences(value) { message = L10n.tr("Profile “\(profile.name)” saved.") }
    }
    func deleteProfile(_ id: UUID) {
        if sendToManager(.deleteProfile(id)) { return }
        var value = preferences
        value.profiles.removeAll { $0.id == id }
        value.displayProfiles = value.displayProfiles.filter { $0.value != id }
        commitPreferences(value)
    }
    func applyProfile(_ id: UUID) {
        if sendToManager(.applyProfile(id)) { return }
        guard let profile = preferences.profiles.first(where: { $0.id == id }), !configurationBlocked,
            !preferencesBlocked,
            !busy, !scanning, !resizingColumns, !managementSuspended, !demo
        else { return }
        reflowTask?.cancel()
        pendingAutomaticProfile = nil
        noteUserInteraction()
        let oldLayout = PersistedLayout(
            ratio: ratio, screenID: selectedScreenID, autoHideTabBars: autoHideTabBars,
            revealTabsAtTopEdge: revealTabsAtTopEdge, applicationAssignments: applicationAssignments,
            tabAppearance: tabAppearance, template: layoutTemplate, rowRatio: rowRatio)
        let oldPreferences = preferences
        let oldPending = pendingTabs
        let oldTabs = tabs
        let oldOriginals = originals
        let install: (PersistedLayout) -> Void = { layout in
            self.layoutTemplate = layout.template
            self.ratio = layout.ratio
            self.rowRatio = layout.rowRatio
            // A disconnected display falls back to the main display.
            self.selectedScreenID =
                NSScreen.screens.first(where: {
                    Self.screenID($0) == layout.screenID || Self.stableDisplayID($0) == layout.screenID
                }).map { Self.screenID($0) } ?? ""
            self.autoHideTabBars = layout.autoHideTabBars
            self.revealTabsAtTopEdge = layout.revealTabsAtTopEdge
            self.tabAppearance = layout.tabAppearance
            self.applicationAssignments = layout.applicationAssignments
        }
        perform {
            install(profile.layout)
            let urls = Dictionary(
                uniqueKeysWithValues: Set(self.windows.map(\.pid)).compactMap { pid in
                    NSRunningApplication(processIdentifier: pid)?.bundleURL.map { (pid, $0) }
                })
            let plan = profile.resolve(tabs: self.tabs, windows: self.windows, applicationURLs: urls)
            let next = plan.tabs
            var states = self.originals
            var beforePlacement: [UUID: OriginalWindowState] = [:]
            var placed = false
            do {
                for windowID in self.activeZones.flatMap({ next.windows[$0, default: []] }) {
                    let state = try await self.windowManager.state(of: windowID)
                    beforePlacement[windowID] = state
                    if states[windowID] == nil { states[windowID] = state }
                }
                self.pendingTabs = plan.pending
                let frames = try self.managedFrames(tabs: next)
                try await self.windowManager.applyLayout(
                    frames: frames, selected: profile.layout.template.zones.compactMap { next.selected[$0] })
                placed = true
                self.tabs = next
                self.originals = states
                var value = self.preferences
                value.zoneNames = profile.zoneNames
                guard self.commitPreferences(value) else {
                    throw ConfigurationError(L10n.tr("Could not save the active profile."))
                }
                try self.checkpoint(tabs: next, originals: states)
                self.applicationAssignmentAttempts = [:]
                self.appliedRatio = self.ratio
                self.appliedRowRatio = self.rowRatio
                self.appliedScreenID = self.selectedScreenID
                self.appliedAutoHideTabBars = self.autoHideTabBars
                if !self.activeZones.contains(self.activeZone) { self.activeZone = .b }
                self.message = L10n.tr(
                    "Profile “\(profile.name)” applied. Closed apps will be assigned when you open them.")
                self.showTabBars()
            } catch {
                install(oldLayout)
                self.pendingTabs = oldPending
                self.tabs = oldTabs
                self.originals = oldOriginals
                if let failure = error as? WindowError {
                    for (id, state) in failure.recoveryStates { self.originals[id] = states[id] ?? state }
                }
                self.commitPreferences(oldPreferences)
                // Geometry failures already roll back in applyLayout. Only a
                // subsequent save failure needs a second recovery operation.
                if placed {
                    var failed: [UUID: OriginalWindowState] = [:]
                    for (windowID, state) in beforePlacement {
                        do { try await self.windowManager.restore(windowID, state: self.safeRestoration(state)) } catch
                        {
                            failed[windowID] = states[windowID] ?? state
                            self.originals[windowID] = states[windowID] ?? state
                        }
                    }
                    if !failed.isEmpty {
                        throw WindowError(
                            message: L10n.tr("Part of the previous layout could not be restored. Use Release All."),
                            recoveryStates: failed)
                    }
                }
                throw error
            }
        }
    }
}
