import Foundation

public protocol WindowPresentationAccess: WindowFocusAccess {
    func preparePresentation(_ id: UUID) async throws
    func raise(_ id: UUID, focus: Bool) async throws
}

/// A quiet AXRaise can succeed without crossing the frontmost application's
/// windows. Activate and confirm each selected window, then restore their order
/// after all application activations have settled. This is a finite user action.
public struct WindowPresentationOperations<Backend: WindowPresentationAccess>: Sendable {
    private let backend: Backend
    private let wait: @Sendable (Duration) async throws -> Void
    public init(
        backend: Backend, wait: @escaping @Sendable (Duration) async throws -> Void = { try await Task.sleep(for: $0) }
    ) {
        self.backend = backend
        self.wait = wait
    }

    public func present(
        _ selected: [UUID], willFocus: @Sendable (UUID) async -> Void = { _ in },
        isCurrent: @Sendable () async -> Bool
    ) async throws -> [String] {
        var ready: [UUID] = []
        var focused: [UUID] = []
        var errors: [String] = []
        for id in selected {
            try Task.checkCancellation()
            guard await isCurrent() else { throw CancellationError() }
            do {
                try await backend.preparePresentation(id)
                ready.append(id)
            } catch is CancellationError { throw CancellationError() } catch {
                errors.append(error.localizedDescription)
            }
        }
        for id in ready {
            try Task.checkCancellation()
            guard await isCurrent() else { throw CancellationError() }
            await willFocus(id)
            do {
                try await WindowFocusOperations(backend: backend, wait: wait).focus(id, isCurrent: isCurrent)
                focused.append(id)
            } catch is CancellationError { throw CancellationError() } catch {
                errors.append(error.localizedDescription)
            }
        }
        for id in focused {
            try Task.checkCancellation()
            guard await isCurrent() else { throw CancellationError() }
            do { try await backend.raise(id, focus: false) } catch is CancellationError {
                throw CancellationError()
            } catch { errors.append(error.localizedDescription) }
        }
        return errors
    }
}
