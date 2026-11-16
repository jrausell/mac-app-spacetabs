import Foundation
import Testing

@testable import SpaceTabsCore

private func syncWindow(_ number: UInt32?, pid: Int32 = 42, bundle: String = "test.browser", title: String = "New page")
    -> WindowSnapshot
{
    WindowSnapshot(
        id: UUID(), pid: pid, appName: "App",
        identity: WindowIdentity(bundleID: bundle, title: title, document: "https://example.test/new"),
        state: OriginalWindowState(frame: CGRect(x: 0, y: 0, width: 900, height: 800), minimized: false),
        windowNumber: number)
}

private func visibleSyncWindow(_ number: UInt32, pid: Int32 = 42) -> WindowServerWindow {
    WindowServerWindow(pid: pid, number: number, frame: CGRect(x: 0, y: 0, width: 900, height: 800))
}

@Test func explicitAppSynchronizationAcceptsOneExistingWindowWithoutItsFormerTitleOrDocument() {
    let godot = syncWindow(101, bundle: "test.godot", title: "A different project")
    let mail = syncWindow(102, bundle: "test.mail", title: "Inbox")
    let windows = [godot, mail]
    let visible = [visibleSyncWindow(101), visibleSyncWindow(102)]
    #expect(
        PendingAppSynchronization.candidates(bundleID: "test.godot", windows: windows, assigned: [], visible: visible)
            == [godot])
    #expect(
        PendingAppSynchronization.candidates(bundleID: "test.mail", windows: windows, assigned: [], visible: visible)
            == [mail])
}

@Test func twoChromeWindowsRemainTwoChoicesWhileDuplicateAXWrappersDoNotCreatePageChoices() {
    let first = syncWindow(101, title: "Same page")
    let wrapper = syncWindow(101, title: "Other page")
    let second = syncWindow(102, title: "Same page")
    let result = PendingAppSynchronization.candidates(
        bundleID: "test.browser", windows: [first, wrapper, second], assigned: [],
        visible: [visibleSyncWindow(101), visibleSyncWindow(102)])
    #expect(result.map(\.id) == [first.id, second.id])
    #expect(result.count != 1)
}

@Test func existingWindowSynchronizationNeverTakesOtherZonesOrOtherDesktopsWindows() {
    let owned = syncWindow(101)
    let alias = syncWindow(101)
    let otherDesktop = syncWindow(102)
    let visible = [visibleSyncWindow(101)]
    #expect(
        PendingAppSynchronization.candidates(
            bundleID: "test.browser", windows: [owned, alias, otherDesktop], assigned: [owned.id], visible: visible
        ).isEmpty)
    #expect(
        PendingAppSynchronization.candidates(
            bundleID: "test.browser", windows: [otherDesktop], assigned: [], visible: visible
        ).isEmpty)
    #expect(
        PendingAppSynchronization.candidates(
            bundleID: "test.browser", windows: [syncWindow(nil)], assigned: [], visible: visible
        ).isEmpty)
}

@Test func synchronizationRevalidatesAChosenWindowAndChecksItsProcessAlongWithItsNumber() {
    let selected = syncWindow(101)
    #expect(
        PendingAppSynchronization.candidates(
            bundleID: "test.browser", windows: [selected], assigned: [], visible: [visibleSyncWindow(101)]
        ).count == 1)
    #expect(
        PendingAppSynchronization.candidates(
            bundleID: "test.browser", windows: [selected], assigned: [], visible: []
        ).isEmpty)
    #expect(
        PendingAppSynchronization.candidates(
            bundleID: "test.browser", windows: [selected], assigned: [], visible: [visibleSyncWindow(101, pid: 99)]
        ).isEmpty)
    #expect(
        PendingAppSynchronization.candidates(
            bundleID: "test.browser", windows: [selected], assigned: [selected.id], visible: [visibleSyncWindow(101)]
        ).isEmpty)
}
