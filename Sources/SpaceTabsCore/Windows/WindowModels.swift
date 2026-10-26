import CoreGraphics
import Foundation

public struct WindowIdentity: Codable, Equatable, Sendable {
    public let bundleID: String
    public let title: String
    public let document: String?
    public init(bundleID: String, title: String, document: String? = nil) {
        self.bundleID = bundleID
        self.title = title
        self.document = document
    }
}

public struct OriginalWindowState: Codable, Equatable, Sendable {
    /// Global AX coordinates.
    public let frame: CGRect
    public let minimized: Bool
    public init(frame: CGRect, minimized: Bool) {
        self.frame = frame
        self.minimized = minimized
    }
}

public struct WindowSnapshot: Codable, Identifiable, Equatable, Sendable {
    public let id: UUID
    public let pid: Int32
    public let appName: String
    public let identity: WindowIdentity
    public let state: OriginalWindowState
    public let incompatibility: String?
    public var label: String { "\(appName) · \(identity.title.isEmpty ? L10n.tr("Untitled") : identity.title)" }
    public var compatible: Bool { incompatibility == nil }

    public init(
        id: UUID, pid: Int32, appName: String, identity: WindowIdentity,
        state: OriginalWindowState, incompatibility: String? = nil
    ) {
        self.id = id
        self.pid = pid
        self.appName = appName
        self.identity = identity
        self.state = state
        self.incompatibility = incompatibility
    }
}
