import CoreGraphics
import Foundation
import Testing

@testable import SpaceTabsCore

private let unavailable = WindowAccessError(
    .noValue, attribute: "AXPosition", code: -25212, detail: "No value during the transition.")
private let timedOut = WindowAccessError(.transient, attribute: "AXSize", code: -25204, detail: "Timeout.")
private let unsupported = WindowAccessError(.unsupported, attribute: "AXSize", code: -25205, detail: "Not supported.")

private actor TestWindows: WindowLayoutAccess, WindowPresentationAccess {
    private(set) var raised: [UUID] = []
    private(set) var presentationEvents: [String] = []
    private(set) var focusRequests: [Bool] = []
    func preparePresentation(_ id: UUID) throws {
        presentationEvents.append("prepare:\(id)")
        if try minimized(id) { try writeMinimized(id, minimized: false) }
    }
    func prepareFocus(_ id: UUID) throws {
        if try minimized(id) { try writeMinimized(id, minimized: false) }
    }
    func requestActivation(_ id: UUID) -> Bool { true }
    func applicationIsActive(_ id: UUID) -> Bool { true }
    func raiseAndFocus(_ id: UUID) { raise(id, focus: true) }
    func windowIsFocused(_ id: UUID) -> Bool { true }
    func raise(_ id: UUID, focus: Bool) {
        raised.append(id)
        focusRequests.append(focus)
        presentationEvents.append("raise:\(id)")
    }
    var states: [UUID: OriginalWindowState]
    var caches: [UUID: CGRect]
    var frameReads: [UUID: Int] = [:]
    var frameWrites: [UUID: Int] = [:]
    var minimizeWrites: [UUID: [Bool]] = [:]
    var temporaryReadsAfterWrite = 0
    var staleReadsAfterWrite = 0
    var denyReadsUntilWrite = false
    var rejectedFrame: CGRect?
    var invalidPlacement = false
    var timeoutAfterAcceptedWrite = false
    var timeoutAfterAcceptedMinimize = false
    var permanentReadError: WindowAccessError?
    private var pendingErrors: [UUID: Int] = [:]
    private var pendingStale: [UUID: (Int, CGRect)] = [:]

    init(_ states: [UUID: OriginalWindowState]) {
        self.states = states
        self.caches = states.mapValues(\.frame)
    }

    func configure(
        temporary: Int = 0, stale: Int = 0, unreadableBeforeWrite: Bool = false,
        reject: CGRect? = nil, invalidPlacement: Bool = false, writeTimeout: Bool = false,
        minimizeTimeout: Bool = false, readError: WindowAccessError? = nil
    ) {
        temporaryReadsAfterWrite = temporary
        staleReadsAfterWrite = stale
        denyReadsUntilWrite = unreadableBeforeWrite
        rejectedFrame = reject
        self.invalidPlacement = invalidPlacement
        timeoutAfterAcceptedWrite = writeTimeout
        timeoutAfterAcceptedMinimize = minimizeTimeout
        permanentReadError = readError
    }

    func frame(_ id: UUID) throws -> CGRect {
        frameReads[id, default: 0] += 1
        if let permanentReadError { throw permanentReadError }
        if denyReadsUntilWrite && frameWrites[id, default: 0] == 0 { throw unavailable }
        if pendingErrors[id, default: 0] > 0 {
            pendingErrors[id, default: 0] -= 1
            throw pendingErrors[id, default: 0] % 2 == 0 ? timedOut : unavailable
        }
        if let (count, stale) = pendingStale[id], count > 0 {
            pendingStale[id] = (count - 1, stale)
            return stale
        }
        guard let state = states[id] else {
            throw WindowAccessError(.invalidWindow, attribute: "AXPosition", detail: "Cerrada.")
        }
        if state.minimized { throw unavailable }
        caches[id] = state.frame
        return state.frame
    }

    func minimized(_ id: UUID) throws -> Bool {
        guard let state = states[id] else {
            throw WindowAccessError(.invalidWindow, attribute: "AXMinimized", detail: "Cerrada.")
        }
        return state.minimized
    }
    func cachedFrame(_ id: UUID) -> CGRect? { caches[id] }
    func validatePlacement(_ id: UUID) throws { if invalidPlacement { throw unsupported } }
    func writeFrame(_ id: UUID, frame: CGRect) throws {
        frameWrites[id, default: 0] += 1
        if frame == rejectedFrame { throw unsupported }
        let previous = states[id]!
        states[id] = OriginalWindowState(frame: frame, minimized: previous.minimized)
        pendingErrors[id] = temporaryReadsAfterWrite
        pendingStale[id] = (staleReadsAfterWrite, previous.frame)
        if timeoutAfterAcceptedWrite {
            timeoutAfterAcceptedWrite = false
            throw timedOut
        }
    }
    func writeMinimized(_ id: UUID, minimized: Bool) throws {
        minimizeWrites[id, default: []].append(minimized)
        states[id] = OriginalWindowState(frame: states[id]!.frame, minimized: minimized)
        if timeoutAfterAcceptedMinimize {
            timeoutAfterAcceptedMinimize = false
            throw timedOut
        }
    }
    func state(_ id: UUID) -> OriginalWindowState { states[id]! }
    func reads(_ id: UUID) -> Int { frameReads[id, default: 0] }
    func writes(_ id: UUID) -> Int { frameWrites[id, default: 0] }
    func minimizations(_ id: UUID) -> [Bool] { minimizeWrites[id, default: []] }
}

private func original(_ minimized: Bool = false) -> OriginalWindowState {
    OriginalWindowState(frame: CGRect(x: 50, y: 80, width: 700, height: 600), minimized: minimized)
}
private let destination = CGRect(x: 8, y: 74, width: 450, height: 800)
private func engine(_ backend: TestWindows) -> WindowOperations<TestWindows> {
    WindowOperations(backend: backend, wait: { _ in })
}

@Test func geometryMayBeTemporarilyUnavailableAfterSuccessfulWrite() async throws {
    let id = UUID()
    let backend = TestWindows([id: original()])
    await backend.configure(temporary: 2)
    try await engine(backend).execute([.place(id, destination)])
    #expect(await backend.state(id).frame == destination)
    #expect(await backend.writes(id) == 1)
    #expect(await backend.minimizations(id).isEmpty)  // no redundant AXMinimized=false
}

@Test func staleGeometrySettlesWithoutRepeatedResizeRequests() async throws {
    let id = UUID()
    let backend = TestWindows([id: original()])
    await backend.configure(stale: 2)
    try await engine(backend).execute([.place(id, destination)])
    #expect(await backend.writes(id) == 1)
    #expect(await backend.state(id).frame == destination)
}

@Test func minimizedWindowUsesLastConfirmedFrameUntilRestored() async throws {
    let id = UUID()
    let backend = TestWindows([id: original(true)])
    let operations = engine(backend)
    let state = try await operations.snapshot(id)
    #expect(state == original(true))
    #expect(await backend.reads(id) == 0)
    try await operations.execute([.place(id, destination)])
    #expect(await backend.minimizations(id) == [false])
    #expect(await backend.state(id) == OriginalWindowState(frame: destination, minimized: false))
}

@Test func releaseWorksWhenGeometryCannotBeReadBeforeRecoveryWrite() async throws {
    let id = UUID()
    let backend = TestWindows([id: original()])
    await backend.configure(temporary: 2, unreadableBeforeWrite: true)
    let saved = OriginalWindowState(frame: destination, minimized: false)
    try await engine(backend).restore(id, state: saved)
    #expect(await backend.state(id) == saved)
    #expect(await backend.writes(id) == 1)
}

@Test func acceptedWriteTimeoutIsVerifiedRatherThanRepeated() async throws {
    let id = UUID()
    let backend = TestWindows([id: original()])
    await backend.configure(writeTimeout: true)
    try await engine(backend).execute([.place(id, destination)])
    #expect(await backend.writes(id) == 1)
}

@Test func acceptedMinimizeTimeoutDoesNotMinimizeTwice() async throws {
    let id = UUID()
    let backend = TestWindows([id: original()])
    await backend.configure(minimizeTimeout: true)
    try await engine(backend).execute([.minimize(id, true)])
    #expect(await backend.minimizations(id) == [true])
}

@Test func permanentReadFailureIsNotRetriedOrClassifiedAsFailedRollback() async {
    let id = UUID()
    let backend = TestWindows([id: original()])
    await backend.configure(readError: unsupported)
    do {
        try await engine(backend).execute([.place(id, destination)])
        Issue.record("Expected failure before changing the window.")
    } catch let error as WindowAccessError {
        #expect(error.kind == .unsupported)
        #expect(error.code == -25205)
        #expect(error.errorDescription?.contains("AXSize") == true)
    } catch { Issue.record("Error inesperado: \(error)") }
    #expect(await backend.reads(id) == 1)
    #expect(await backend.writes(id) == 0)
}

@Test func rejectedPlacementDoesNotTouchWindowsOrReportFailedRecovery() async {
    let id = UUID()
    let backend = TestWindows([id: original()])
    await backend.configure(invalidPlacement: true)
    do {
        try await engine(backend).execute([.place(id, destination)])
        Issue.record("Expected the placement to be rejected.")
    } catch let error as WindowOperationError {
        #expect(error.recoveryStates.isEmpty)
        #expect(error.windowID == id)
    } catch {
        Issue.record("Error inesperado: \(error)")
    }
    #expect(await backend.writes(id) == 0)
    #expect(await backend.minimizations(id).isEmpty)
}

@Test func failedAssignmentRestoresTargetAndLeavesOtherColumnUntouched() async {
    let target = UUID()
    let previous = UUID()
    let otherColumn = UUID()
    let backend = TestWindows([target: original(), previous: original(), otherColumn: original()])
    await backend.configure(temporary: 2, reject: destination)
    do {
        try await engine(backend).execute([.place(target, destination)])
        Issue.record("Expected the requested size to fail.")
    } catch let error as WindowOperationError { #expect(error.recoveryStates.isEmpty) } catch {
        Issue.record("Error inesperado: \(error)")
    }
    #expect(await backend.state(target) == original())
    #expect(await backend.state(previous) == original())
    #expect(await backend.reads(otherColumn) == 0)
    #expect(await backend.writes(otherColumn) == 0)
    #expect(await backend.minimizations(otherColumn).isEmpty)
}

@Test func switchingTabsRestoresTargetWithoutTouchingPreviousOrOtherZone() async throws {
    let target = UUID()
    let previous = UUID()
    let otherColumn = UUID()
    let backend = TestWindows([target: original(true), previous: original(), otherColumn: original()])
    try await engine(backend).execute([.place(target, destination)])
    #expect(await backend.minimizations(target) == [false])
    #expect(await backend.minimizations(previous).isEmpty)
    #expect(await backend.reads(previous) == 0)
    #expect(await backend.writes(previous) == 0)
    #expect(await backend.reads(otherColumn) == 0)
    #expect(await backend.writes(otherColumn) == 0)
}

@Test func persistentGeometryFailureHasBoundedRetriesAndPreservesRecoveryState() async {
    let id = UUID()
    let backend = TestWindows([id: original()])
    await backend.configure(temporary: 10)
    do {
        try await engine(backend).execute([.place(id, destination)])
        Issue.record("Expected an unconfirmed recovery error.")
    } catch let error as WindowOperationError {
        #expect(error.recoveryStates[id] == original())
        #expect(error.message.contains("AXPosition") || error.message.contains("AXSize"))
    } catch { Issue.record("Error inesperado: \(error)") }
    #expect(await backend.reads(id) <= 9)
    #expect(await backend.writes(id) == 2)
}

@Test func selectingAnAlreadyPlacedTabDoesNotResizeOrMinimizeIt() async throws {
    let id = UUID()
    let backend = TestWindows([id: OriginalWindowState(frame: destination, minimized: false)])
    try await engine(backend).execute([.place(id, destination)])
    #expect(await backend.writes(id) == 0)
    #expect(await backend.minimizations(id).isEmpty)
}

@Test func restoringLayoutPlacesAllTabsWithoutMinimizingBackgroundTabs() async throws {
    let background = UUID()
    let selected = UUID()
    let otherZone = UUID()
    let backend = TestWindows([background: original(true), selected: original(), otherZone: original()])
    let otherFrame = CGRect(x: 470, y: 74, width: 1000, height: 800)
    let commands = WindowPlacementPlan.commands(
        frames: [background: destination, selected: destination, otherZone: otherFrame],
        selected: [selected, otherZone])
    try await engine(backend).execute(commands)
    #expect(await backend.state(background) == OriginalWindowState(frame: destination, minimized: false))
    #expect(await backend.state(selected).frame == destination)
    #expect(await backend.state(otherZone).frame == otherFrame)
    #expect(await backend.minimizations(background) == [false])
    #expect(await backend.minimizations(selected).isEmpty)
    #expect(await backend.minimizations(otherZone).isEmpty)
    let orderedIDs = commands.compactMap { command -> UUID? in
        if case .place(let id, _) = command { return id }
        return nil
    }
    #expect(orderedIDs == [background, selected, otherZone])
}

@Test func changingHeaderModeReflowsBackgroundTabsAndSelectionsWithoutMinimizing() async throws {
    let selected = UUID()
    let background = UUID()
    let backend = TestWindows([selected: original(), background: original()])
    let visible = CGRect(x: 0, y: 40, width: 1600, height: 960)
    for reserve in [false, true, false] {
        let geometry = LayoutEngine().geometry(visibleFrame: visible, ratio: 0.5, reserveHeader: reserve)
        let rects = try #require(geometry[.a])
        let target = LayoutEngine.accessibilityFrame(from: rects.content, primaryDisplayTop: 1080)
        let commands = WindowPlacementPlan.commands(
            frames: [selected: target, background: target], selected: [selected])
        try await engine(backend).execute(commands)
        #expect(await backend.state(selected).frame == target)
        #expect(await backend.state(background).frame == target)
        #expect(await backend.minimizations(selected).isEmpty)
        #expect(await backend.minimizations(background).isEmpty)
    }
}

@Test func threeZoneRowResizeLeavesRightZoneUntouchedAndRollsBackRejectedHeight() async throws {
    let a = UUID()
    let b = UUID()
    let c = UUID()
    let desktop = CGRect(x: 0, y: 0, width: 1600, height: 1000)
    let engineLayout = LayoutEngine()
    let initial = engineLayout.geometry(visibleFrame: desktop, ratio: 0.25, reserveHeader: false, template: .splitLeft)
    let updated = engineLayout.geometry(
        visibleFrame: desktop, ratio: 0.25, reserveHeader: false, template: .splitLeft, rowRatio: 0.6)
    let ids: [Zone: UUID] = [.a: a, .b: b, .c: c]
    var states: [UUID: OriginalWindowState] = [:]
    var frames: [UUID: CGRect] = [:]
    for zone in LayoutTemplate.splitLeft.zones {
        let id = try #require(ids[zone])
        let before = try #require(initial[zone])
        let after = try #require(updated[zone])
        states[id] = OriginalWindowState(frame: before.content, minimized: false)
        frames[id] = after.content
    }
    let backend = TestWindows(states)
    let commands = WindowPlacementPlan.commands(frames: frames, selected: [a, c, b])
    try await engine(backend).execute(commands)
    #expect(await backend.writes(b) == 0)
    #expect(await backend.state(b) == states[b])
    #expect(await backend.state(a).frame == frames[a])
    #expect(await backend.state(c).frame == frames[c])
    for id in [a, b, c] { #expect(await backend.minimizations(id).isEmpty) }
    // Reject C only after A has been changed; A must return to the 60/40 split.
    let rejected = try #require(initial[.c]?.content)
    await backend.configure(reject: rejected)
    let previousA = await backend.state(a)
    let previousC = await backend.state(c)
    do {
        let restoreFrames = states.mapValues(\.frame)
        try await engine(backend).execute(WindowPlacementPlan.commands(frames: restoreFrames, selected: [a, c, b]))
        Issue.record("A rejected height must cancel the layout change.")
    } catch is WindowOperationError {}
    #expect(await backend.state(a) == previousA)
    #expect(await backend.state(c) == previousC)
    #expect(await backend.state(b) == states[b])
}

@Test func backgroundReflowNeverRaisesAnyTabOverSettings() async throws {
    let first = UUID()
    let second = UUID()
    let third = UUID()
    let otherZone = UUID()
    let backend = TestWindows([first: original(), second: original(), third: original(), otherZone: original()])
    let frames = [
        first: destination, second: destination, third: destination,
        otherZone: CGRect(x: 500, y: 50, width: 500, height: 800),
    ]
    let layout = WindowLayoutOperations(backend: backend, wait: { _ in })
    try await layout.apply(frames: frames, selected: [third, otherZone])
    #expect(await backend.raised.isEmpty)
    try await layout.apply(frames: frames, selected: [second, otherZone], raiseSelected: true)
    #expect(await backend.raised == [second, otherZone])
    for id in [first, second, third, otherZone] { #expect(await backend.minimizations(id).isEmpty) }
}

@Test func presentingZonesRestoresAllSelectionsBeforeRaisingAndPreservesGeometry() async throws {
    let a = UUID()
    let b = UUID()
    let background = UUID()
    let backend = TestWindows([a: original(), b: original(true), background: original()])
    let errors = try await WindowPresentationOperations(backend: backend).present([a, b]) { true }
    #expect(errors.isEmpty)
    #expect(
        await backend.presentationEvents == [
            "prepare:\(a)", "prepare:\(b)", "raise:\(a)", "raise:\(b)", "raise:\(a)", "raise:\(b)",
        ])
    #expect(await backend.focusRequests == [true, true, false, false])
    #expect(await backend.state(b).minimized == false)
    for id in [a, b, background] {
        #expect(await backend.writes(id) == 0)
        #expect(await backend.state(id).frame == original().frame)
    }
    #expect(await backend.minimizations(background).isEmpty)
}

@Test func presentingZonesContinuesIfOneSelectedWindowHasClosed() async throws {
    let closed = UUID()
    let available = UUID()
    let backend = TestWindows([available: original()])
    let errors = try await WindowPresentationOperations(backend: backend).present([closed, available]) { true }
    #expect(errors.count == 1)
    #expect(await backend.raised == [available, available])
}

@Test func cancelledPresentationNeverRaisesWindowsOverANewerUserAction() async throws {
    let id = UUID()
    let backend = TestWindows([id: original()])
    await #expect(throws: CancellationError.self) {
        try await WindowPresentationOperations(backend: backend).present([id]) { false }
    }
    #expect(await backend.presentationEvents.isEmpty)
}

@Test func temporaryEnlargementAndReturnPreserveManualFrameOtherZonesAndMinimization() async throws {
    let id = UUID()
    let other = UUID()
    let initial = OriginalWindowState(frame: CGRect(x: -1400, y: 100, width: 440, height: 600), minimized: false)
    let neighbor = OriginalWindowState(frame: CGRect(x: -800, y: 70, width: 800, height: 1000), minimized: false)
    let backend = TestWindows([id: initial, other: neighbor])
    let operations = WindowOperations(backend: backend, wait: { _ in })
    let before = try await operations.snapshot(id)
    try await operations.execute([.place(id, CGRect(x: -1600, y: 70, width: 1600, height: 1000))])
    #expect(await backend.states[other] == neighbor)
    try await operations.execute([.place(id, before.frame)])
    #expect(await backend.states[id] == initial)
    #expect(await backend.states[other] == neighbor)
    #expect(await backend.raised.isEmpty)
    #expect(await backend.minimizeWrites.isEmpty)
}
