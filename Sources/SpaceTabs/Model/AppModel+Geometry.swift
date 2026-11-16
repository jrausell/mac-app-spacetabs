import AppKit
import SpaceTabsCore

extension AppModel {
    var screen: NSScreen? {
        if selectedScreenID.isEmpty { return NSScreen.screens.first }
        return NSScreen.screens.first { Self.screenID($0) == selectedScreenID }
    }

    static func screenID(_ screen: NSScreen) -> String {
        (screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber)?.stringValue
            ?? screen.localizedName
    }

    func targetFrame(_ zone: Zone) throws -> CGRect {
        guard let screen, let primary = NSScreen.screens.first,
            let rect = zoneGeometry(on: screen)[zone]?.content,
            rect.width >= 100, rect.height >= 100
        else {
            throw WindowError(message: L10n.tr("No display or valid area is available for this zone."))
        }
        return LayoutEngine.accessibilityFrame(from: rect, primaryDisplayTop: primary.frame.maxY)
    }

    func placementIsCurrent(zone: Zone, target: CGRect, desktop: Int, interaction: Int, input: PlacementInputSnapshot)
        -> Bool
    {
        !terminating && !managementSuspended && desktopRevision == desktop && presentationRevision == interaction
            && NSEvent.pressedMouseButtons == 0 && !resizingColumns && !resizingRows
            && PlacementInputSnapshot.capture() == input
            && (try? targetFrame(zone)) == target
    }

    func needsPlacementSettlement(_ id: UUID, recovering: Bool) -> Bool {
        if recovering { return true }
        guard let window = windows.first(where: { $0.id == id }),
            let launch = NSRunningApplication(processIdentifier: window.pid)?.launchDate
        else { return false }
        return (0...30).contains(Date.now.timeIntervalSince(launch))
    }

    func safeRestoration(_ state: OriginalWindowState) -> OriginalWindowState {
        guard let primary = NSScreen.screens.first else { return state }
        let rect = LayoutEngine.appKitFrame(from: state.frame, primaryDisplayTop: primary.frame.maxY)
        let destination =
            NSScreen.screens.max {
                let a = $0.visibleFrame.intersection(rect)
                let b = $1.visibleFrame.intersection(rect)
                return max(0, a.width * a.height) < max(0, b.width * b.height)
            } ?? primary
        let safe = LayoutEngine.clamped(rect, to: destination.visibleFrame)
        return OriginalWindowState(
            frame: LayoutEngine.accessibilityFrame(from: safe, primaryDisplayTop: primary.frame.maxY),
            minimized: state.minimized)
    }
}
