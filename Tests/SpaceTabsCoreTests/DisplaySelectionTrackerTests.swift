import Testing

@testable import SpaceTabsCore

@Test func monitorSelectionSurvivesDisconnectionAndRuntimeIDChangesWithoutFallingBack() {
    let a = DisplayIdentity(runtimeID: "1", stableID: "monitor-a")
    let b = DisplayIdentity(runtimeID: "2", stableID: "monitor-b")
    var tracker = DisplaySelectionTracker()
    #expect(tracker.resolve("1", displays: [a, b]) == "1")
    #expect(tracker.resolve("1", displays: [b]) == nil)
    let returned = DisplayIdentity(runtimeID: "77", stableID: "monitor-a")
    #expect(tracker.resolve("1", displays: [b, returned]) == "77")
    #expect(tracker.resolve("77", displays: [b, returned]) == "77")
    #expect(tracker.resolve("2", displays: [b, returned]) == "2")
}

@Test func defaultMonitorGetsAStableAssociationAndAmbiguousMonitorsAreNotGuessed() {
    let a = DisplayIdentity(runtimeID: "1", stableID: "monitor-a")
    let b = DisplayIdentity(runtimeID: "2", stableID: "monitor-b")
    var tracker = DisplaySelectionTracker()
    #expect(tracker.resolve("", displays: [a, b]) == "1")
    #expect(tracker.resolve("1", displays: []) == nil)
    #expect(tracker.resolve("1", displays: [b, a]) == "1")
    let duplicate = DisplayIdentity(runtimeID: "3", stableID: "monitor-a")
    #expect(tracker.resolve("1", displays: [a, duplicate]) == nil)
    var saved = DisplaySelectionTracker()
    #expect(saved.resolve("monitor-b", displays: [a, b]) == "2")
}
