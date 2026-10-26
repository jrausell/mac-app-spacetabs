import Foundation
import Testing

@testable import SpaceTabsCore

/// Quiet raise deliberately succeeds while failing to cross another app.
private actor PresentationWindows: WindowPresentationAccess {
    let owners: [UUID: Int32]
    private(set) var order: [UUID]
    private var active: Int32
    private var focused: UUID?
    private var activationChecks = 0
    private var requested: UUID?
    private(set) var activations: [UUID] = []
    private(set) var announced: [UUID] = []
    private(set) var current = true
    var cancelOnActivation: Bool
    init(owners: [UUID: Int32], order: [UUID], active: Int32, cancelOnActivation: Bool = false) {
        self.owners = owners
        self.order = order
        self.active = active
        self.cancelOnActivation = cancelOnActivation
    }
    func preparePresentation(_ id: UUID) {}
    func prepareFocus(_ id: UUID) {}
    func announce(_ id: UUID) { announced.append(id) }
    func requestActivation(_ id: UUID) -> Bool {
        // The event handler must know this is intentional before activation.
        guard announced.last == id else { return false }
        requested = id
        activationChecks = 0
        activations.append(id)
        if cancelOnActivation { current = false }
        return true
    }
    func applicationIsActive(_ id: UUID) -> Bool {
        activationChecks += 1
        if activationChecks >= 2, requested == id { active = owners[id]! }
        return active == owners[id]
    }
    func raiseAndFocus(_ id: UUID) throws {
        guard active == owners[id] else { throw CancellationError() }
        order.removeAll { $0 == id }
        order.append(id)
        focused = id
    }
    func windowIsFocused(_ id: UUID) -> Bool { focused == id && active == owners[id] }
    func raise(_ id: UUID, focus: Bool) {
        guard owners[id] == active else { return }
        order.removeAll { $0 == id }
        order.append(id)
    }
}

@Test func workspacePresentationCrossesUnrelatedForegroundAppInsteadOfTrustingQuietRaise() async throws {
    let a = UUID()
    let b = UUID()
    let random = UUID()
    let backend = PresentationWindows(owners: [a: 10, b: 20, random: 30], order: [a, b, random], active: 30)
    await backend.raise(a, focus: false)
    await backend.raise(b, focus: false)
    #expect(await backend.order == [a, b, random])
    let errors = try await WindowPresentationOperations(backend: backend, wait: { _ in }).present(
        [a, b],
        willFocus: {
            await backend.announce($0)
        }, isCurrent: { await backend.current })
    #expect(errors.isEmpty)
    #expect(await backend.order == [random, a, b])
    #expect(await backend.activations == [a, b])
}

@Test func workspacePresentationSupportsDifferentSelectedWindowsOfTheSameApp() async throws {
    let a = UUID()
    let b = UUID()
    let random = UUID()
    let backend = PresentationWindows(owners: [a: 10, b: 10, random: 20], order: [a, b, random], active: 20)
    let errors = try await WindowPresentationOperations(backend: backend, wait: { _ in }).present(
        [a, b],
        willFocus: {
            await backend.announce($0)
        }, isCurrent: { await backend.current })
    #expect(errors.isEmpty)
    #expect(await backend.order == [random, a, b])
}

@Test func userCancellationDuringWorkspaceActivationStopsBeforeFocusingOrNextZone() async {
    let a = UUID()
    let b = UUID()
    let random = UUID()
    let backend = PresentationWindows(
        owners: [a: 10, b: 20, random: 30], order: [a, b, random], active: 30, cancelOnActivation: true)
    do {
        _ = try await WindowPresentationOperations(backend: backend, wait: { _ in }).present(
            [a, b],
            willFocus: {
                await backend.announce($0)
            }, isCurrent: { await backend.current })
        Issue.record("Presentation should have been cancelled")
    } catch is CancellationError {} catch { Issue.record("Unexpected error: \(error)") }
    #expect(await backend.order == [a, b, random])
    #expect(await backend.activations == [a])
}
