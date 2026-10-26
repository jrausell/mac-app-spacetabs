import AppKit
import SpaceTabsCore

extension AppModel {
    func stopDemo() {
        if sendToManager(.demo) { return }
        demo = false
        tabs = TabManager()
        titles = [:]
        layoutChanged()
        refresh()
    }

    func startDemo() {
        if sendToManager(.demo) { return }
        guard originals.isEmpty, !busy else {
            message = L10n.tr("Release managed windows before starting the demo.")
            return
        }
        demo = true
        paused = false
        if screen == nil { selectedScreenID = "" }
        tabs = TabManager()
        titles = [:]
        for zone in activeZones {
            for index in 1...2 {
                let id = UUID()
                titles[id] = L10n.tr("Demo \(zone.title) · \(index)")
                tabs.assign(id, to: zone)
            }
        }
        layoutChanged()
    }
}
