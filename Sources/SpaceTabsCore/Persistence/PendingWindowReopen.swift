import Foundation

/// A user explicitly requested this saved tab's app to reopen. Existing Window
/// Server numbers exclude windows on other desktops as well as visible windows.
public struct PendingWindowReopen: Sendable {
    public let existingWindowNumbers: Set<UInt32>
    public init(existingWindowNumbers: Set<UInt32>) {
        self.existingWindowNumbers = existingWindowNumbers
    }

    public func candidate(for saved: SavedTab, windows: [WindowSnapshot], assigned: Set<UUID>) -> UUID? {
        let candidates = windows.filter { window in
            guard window.compatible, !assigned.contains(window.id),
                window.identity.bundleID == saved.identity.bundleID,
                let number = window.windowNumber, !existingWindowNumbers.contains(number)
            else { return false }
            // Reopening an app is not permission to replace a saved document.
            if let document = saved.identity.document, !document.isEmpty {
                return window.identity.document == document
            }
            return true
        }
        return candidates.count == 1 ? candidates.first?.id : nil
    }
}
