import Foundation
import Observation
import SpaceTabsCore

/// Publishes a small read-only snapshot. Commands arrive as narrowly typed URLs
/// with a private per-run capability, context epoch, freshness and replay checks.
@MainActor final class DesktopMenuBridge {
    typealias Snapshot = @MainActor (UUID, UUID) -> DesktopMenuSnapshot
    private let snapshot: Snapshot
    private let perform: @MainActor (DesktopMenuRequest) -> Void
    private let url: URL?
    private let writer = DispatchQueue(label: "SpaceTabs.desktop-menu.state", qos: .utility)
    private var authorization = DesktopMenuAuthorization()
    private var last: DesktopMenuSnapshot?
    private var publicationTask: Task<Void, Never>?
    private var generation = 0
    private var stopped = true

    init(
        url: URL? = DesktopMenuStorage.url, snapshot: @escaping Snapshot,
        perform: @escaping @MainActor (DesktopMenuRequest) -> Void
    ) {
        self.url = url
        self.snapshot = snapshot
        self.perform = perform
    }
    func start() {
        stopped = false
        observe()
    }
    func refresh() {
        generation += 1
        if !stopped { observe() }
    }
    func invalidateContext() {
        authorization.invalidateContext()
        generation += 1
        if !stopped { observe() }
    }
    private func observe() {
        guard !stopped else { return }
        let currentGeneration = generation
        let state = withObservationTracking {
            snapshot(authorization.token, authorization.context)
        } onChange: { [weak self] in
            Task { @MainActor in
                guard let self, self.generation == currentGeneration else { return }
                self.observe()
            }
        }
        publish(state)
    }
    private func publish(_ state: DesktopMenuSnapshot) {
        guard state != last, let url else { return }
        last = state
        publicationTask?.cancel()
        publicationTask = Task { [weak self] in
            do { try await Task.sleep(for: .milliseconds(80)) } catch { return }
            guard let self, !stopped else { return }
            write(state, to: url)
        }
    }
    private func write(_ state: DesktopMenuSnapshot, to url: URL) {
        writer.async {
            do { try DesktopMenuStorage.save(state, at: url) } catch {
                DiagnosticLog.shared.failure(error, operation: "desktopMenu.publish")
            }
        }
    }
    @discardableResult func receive(_ url: URL, now: Date = .now) -> Bool {
        guard !stopped, let request = DesktopMenuRequest.decode(url),
            snapshot(authorization.token, authorization.context).ready,
            authorization.accept(request, now: now)
        else {
            // Never log the URL: it contains a private capability.
            DiagnosticLog.shared.record("desktopMenu.rejected")
            return false
        }
        perform(request)
        return true
    }
    func stop() {
        guard !stopped else { return }
        stopped = true
        generation += 1
        authorization.invalidateContext()
        var state = snapshot(authorization.token, authorization.context)
        state.ready = false
        state.managerPID = 0
        publicationTask?.cancel()
        publicationTask = nil
        if let url { write(state, to: url) }
    }
}
