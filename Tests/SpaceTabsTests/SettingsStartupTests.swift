import Foundation
import Testing

@testable import SpaceTabs

@MainActor @Test func slowSettingsSetupLeavesTheMainActorAvailable() async throws {
    let started = AsyncStream<Void>.makeStream()
    let release = DispatchSemaphore(value: 0)
    let work = Task {
        try await SettingsTransportSetup.perform {
            started.continuation.yield(())
            let released = release.wait(timeout: .now() + 2) == .success
            return (released, Thread.isMainThread)
        }
    }
    defer { release.signal() }
    var events = started.stream.makeAsyncIterator()
    await events.next()
    // Reaching this actor while setup is deliberately blocked models showing
    // the Settings window before signature verification has finished.
    release.signal()
    let (released, ranOnMainThread) = try await work.value
    #expect(released && !ranOnMainThread)
}

@Test func cancelledSettingsStartupDoesNotBeginSignatureOrSocketWork() async {
    let work = Task {
        withUnsafeCurrentTask { $0?.cancel() }
        return try await SettingsTransportSetup.perform {
            Issue.record("A cancelled startup must not create a socket or inspect signatures.")
            return true
        }
    }
    do {
        _ = try await work.value
        Issue.record("Expected cancellation.")
    } catch is CancellationError {} catch { Issue.record("Unexpected error: \(error)") }
}

@MainActor @Test func failedSettingsConnectionLeavesCommandsDisabledWithoutStartingManagerWork() async {
    let model = AppModel()
    let remote = RemoteSettingsModel(model: model)
    model.remoteSettings = remote
    do {
        try await remote.connect(path: String(repeating: "x", count: 200))
        Issue.record("An invalid socket path must not connect.")
    } catch {}
    #expect(!model.remoteSettingsConnected && remote.state == nil)
    #expect(model.scanTask == nil && model.operationTask == nil && model.refreshTask == nil)
}
