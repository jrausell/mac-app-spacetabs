import AppKit
import SpaceTabsCore

extension AppModel {
    func changeTemplate(_ destination: LayoutTemplate) {
        if sendToManager(.template(destination)) { return }
        guard destination != layoutTemplate, !busy, !scanning, !resizingColumns, !terminating else { return }
        guard !configurationBlocked else {
            message = L10n.tr("Reset the configuration before changing the template.")
            return
        }
        reflowTask?.cancel()
        let previousTemplate = layoutTemplate
        let previousRatio = ratio
        let previousRows = rowRatio
        let previousPending = pendingTabs
        let previousRules = applicationAssignments
        var next = tabs
        next.adapt(to: destination)
        if demo, destination != .twoColumns, next.windows[.c, default: []].isEmpty {
            for index in 1...2 {
                let id = UUID()
                titles[id] = L10n.tr("Demo C · \(index)")
                next.assign(id, to: .c)
            }
        }
        var saved = PersistedLayout(tabs: pendingTabs, applicationAssignments: applicationAssignments)
        saved.adapt(to: destination)
        let updatePreferences = {
            self.layoutTemplate = destination
            self.ratio = destination.defaultRatio
            self.rowRatio = 0.5
            self.pendingTabs = saved.tabs
            self.applicationAssignments = saved.applicationAssignments
        }
        let commit = {
            self.tabs = next
            self.appliedRatio = self.ratio
            self.appliedRowRatio = self.rowRatio
            if !self.activeZones.contains(self.activeZone) { self.activeZone = .a }
            if let zone = self.assignmentZone, !self.activeZones.contains(zone) { self.assignmentZone = .a }
            self.message =
                destination == .twoColumns
                ? L10n.tr("Two columns. Tabs from C are moved into A.")
                : L10n.tr(
                    "Three zones: A above C, with B as the main zone. Drag the vertical arrow handle to adjust the rows."
                )
        }
        if originals.isEmpty || demo {
            updatePreferences()
            commit()
            saveLayout()
            layoutChanged()
            return
        }
        perform(allowPaused: true) {
            updatePreferences()
            do {
                try self.checkpoint(tabs: next, originals: self.originals)
                if !self.paused {
                    let frames = try self.managedFrames(tabs: next)
                    try await self.windowManager.applyLayout(
                        frames: frames, selected: destination.zones.compactMap { next.selected[$0] })
                }
                commit()
            } catch {
                self.layoutTemplate = previousTemplate
                self.ratio = previousRatio
                self.rowRatio = previousRows
                self.pendingTabs = previousPending
                self.applicationAssignments = previousRules
                throw error
            }
        }
    }
}
