import Foundation

public protocol WindowFocusAccess: Sendable {
    func prepareFocus(_ id: UUID) async throws
    func requestActivation(_ id: UUID) async -> Bool
    func applicationIsActive(_ id: UUID) async -> Bool
    func raiseAndFocus(_ id: UUID) async throws
    func windowIsFocused(_ id: UUID) async -> Bool
}

/// Activation is asynchronous. Never raise before it settles, and never keep
/// enforcing focus after another user action, such as opening Settings.
public struct WindowFocusOperations<Backend: WindowFocusAccess>: Sendable {
    private let backend: Backend
    private let wait: @Sendable (Duration) async throws -> Void
    private let delays: [Duration] = [
        .zero, .milliseconds(20), .milliseconds(40), .milliseconds(80), .milliseconds(160), .milliseconds(320),
    ]
    public init(
        backend: Backend, wait: @escaping @Sendable (Duration) async throws -> Void = { try await Task.sleep(for: $0) }
    ) {
        self.backend = backend
        self.wait = wait
    }

    public func focus(_ id: UUID, isCurrent: @Sendable () async -> Bool) async throws {
        guard await isCurrent() else { throw CancellationError() }
        try await backend.prepareFocus(id)
        guard await isCurrent() else { throw CancellationError() }
        guard await backend.requestActivation(id) else {
            throw WindowOperationError(message: L10n.tr("macOS did not allow the selected app to activate."))
        }
        var active = false
        for delay in delays {
            if delay != .zero { try await wait(delay) }
            guard await isCurrent() else { throw CancellationError() }
            if await backend.applicationIsActive(id) {
                active = true
                break
            }
        }
        guard active else {
            throw WindowOperationError(
                message: L10n.tr("The app did not confirm activation. The selected tab has not changed."))
        }
        guard await isCurrent() else { throw CancellationError() }
        try await backend.raiseAndFocus(id)
        for delay in delays {
            if delay != .zero { try await wait(delay) }
            guard await isCurrent() else { throw CancellationError() }
            if await backend.windowIsFocused(id) { return }
        }
        throw WindowOperationError(
            message: L10n.tr("The app did not confirm window focus. A dialog or floating window may be in front."))
    }
}
