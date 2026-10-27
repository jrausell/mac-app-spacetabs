import CoreGraphics
import Foundation

/// Commands are driven by the application operation queue. No idle polling,
/// blocking sleeps, speculative geometry or window-server/private APIs.
public struct WindowOperations<Backend: WindowAccess>: Sendable {
    private let backend: Backend
    private let wait: @Sendable (Duration) async throws -> Void
    private let delays: [Duration] = [.zero, .milliseconds(80), .milliseconds(160), .milliseconds(320)]

    public init(
        backend: Backend, wait: @escaping @Sendable (Duration) async throws -> Void = { try await Task.sleep(for: $0) }
    ) {
        self.backend = backend
        self.wait = wait
    }

    public func snapshot(_ id: UUID) async throws -> OriginalWindowState {
        let minimized = try await retry { try await backend.minimized(id) }
        if minimized, let cached = await backend.cachedFrame(id) {
            return OriginalWindowState(frame: cached, minimized: true)
        }
        return try await OriginalWindowState(frame: retryFrame(id), minimized: minimized)
    }

    /// Restoring a known state must not require a successful geometry read first.
    public func restore(_ id: UUID, state: OriginalWindowState) async throws {
        let current = try? await retry { try await backend.minimized(id) }
        if current != false { try await setMinimized(id, false) }
        try await move(id, target: state.frame)
        if state.minimized { try await setMinimized(id, true) }
    }

    public func execute(_ commands: [WindowCommand]) async throws {
        var before: [UUID: OriginalWindowState] = [:]
        for command in commands where before[command.id] == nil { before[command.id] = try await snapshot(command.id) }
        var touched: [UUID] = []
        var attemptedWindow: UUID?
        do {
            for command in commands {
                attemptedWindow = command.id
                var mutated = false
                do {
                    switch command {
                    case .place(let id, let frame):
                        if try await retry({ try await backend.minimized(id) }) {
                            mutated = true
                            try await setMinimized(id, false)
                        }
                        try await retry { try await backend.validatePlacement(id) }
                        // A tab already at its destination only needs raising.
                        // Use the live transaction snapshot, never idle geometry.
                        if !mutated, !touched.contains(id), let current = before[id],
                            LayoutEngine.accepts(actual: current.frame, target: frame)
                        {
                            break
                        }
                        mutated = true
                        try await move(id, target: frame)
                    case .minimize(let id, let value):
                        if try await retry({ try await backend.minimized(id) }) != value {
                            mutated = true
                            try await setMinimized(id, value)
                        }
                    case .restore(let id, let state):
                        mutated = true
                        try await restore(id, state: state)
                    }
                } catch {
                    if mutated && !touched.contains(command.id) { touched.append(command.id) }
                    throw error
                }
                if mutated && !touched.contains(command.id) { touched.append(command.id) }
            }
        } catch {
            var failed: [UUID: OriginalWindowState] = [:]
            var details: [String] = []
            for id in touched.reversed() {
                guard let state = before[id] else { continue }
                do { try await restore(id, state: state) } catch {
                    failed[id] = state
                    details.append(error.localizedDescription)
                }
            }
            let suffix =
                failed.isEmpty
                ? ""
                : L10n.tr(
                    " Could not confirm recovery: \(details.joined(separator: "; ")). SpaceTabs is paused. You can release the windows."
                )
            throw WindowOperationError(
                message: error.localizedDescription + suffix, recoveryStates: failed, windowID: attemptedWindow)
        }
    }

    private func move(_ id: UUID, target: CGRect) async throws {
        try await writeAndVerify(id, target: target)
    }

    private func writeAndVerify(_ id: UUID, target: CGRect) async throws {
        // An AX timeout can occur after a write was accepted. Check the actual
        // result before repeating the batch; never retry permanent failures.
        do { try await backend.writeFrame(id, frame: target) } catch {
            guard let access = error as? WindowAccessError, access.retryable else { throw error }
            try await wait(.milliseconds(80))
            if let actual = try? await backend.frame(id), LayoutEngine.accepts(actual: actual, target: target) {
                return
            }
            try await backend.writeFrame(id, frame: target)
        }
        var lastError: (any Error)?
        var lastFrame: CGRect?
        for delay in delays {
            if delay != .zero { try await wait(delay) }
            do {
                let actual = try await backend.frame(id)
                if LayoutEngine.accepts(actual: actual, target: target) { return }
                lastFrame = actual
                lastError = nil
            } catch {
                guard let access = error as? WindowAccessError, access.retryable else { throw error }
                lastError = error
            }
        }
        if let lastError { throw lastError }
        if let actual = lastFrame,
            actual.width <= target.width + 32, actual.height <= target.height + 32,
            actual.width > target.width + 2 || actual.height > target.height + 2
        {
            var adjusted = target
            adjusted.size.width -= max(0, actual.width - target.width) + 2
            adjusted.size.height -= max(0, actual.height - target.height) + 2
            try await backend.writeFrame(id, frame: adjusted)
            let result = try await retryFrame(id)
            if LayoutEngine.accepts(actual: result, target: target) { return }
        }
        let dimensions = lastFrame.map { L10n.tr(" (accepts \(Int($0.width)) × \(Int($0.height)) pt)") } ?? ""
        throw WindowOperationError(
            message: L10n.tr("The window does not accept the size or position\(dimensions). Adjust the zone width."))
    }

    private func setMinimized(_ id: UUID, _ value: Bool) async throws {
        do { try await backend.writeMinimized(id, minimized: value) } catch {
            guard let access = error as? WindowAccessError, access.retryable else { throw error }
            try await wait(.milliseconds(80))
            if (try? await backend.minimized(id)) == value { return }
            try await backend.writeMinimized(id, minimized: value)
        }
        for delay in delays {
            if delay != .zero { try await wait(delay) }
            do { if try await backend.minimized(id) == value { return } } catch {
                guard let access = error as? WindowAccessError, access.retryable else { throw error }
            }
        }
        throw WindowAccessError(
            .transient, attribute: "AXMinimized", detail: L10n.tr("The app did not confirm the minimized state change.")
        )
    }

    private func retryFrame(_ id: UUID) async throws -> CGRect { try await retry { try await backend.frame(id) } }

    private func retry<T: Sendable>(_ read: () async throws -> T) async throws -> T {
        for (index, delay) in delays.enumerated() {
            if delay != .zero { try await wait(delay) }
            do { return try await read() } catch {
                guard let access = error as? WindowAccessError, access.retryable, index < delays.count - 1 else {
                    throw error
                }
            }
        }
        throw CancellationError()
    }
}
