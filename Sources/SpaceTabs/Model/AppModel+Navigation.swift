import AppKit
import SpaceTabsCore

extension AppModel {
    func toggleZoom() {
        if sendToManager(.zoom) { return }
        guard !demo, !managementSuspended, !terminating else { return }
        noteUserInteraction()
        let revision = presentationRevision
        zoomRequestTask?.cancel()
        zoomRequestTask = Task { [weak self] in
            guard let self else { return }
            let target = await FocusedZoomTarget.resolve(from: windowManager, tabs: tabs)
            guard !Task.isCancelled, presentationRevision == revision, !managementSuspended, !terminating else {
                return
            }
            guard let target, let screen else {
                message = L10n.tr("The focused window is not in a SpaceTabs zone. Focus a managed window to zoom it.")
                return
            }
            let id = target.windowID
            let undoing = zoomedWindow?.id == id
            let full = LayoutEngine.accessibilityFrame(
                from: layoutVisibleFrame(on: screen),
                primaryDisplayTop: NSScreen.screens.first?.frame.maxY ?? screen.frame.maxY)
            perform(duringDiscovery: true) {
                // perform() restores any previous temporary zoom first.
                guard self.presentationRevision == revision else { return }
                if !undoing {
                    let before = try await self.windowManager.state(of: id)
                    guard self.presentationRevision == revision, !self.managementSuspended else { return }
                    try await self.windowManager.place(id, frame: full)
                    self.zoomedWindow = ZoomedWindow(id: id, frame: before.frame)
                }
                guard self.presentationRevision == revision else { return }
                self.tabs.select(id, in: target.zone)
                self.activeZone = target.zone
                self.layoutChanged()
            }
        }
    }

    func restoreZoom() async throws {
        guard let zoom = zoomedWindow else { return }
        if originals[zoom.id] == nil {
            zoomedWindow = nil
            return
        }
        try await windowManager.place(zoom.id, frame: zoom.frame)
        zoomedWindow = nil
    }
    func navigate(_ direction: NavigationDirection, moving: Bool) {
        guard let screen,
            let destination = LayoutNavigation.neighbor(
                from: activeZone, direction: direction,
                zones: zoneGeometry(on: screen).mapValues { $0.content.union($0.bar) })
        else { return }
        if moving, let id = tabs.selected[activeZone] {
            move(id, to: destination)
        } else if let id = tabs.selected[destination] {
            select(id, zone: destination)
        } else {
            activeZone = destination
            showTabBars()
        }
    }
    func reorderTab(_ id: UUID, to zone: Zone, before other: UUID? = nil) {
        if sendToManager(.reorderTab(id, zone, other)) { return }
        guard !busy, !scanning, activeZones.contains(zone), let current = tabs.zone(of: id) else { return }
        if current != zone {
            move(id, to: zone, before: other)
            return
        }
        tabs.reorder(id, in: zone, before: other)
        saveLayout()
        layoutChanged()
        showTabBars()
    }
}

struct ZoomedWindow {
    let id: UUID
    let frame: CGRect
}
