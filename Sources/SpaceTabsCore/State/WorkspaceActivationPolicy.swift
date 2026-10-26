/// Activation belongs to the workspace, independently of any Settings window.
/// Keep explicit Settings activation suppressed across duplicate AppKit and
/// NSWorkspace notifications, until leaving the app or explicitly reopening it.
public struct WorkspaceActivationPolicy: Sendable {
    public var ready = false
    private var openingSettings = false
    public init() {}
    public mutating func settingsRequested() { openingSettings = true }
    public mutating func applicationActivated(isSpaceTabs: Bool) -> Bool {
        guard isSpaceTabs else {
            openingSettings = false
            return false
        }
        return ready && !openingSettings
    }
    public mutating func reopenRequested() -> Bool {
        openingSettings = false
        return ready
    }
}
