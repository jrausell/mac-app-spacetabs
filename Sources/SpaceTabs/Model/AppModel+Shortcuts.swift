import AppKit
import SpaceTabsCore

extension AppModel {
    func handleShortcut(_ action: ShortcutManager.Action, source: String = L10n.tr("Global keyboard")) {
        if sendToManager(.shortcut(action.rawValue)) { return }
        shortcutEventCount += 1
        if source == L10n.tr("Global keyboard") { globalShortcutEventCount += 1 }
        lastShortcutEvent =
            L10n.tr(
                "\(source) · \(action.title) · \((preferences.shortcuts[action.rawValue] ?? action.defaultBinding).display) · \(Date.now.formatted(date: .omitted, time: .standard)) · paused=\(paused) busy=\(busy)"
            )
        guard !terminating else { return }
        if action == .showTabs {
            showTabBars()
            return
        }
        if action == .quickSwitcher {
            showQuickSwitcher()
            return
        }
        guard !managementSuspended else { return }
        switch action {
        case .focusA, .focusB, .focusC:
            let zone: Zone = action == .focusA ? .a : action == .focusB ? .b : .c
            guard activeZones.contains(zone) else { return }
            activeZone = zone
            if let id = tabs.selected[zone] { select(id, zone: zone) }
        case .previous, .next:
            if let id = tabs.adjacent(in: activeZone, offset: action == .previous ? -1 : 1) {
                select(id, zone: activeZone)
            }
        case .moveA, .moveB, .moveC:
            let zone: Zone = action == .moveA ? .a : action == .moveB ? .b : .c
            guard activeZones.contains(zone) else { return }
            if let id = tabs.selected[activeZone] { move(id, to: zone) }
        case .showTabs, .quickSwitcher: break
        case .zoom: toggleZoom()
        case .focusLeft, .focusRight, .focusUp, .focusDown, .moveLeft, .moveRight, .moveUp, .moveDown:
            let direction: NavigationDirection =
                switch action {
                case .focusLeft, .moveLeft: .left
                case .focusRight, .moveRight: .right
                case .focusUp, .moveUp: .up
                default: .down
                }
            navigate(direction, moving: action.rawValue >= ShortcutManager.Action.moveLeft.rawValue)
        case .release:
            if let id = tabs.selected[activeZone] { release(id) }
        }
    }
}
