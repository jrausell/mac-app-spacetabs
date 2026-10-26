import Foundation
import Testing

@testable import SpaceTabsCore

private actor FocusWindows: WindowFocusAccess {
    private let applications: [UUID: Int32]
    private var active: Int32?
    private var main: [Int32: UUID] = [:]
    private(set) var focused: UUID?
    private(set) var raised: [UUID] = []
    private(set) var events: [String] = []
    private(set) var activationReads = 0
    private(set) var focusReads = 0
    private var activeAfter: Int
    private let denyActivation: Bool
    private let cancelOnActivation: Bool
    private let confirmFocus: Bool
    private(set) var current = true
    init(
        _ applications: [UUID: Int32], activeAfter: Int = 3, denyActivation: Bool = false,
        cancelOnActivation: Bool = false, confirmFocus: Bool = true
    ) {
        self.applications = applications
        self.activeAfter = activeAfter
        self.denyActivation = denyActivation
        self.cancelOnActivation = cancelOnActivation
        self.confirmFocus = confirmFocus
    }
    func prepareFocus(_ id: UUID) {
        events.append("prepare")
        main[applications[id]!] = id
        activationReads = 0
    }
    func requestActivation(_ id: UUID) -> Bool {
        events.append("activate")
        if cancelOnActivation { current = false }
        return !denyActivation
    }
    func applicationIsActive(_ id: UUID) -> Bool {
        activationReads += 1
        events.append("activation check")
        if activationReads >= activeAfter { active = applications[id] }
        return active == applications[id]
    }
    func raiseAndFocus(_ id: UUID) throws {
        guard active == applications[id], main[applications[id]!] == id else {
            throw WindowOperationError(message: "Raise before the target app/window was ready")
        }
        events.append("raise")
        raised.append(id)
        focused = id
    }
    func windowIsFocused(_ id: UUID) -> Bool {
        events.append("focus check")
        focusReads += 1
        return confirmFocus && focused == id
    }
}

@Test func selectionWaitsForActivationAndWorksAcrossThreeTabsAndSameAppWindows() async throws {
    let first = UUID()
    let second = UUID()
    let third = UUID()
    let otherZone = UUID()
    let backend = FocusWindows([first: 10, second: 20, third: 10, otherZone: 30])
    let focus = WindowFocusOperations(backend: backend, wait: { _ in })
    for id in [third, second, first, third] {
        try await focus.focus(id, isCurrent: { await backend.current })
        #expect(await backend.focused == id)
    }
    #expect(await backend.raised == [third, second, first, third])
    let events = await backend.events
    #expect(
        Array(events.prefix(6)) == [
            "prepare", "activate", "activation check", "activation check", "activation check", "raise",
        ])
    #expect(!(await backend.raised).contains(otherZone))
}

@Test func openingSettingsCancelsPendingFocusWithoutRaisingAWindowAfterwards() async {
    let id = UUID()
    let windows = FocusWindows([id: 10], cancelOnActivation: true)
    do {
        try await WindowFocusOperations(backend: windows, wait: { _ in }).focus(
            id, isCurrent: { await windows.current })
        Issue.record("Opening Settings should cancel this pending focus")
    } catch is CancellationError {} catch { Issue.record("Unexpected error: \(error)") }
    #expect(await windows.raised.isEmpty)
}

@Test func deniedOrUnsettledActivationDoesNotRaiseAndHasBoundedWork() async {
    let id = UUID()
    for backend in [FocusWindows([id: 10], denyActivation: true), FocusWindows([id: 10], activeAfter: 1000)] {
        do {
            try await WindowFocusOperations(backend: backend, wait: { _ in }).focus(id, isCurrent: { true })
            Issue.record("Unconfirmed activation should fail")
        } catch is WindowOperationError {} catch { Issue.record("Unexpected error: \(error)") }
        #expect(await backend.raised.isEmpty)
        #expect(await backend.activationReads <= 6)
    }
}

@Test func unconfirmedWindowFocusIsReportedAndNeverTurnsIntoARaiseLoop() async {
    let id = UUID()
    let windows = FocusWindows([id: 10], confirmFocus: false)
    do {
        try await WindowFocusOperations(backend: windows, wait: { _ in }).focus(id, isCurrent: { true })
        Issue.record("Unconfirmed focus should not be reported as a successful selection")
    } catch is WindowOperationError {} catch { Issue.record("Unexpected error: \(error)") }
    #expect(await windows.raised == [id])
    #expect(await windows.focusReads == 6)
}

@Test func automaticNewTabsPreserveTheSelectionOfEachExistingZone() {
    var tabs = TabManager()
    let a = UUID()
    let b = UUID()
    let c = UUID()
    let later = UUID()
    tabs.assign(a, to: .a)
    tabs.assign(b, to: .b)
    tabs.assign(c, to: .c)
    tabs.assign(later, to: .b, selecting: false)
    #expect(tabs.selected == [.a: a, .b: b, .c: c])
    #expect(tabs.windows[.b] == [b, later])
}

@Test func initialDiscoveryPrioritizesSavedAppsAndDoesNotWaitForUnrelatedProcesses() {
    let running: [Int32: String] = [
        10: "saved.editor", 20: "saved.browser", 30: "unrelated.app", 40: "unrelated.helper",
    ]
    #expect(
        WindowDiscoveryPlan.initialProcesses(savedBundleIDs: ["saved.editor", "saved.browser"], running: running) == [
            10, 20,
        ])
    #expect(WindowDiscoveryPlan.initialProcesses(savedBundleIDs: ["closed.app"], running: running) == [])
    #expect(WindowDiscoveryPlan.initialProcesses(savedBundleIDs: [], running: running) == nil)
}
