import Foundation

public protocol ManagedWindowFocusSource: Sendable {
    func focusedManagedID() async -> UUID?
}

public struct FocusedZoomTarget: Equatable, Sendable {
    public let windowID: UUID
    public let zone: Zone
    public static func resolve(from source: some ManagedWindowFocusSource, tabs: TabManager) async -> Self? {
        guard let id = await source.focusedManagedID(), let zone = tabs.zone(of: id) else { return nil }
        return Self(windowID: id, zone: zone)
    }
}
