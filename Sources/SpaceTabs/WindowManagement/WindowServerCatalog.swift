import AppKit
import SpaceTabsCore

/// Read once per discovery batch, away from UI and interactive AX sessions.
actor WindowServerCatalog {
    nonisolated let executor = AXQueueExecutor(label: "dev.spacetabs.window-server")
    nonisolated var unownedExecutor: UnownedSerialExecutor { executor.asUnownedSerialExecutor() }

    func windows() -> [WindowServerWindow] { Self.read() }

    nonisolated static func read() -> [WindowServerWindow] {
        guard
            let list = CGWindowListCopyWindowInfo([.optionAll, .excludeDesktopElements], kCGNullWindowID)
                as? [[String: Any]]
        else { return [] }
        return list.compactMap { info in
            guard let pid = info[kCGWindowOwnerPID as String] as? Int32,
                let number = info[kCGWindowNumber as String] as? UInt32,
                let layer = info[kCGWindowLayer as String] as? Int, layer == 0,
                let bounds = info[kCGWindowBounds as String] as? NSDictionary,
                let frame = CGRect(dictionaryRepresentation: bounds as CFDictionary)
            else { return nil }
            return WindowServerWindow(pid: pid, number: number, frame: frame)
        }
    }
}
