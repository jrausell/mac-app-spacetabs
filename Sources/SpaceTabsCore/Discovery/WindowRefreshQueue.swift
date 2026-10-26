import Foundation

public enum WindowRefreshEvent: Sendable {
    case created, destroyed, focusChanged, titleChanged
}

public struct WindowRefreshBatch: Equatable, Sendable {
    public let fullDiscovery: Bool
    public let processIDs: Set<Int32>
    public let focusPID: Int32?
    public var needsDiscovery: Bool { fullDiscovery || !processIDs.isEmpty }
}

/// Only structural events request discovery. Titles are snapshots refreshed by
/// discovery/manual refresh; browser notification titles cannot drive idle work.
public struct WindowRefreshQueue: Sendable {
    private var full = false
    private var processes: Set<Int32> = []
    private var focus: Int32?
    public init() {}
    public var isEmpty: Bool { !full && processes.isEmpty && focus == nil }

    public mutating func request(_ event: WindowRefreshEvent, pid: Int32) {
        switch event {
        case .created, .destroyed: requestDiscovery(pid: pid)
        case .focusChanged: requestFocus(pid: pid)
        case .titleChanged: break
        }
    }
    public mutating func requestDiscovery(pid: Int32? = nil) {
        if let pid {
            if !full { processes.insert(pid) }
        } else {
            full = true
            processes.removeAll()
        }
    }
    public mutating func requestFocus(pid: Int32) { focus = pid }
    public mutating func take() -> WindowRefreshBatch? {
        guard !isEmpty else { return nil }
        let result = WindowRefreshBatch(fullDiscovery: full, processIDs: processes, focusPID: focus)
        self = WindowRefreshQueue()
        return result
    }
}
