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
