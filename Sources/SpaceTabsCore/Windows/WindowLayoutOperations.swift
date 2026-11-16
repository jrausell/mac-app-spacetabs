import CoreGraphics
import Foundation

public protocol WindowLayoutAccess: WindowAccess {
    func raise(_ id: UUID, focus: Bool) async throws
}

public struct WindowLayoutOperations<Backend: WindowLayoutAccess>: Sendable {
    private let backend: Backend
    private let wait: @Sendable (Duration) async throws -> Void
    public init(
        backend: Backend, wait: @escaping @Sendable (Duration) async throws -> Void = { try await Task.sleep(for: $0) }
    ) {
        self.backend = backend
        self.wait = wait
    }

    /// Background reflow changes geometry only. Raising is a separate explicit
    /// choice; otherwise opening Settings could immediately be covered again.
    public func apply(
        frames: [UUID: CGRect], selected: [UUID], raiseSelected: Bool = false,
        settling: Set<UUID> = [], isCurrent: @Sendable () async -> Bool = { true }
    ) async throws {
        try await WindowOperations(backend: backend, wait: wait).execute(
            WindowPlacementPlan.commands(frames: frames, selected: selected), settling: settling, isCurrent: isCurrent)
        if !settling.isEmpty, !(await isCurrent()) { return }
        if raiseSelected { for id in selected where frames[id] != nil { try await backend.raise(id, focus: false) } }
    }
}
