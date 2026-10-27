import CoreGraphics
import Foundation

public struct WindowAccessError: LocalizedError, Sendable {
    public enum Kind: Sendable { case transient, noValue, invalidWindow, permission, unsupported, invalidValue, other }
    public let kind: Kind
    public let attribute: String
    public let code: Int32?
    public let detail: String
    public var retryable: Bool { kind == .transient || kind == .noValue }
    public var errorDescription: String? {
        "\(attribute): \(detail)\(code.map { L10n.tr(" (AX \($0))") } ?? "")"
    }
    public init(_ kind: Kind, attribute: String, code: Int32? = nil, detail: String) {
        self.kind = kind
        self.attribute = attribute
        self.code = code
        self.detail = detail
    }
}

public struct WindowOperationError: LocalizedError, Sendable {
    public let message: String
    public var recoveryStates: [UUID: OriginalWindowState]
    public let windowID: UUID?
    public var errorDescription: String? { message }
    public init(message: String, recoveryStates: [UUID: OriginalWindowState] = [:], windowID: UUID? = nil) {
        self.message = message
        self.recoveryStates = recoveryStates
        self.windowID = windowID
    }
}

/// A public-API backend supplies live reads and a last *confirmed* frame.
/// Cached geometry is only used to snapshot a minimized window, never to claim
/// that a move succeeded or to skip a requested move on a visible window.
public protocol WindowAccess: Sendable {
    func frame(_ id: UUID) async throws -> CGRect
    func minimized(_ id: UUID) async throws -> Bool
    func cachedFrame(_ id: UUID) async -> CGRect?
    func validatePlacement(_ id: UUID) async throws
    func writeFrame(_ id: UUID, frame: CGRect) async throws
    func writeMinimized(_ id: UUID, minimized: Bool) async throws
}

public enum WindowCommand: Sendable {
    case place(UUID, CGRect)
    case minimize(UUID, Bool)
    case restore(UUID, OriginalWindowState)
    var id: UUID {
        switch self {
        case .place(let id, _), .minimize(let id, _), .restore(let id, _): id
        }
    }
}
