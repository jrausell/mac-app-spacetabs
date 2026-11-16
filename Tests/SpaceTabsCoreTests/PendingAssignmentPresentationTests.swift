import Foundation
import Testing

@testable import SpaceTabsCore

@Test func dozensOfSavedBrowserPagesProduceOneAppPlaceholderWithoutDiscardingRecoveryData() {
    let saved = (0..<50).map { index in
        SavedTab(
            id: UUID(),
            identity: WindowIdentity(
                bundleID: "test.browser", title: "Page \(index)", document: "https://example.test/\(index)"),
            zone: .b, selected: false)
    }
    let result = PendingAssignmentPresentation.representatives(pending: saved, live: [], zone: .b)
    #expect(result.map(\.id) == [saved[0].id])
    #expect(saved.count == 50)
    let window = WindowSnapshot(
        id: UUID(), pid: 42, appName: "Browser",
        identity: WindowIdentity(bundleID: "test.browser", title: "Current page"),
        state: OriginalWindowState(frame: CGRect(x: 0, y: 0, width: 900, height: 800), minimized: false),
        windowNumber: 101)
    #expect(PendingAssignmentPresentation.representatives(pending: saved, live: [window], zone: .b).isEmpty)
}

@Test func appPlaceholdersAreIndependentAcrossZonesAndApps() {
    let first = SavedTab(
        id: UUID(), identity: WindowIdentity(bundleID: "test.browser", title: "A"), zone: .a, selected: false)
    let second = SavedTab(id: UUID(), identity: first.identity, zone: .b, selected: false)
    let editor = SavedTab(
        id: UUID(), identity: WindowIdentity(bundleID: "test.editor", title: "Draft"), zone: .b, selected: false)
    let pending = [first, second, editor]
    #expect(PendingAssignmentPresentation.representatives(pending: pending, live: [], zone: .a) == [first])
    #expect(PendingAssignmentPresentation.representatives(pending: pending, live: [], zone: .b) == [second, editor])
}
