import Foundation

/// An explicit app-placeholder action may select an existing window. Native
/// window numbers prove current-desktop visibility and keep browser pages from
/// becoming separate choices. Assignment ownership is never transferred here.
public enum PendingAppSynchronization {
    private struct WindowKey: Hashable {
        let pid: Int32
        let number: UInt32
    }

    public static func candidates(
        bundleID: String, windows: [WindowSnapshot], assigned: Set<UUID>, visible: [WindowServerWindow]
    ) -> [WindowSnapshot] {
        let visibleKeys = Set(visible.map { WindowKey(pid: $0.pid, number: $0.number) })
        let ownedKeys = Set(
            windows.compactMap { window -> WindowKey? in
                guard assigned.contains(window.id), let number = window.windowNumber else { return nil }
                return WindowKey(pid: window.pid, number: number)
            })
        var seen = Set<WindowKey>()
        return windows.filter { window in
            guard window.compatible, !assigned.contains(window.id), window.identity.bundleID == bundleID,
                let number = window.windowNumber, number != 0
            else { return false }
            let key = WindowKey(pid: window.pid, number: number)
            return visibleKeys.contains(key) && !ownedKeys.contains(key) && seen.insert(key).inserted
        }
    }
}
