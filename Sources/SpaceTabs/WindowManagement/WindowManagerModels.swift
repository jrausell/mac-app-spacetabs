import AppKit
import ApplicationServices
import Foundation
import SpaceTabsCore

extension Notification.Name {
    static let spaceTabsAXChanged = Notification.Name("SpaceTabs.AXChanged")
}

struct ApplicationDescriptor: Sendable {
    let pid: Int32
    let name: String
    let bundleID: String
}

struct ScanResult: Sendable {
    let windows: [WindowSnapshot]
    let warnings: [String]
    let removed: Set<UUID>
    let focused: UUID?
    var notices: [String] = []
}

struct DragCapture: Sendable {
    let token: UUID
    let initialFrame: CGRect
    let title: String
}

typealias WindowError = WindowOperationError
