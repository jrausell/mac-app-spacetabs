import AppKit
import SpaceTabsCore

extension AppModel {
    func layoutVisibleFrame(on screen: NSScreen) -> CGRect {
        LayoutEngine.usableFrame(
            visibleFrame: screen.visibleFrame, screenFrame: screen.frame,
            menuBarHeight: NSStatusBar.system.thickness, safeTopInset: screen.safeAreaInsets.top,
            reserveMenuArea: false)
    }

    func zoneGeometry(on screen: NSScreen, ratio preview: Double? = nil, rowRatio rowPreview: Double? = nil) -> [Zone:
        ZoneGeometry]
    {
        LayoutEngine().desktopGeometry(
            visibleFrame: screen.visibleFrame, screenFrame: screen.frame,
            menuBarHeight: NSStatusBar.system.thickness, safeTopInset: screen.safeAreaInsets.top,
            ratio: preview ?? ratio, reserveHeader: !autoHideTabBars, template: layoutTemplate,
            rowRatio: rowPreview ?? rowRatio)
    }

    func beginColumnResize(rows: Bool = false) {
        reflowTask?.cancel()
        resizingColumns = true
        resizingRows = rows
        columnResizePreview = rows ? rowRatio : ratio
        layoutChanged()
    }

    func previewColumnResize(_ value: Double) {
        guard resizingColumns else { return }
        columnResizePreview = value
        layoutChanged()
    }

    func finishColumnResize(commit: Bool, refresh: Bool = true) {
        guard resizingColumns else { return }
        let preview = columnResizePreview
        columnResizePreview = nil
        resizingColumns = false
        if commit, let preview {
            if resizingRows { rowRatio = preview } else { ratio = preview }
        }
        resizingRows = false
        if refresh { layoutPreferenceChanged() }
    }

    func appearancePreferenceChanged() {
        if let remoteSettings {
            if remoteSettings.state?.tabAppearance != tabAppearance { remoteSettings.send(.appearance(tabAppearance)) }
            return
        }
        layoutChanged()
        appearanceSaveTask?.cancel()
        appearanceSaveTask = Task { [weak self] in
            do { try await Task.sleep(for: .milliseconds(250)) } catch { return }
            self?.saveLayout()
        }
    }

    func tabBarPreferenceChanged() {
        if sendLayoutPreferences() { return }
        layoutPreferenceChanged()
    }

    func setAutoHideTabBars(_ enabled: Bool) {
        autoHideTabBars = enabled
        tabBarPreferenceChanged()
    }

    func setRevealTabsAtTopEdge(_ enabled: Bool) {
        revealTabsAtTopEdge = enabled
        if sendLayoutPreferences() { return }
        layoutChanged()
        saveLayout()
    }

    func setFixedBarsAboveWindows(_ enabled: Bool) {
        tabAppearance.keepFixedBarsBehindWindows = !enabled
        appearancePreferenceChanged()
    }

    func showTabBarsAfterInteraction() {
        // Background bars are raised by Show Tabs, not routine assignments or reflows.
        guard autoHideTabBars || !tabAppearance.keepFixedBarsBehindWindows else { return }
        showTabBars()
    }

    func managedFrames(tabs: TabManager) throws -> [UUID: CGRect] {
        var frames: [UUID: CGRect] = [:]
        for zone in Zone.allCases {
            for id in tabs.windows[zone, default: []] { frames[id] = try targetFrame(zone) }
        }
        return frames
    }

    func layoutPreferenceChanged() {
        if sendLayoutPreferences() { return }
        if let screen { lastVisibleFrame = layoutVisibleFrame(on: screen) }
        layoutChanged()
        reflowTask?.cancel()
        guard !resizingColumns else { return }
        reflowTask = Task { [weak self] in
            do { try await Task.sleep(for: .milliseconds(350)) } catch { return }
            guard let self, !terminating else { return }
            if spaceTransitioning { return }
            if busy || scanning {
                layoutPreferenceChanged()
                return
            }
            if demo { return }
            if originals.isEmpty || paused {
                appliedAutoHideTabBars = autoHideTabBars
                appliedRatio = ratio
                appliedRowRatio = rowRatio
                appliedScreenID = selectedScreenID
                saveLayout()
            } else {
                reapplyLayout()
            }
        }
    }

    func reapplyLayout() {
        if sendToManager(.reapply) { return }
        if demo {
            layoutChanged()
            return
        }
        guard !originals.isEmpty else { return }
        perform {
            do {
                let frames = try self.managedFrames(tabs: self.tabs)
                try await self.windowManager.applyLayout(
                    frames: frames, selected: Zone.allCases.compactMap { self.tabs.selected[$0] })
                self.appliedAutoHideTabBars = self.autoHideTabBars
                self.appliedRatio = self.ratio
                self.appliedRowRatio = self.rowRatio
                self.appliedScreenID = self.selectedScreenID
            } catch {
                self.autoHideTabBars = self.appliedAutoHideTabBars
                self.ratio = self.appliedRatio
                self.rowRatio = self.appliedRowRatio
                self.selectedScreenID = self.appliedScreenID
                if let failure = error as? WindowError, let id = failure.windowID,
                    let window = self.windows.first(where: { $0.id == id })
                {
                    throw WindowError(
                        message: L10n.tr(
                            "Could not resize \(window.appName). The previous layout settings were restored. \(failure.localizedDescription)"
                        ),
                        recoveryStates: failure.recoveryStates, windowID: id)
                }
                throw error
            }
        }
    }
}
