import Foundation
import Testing

@testable import SpaceTabsCore

private func saved(_ name: String, zone: Zone = .b, selected: Bool = false) -> SavedTab {
    SavedTab(id: UUID(), identity: WindowIdentity(bundleID: "test.editor", title: name), zone: zone, selected: selected)
}

@Test func unavailableTabsRetainTheirPositionAcrossReorderingAndEmptyWorkspaces() {
    let first = saved("First")
    let closed = saved("Closed", selected: true)
    let last = saved("Last")
    let order = [first.id, closed.id, last.id]
    let merged = SavedTabManifest.merge(live: [last, first], pending: [closed], order: order)
    #expect(merged.map(\.id) == [last.id, closed.id, first.id])
    #expect(merged.first(where: { $0.id == closed.id })?.selected == true)
    let allClosed = SavedTabManifest.merge(live: [], pending: [first, closed, last], order: merged.map(\.id))
    #expect(allClosed == merged)
    let repeated = SavedTabManifest.merge(live: [], pending: allClosed, order: allClosed.map(\.id))
    #expect(repeated == allClosed)
}

@Test func liveSelectionsTakePriorityWithoutDuplicatingRecoveredPendingTabs() throws {
    let old = saved("Old", selected: true)
    let live = saved("Live", selected: true)
    let merged = SavedTabManifest.merge(
        live: [live], pending: [old, live, old], order: [old.id, live.id, old.id])
    #expect(merged.map(\.id) == [old.id, live.id])
    #expect(merged.filter(\.selected).map(\.id) == [live.id])
    try PersistedLayout(tabs: merged).validate()
}

@Test func pendingRecordsMoveWithTheirZoneAndNewTabsAppendWithoutErasingMissingSlots() {
    let a = saved("A", zone: .a)
    let unavailable = saved("Unavailable", zone: .c)
    let moved = SavedTab(id: a.id, identity: a.identity, zone: .c, selected: true)
    let new = saved("New", zone: .c)
    let result = SavedTabManifest.merge(live: [moved, new], pending: [unavailable], order: [a.id, unavailable.id])
    #expect(result.map(\.id) == [moved.id, unavailable.id, new.id])
    #expect(result.allSatisfy { $0.zone == .c })
}

@Test func savingUnavailableProfileTabsStripsProcessAndRecoveryDetails() throws {
    let id = UUID()
    let session = SavedTab(
        id: id, identity: WindowIdentity(bundleID: "test.editor", title: "Draft", document: "file:///test.txt"),
        zone: .b, selected: true,
        original: OriginalWindowState(frame: CGRect(x: 20, y: 30, width: 500, height: 700), minimized: false),
        processID: 12, launchDate: Date(), windowNumber: 456)
    let profile = SavedTabManifest.profileTabs([session])
    #expect(profile.count == 1 && profile[0].id == id && profile[0].identity == session.identity)
    #expect(profile[0].original == nil && profile[0].processID == nil)
    #expect(profile[0].launchDate == nil && profile[0].windowNumber == nil)
    var preferences = UserPreferences()
    preferences.profiles = [
        WorkspaceProfile(name: "Closed workspace", layout: PersistedLayout(tabs: profile), zoneNames: [:])
    ]
    try preferences.validate()
}

@Test func recoveredTabsReturnToTheirSlotWithoutChangingZoneSelections() {
    let first = UUID()
    let missing = UUID()
    let last = UUID()
    let extra = UUID()
    let otherZone = UUID()
    var tabs = TabManager()
    for id in [first, last, extra, missing] { tabs.assign(id, to: .b) }
    tabs.select(last, in: .b)
    tabs.assign(otherZone, to: .a)
    let selections = tabs.selected
    tabs.restoreOrder([first, missing, last, first])
    #expect(tabs.windows[.b] == [first, missing, last, extra])
    #expect(tabs.windows[.a] == [otherZone])
    #expect(tabs.selected == selections)
}
