import Testing

@testable import SpaceTabsCore

@Test func idleAndFocusEventsDoNotRequestDiscovery() throws {
    var queue = WindowRefreshQueue()
    let empty = queue.take()
    #expect(empty == nil)
    queue.requestFocus(pid: 42)
    let pending = queue.take()
    let batch = try #require(pending)
    #expect(!batch.fullDiscovery && batch.processIDs.isEmpty)
    #expect(batch.focusPID == 42)
    let after = queue.take()
    #expect(after == nil)
}

@Test func eventBurstsCollapseToAffectedProcesses() throws {
    var queue = WindowRefreshQueue()
    for _ in 0..<100 {
        queue.requestDiscovery(pid: 42)
        queue.requestFocus(pid: 42)
    }
    queue.requestDiscovery(pid: 78)
    let pending = queue.take()
    let batch = try #require(pending)
    #expect(!batch.fullDiscovery)
    #expect(batch.processIDs == [42, 78])
    let after = queue.take()
    #expect(after == nil)
}

@Test func manualDiscoverySupersedesPartialRequestsAndRetainsLatestFocus() throws {
    var queue = WindowRefreshQueue()
    queue.requestDiscovery(pid: 42)
    queue.requestDiscovery()
    queue.requestDiscovery(pid: 78)
    queue.requestFocus(pid: 42)
    queue.requestFocus(pid: 78)
    let pending = queue.take()
    let batch = try #require(pending)
    #expect(batch.fullDiscovery && batch.processIDs.isEmpty)
    #expect(batch.focusPID == 78)
    // A later event is retained for the next batch, not lost with the first.
    queue.requestDiscovery(pid: 99)
    let later = queue.take()
    #expect(later?.processIDs == [99])
}

@Test func notificationTitlesDoNotScheduleAnyWork() throws {
    var queue = WindowRefreshQueue()
    for _ in 0..<1000 { queue.request(.titleChanged, pid: 42) }
    #expect(queue.isEmpty)
    #expect(queue.take() == nil)
    queue.request(.focusChanged, pid: 42)
    let focusBatch = queue.take()
    let focus = try #require(focusBatch)
    #expect(!focus.needsDiscovery)
    #expect(focus.focusPID == 42)
    queue.request(.created, pid: 42)
    queue.request(.destroyed, pid: 78)
    let structuralBatch = queue.take()
    let structural = try #require(structuralBatch)
    #expect(structural.needsDiscovery)
    #expect(structural.processIDs == [42, 78])
}
