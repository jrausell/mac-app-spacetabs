import CoreGraphics
import Foundation
import Testing

@testable import SpaceTabsCore

private let processDate = Date(timeIntervalSince1970: 12345)
private func live(
    _ title: String, document: String? = nil, compatible: Bool = true, number: UInt32? = nil
) -> WindowSnapshot {
    WindowSnapshot(
        id: UUID(), pid: 42, appName: "Browser",
        identity: WindowIdentity(bundleID: "test.browser", title: title, document: document),
        state: OriginalWindowState(frame: CGRect(x: 0, y: 0, width: 1000, height: 800), minimized: false),
        incompatibility: compatible ? nil : "Not resizable", windowNumber: number)
}
private func saved(
    _ title: String, document: String? = nil, date: Date = processDate, number: UInt32? = nil
) -> SavedTab {
    SavedTab(
        id: UUID(), identity: WindowIdentity(bundleID: "test.browser", title: title, document: document), zone: .c,
        selected: true, processID: 42, launchDate: date, windowNumber: number)
}

@Test func browserWindowRestoresAfterItsActiveTabClosesWithThreeWindowsOpen() {
    let old = saved("Closed page", document: "https://example.test/closed", number: 101)
    let main = live("Remaining page", document: "https://example.test/remaining", number: 101)
    let externalOne = live("Closed page", document: "https://example.test/closed", number: 102)
    let externalTwo = live("Other page", number: 103)
    let windows = [externalOne, externalTwo, main]
    #expect(
        WindowReconciler.matches(saved: [old], windows: windows, launchDates: [42: processDate]) == [old.id: main.id])
    #expect(
        WindowReconciler.matches(saved: [old], windows: [externalOne, externalTwo], launchDates: [42: processDate])
            .isEmpty)
    #expect(WindowReconciler.matches(saved: [old], windows: [main], launchDates: [:]).isEmpty)
    #expect(
        WindowReconciler.matches(saved: [old], windows: [main], launchDates: [42: processDate.addingTimeInterval(1)])
            .isEmpty)
}

@Test func numberedWindowMatchesRemainOneToOneAndNeverAcceptIncompatibleWindows() {
    let first = saved("Same page", number: 101)
    let second = saved("Same page", number: 102)
    let one = live("New page", number: 101)
    let two = live("New page", number: 102)
    let dates = [Int32(42): processDate]
    #expect(
        WindowReconciler.matches(saved: [first, second], windows: [two, one], launchDates: dates) == [
            first.id: one.id, second.id: two.id,
        ])
    let duplicate = saved("Other title", number: 101)
    #expect(WindowReconciler.matches(saved: [first, duplicate], windows: [one], launchDates: dates).isEmpty)
    #expect(
        WindowReconciler.matches(
            saved: [first], windows: [live("Same page", compatible: false, number: 101)], launchDates: dates
        ).isEmpty)
    #expect(WindowReconciler.matches(saved: [first], windows: [live("Same page")], launchDates: dates).isEmpty)
}

@Test func sessionWindowNumbersRoundTripAndOlderSessionsRemainReadable() throws {
    let tab = saved("Page", number: 101)
    var layout = PersistedLayout(tabs: [tab], template: .splitLeft)
    let data = try JSONEncoder().encode(layout)
    #expect(try JSONDecoder().decode(PersistedLayout.self, from: data) == layout)
    layout.adapt(to: .twoColumns)
    #expect(layout.tabs.first?.windowNumber == 101)
    try layout.validate()
    var object = try #require(JSONSerialization.jsonObject(with: JSONEncoder().encode(tab)) as? [String: Any])
    object.removeValue(forKey: "windowNumber")
    #expect(
        try JSONDecoder().decode(SavedTab.self, from: JSONSerialization.data(withJSONObject: object)).windowNumber
            == nil)
}

@Test func automaticRestorationRetriesNeitherFocusEventsNorFailedPlacements() {
    var queue = SessionRestorationQueue()
    let old = saved("Page")
    let window = live("Page")
    let expected = [old.id: window.id]
    #expect(queue.takeMatches(saved: [old], windows: [window], launchDates: [:]) == expected)
    for _ in 0..<20 { #expect(queue.takeMatches(saved: [old], windows: [window], launchDates: [:]).isEmpty) }
    let reopened = live("Page")
    #expect(queue.takeMatches(saved: [old], windows: [reopened], launchDates: [:]) == [old.id: reopened.id])
    // Manual restore uses the reconciler directly and can retry the same pair.
    #expect(WindowReconciler.matches(saved: [old], windows: [window]) == expected)
}

@Test func aSingleWindowWithChangedTitleRestoresOnlyInTheSameRunningProcess() {
    let old = saved("Page")
    let current = live("Page · 1 notification")
    #expect(
        WindowReconciler.matches(saved: [old], windows: [current], launchDates: [42: processDate]) == [
            old.id: current.id
        ])
    #expect(WindowReconciler.matches(saved: [old], windows: [current], launchDates: [:]).isEmpty)
    #expect(
        WindowReconciler.matches(saved: [old], windows: [current], launchDates: [42: processDate.addingTimeInterval(1)])
            .isEmpty)
}

@Test func automaticRestorationNeverGuessesBetweenAmbiguousWindowsOrDifferentDocuments() {
    var queue = SessionRestorationQueue()
    let first = saved("Old")
    let second = saved("Old")
    let changed = live("Changed")
    let duplicate = live("Changed")
    #expect(queue.takeMatches(saved: [first, second], windows: [changed], launchDates: [42: processDate]).isEmpty)
    #expect(queue.takeMatches(saved: [first], windows: [changed, duplicate], launchDates: [42: processDate]).isEmpty)
    #expect(
        queue.takeMatches(
            saved: [saved("Old", document: "file:///original")],
            windows: [live("Changed", document: "file:///different")], launchDates: [42: processDate]
        ).isEmpty)
    #expect(
        queue.takeMatches(
            saved: [saved("No size")], windows: [live("No size", compatible: false)], launchDates: [42: processDate]
        ).isEmpty)
}

@Test func laterWindowDiscoveryRestoresOnlyNewMatchesWithoutRepeatingPreviousOnes() {
    var queue = SessionRestorationQueue()
    let first = saved("One")
    let second = saved("Two")
    let one = live("One")
    let two = live("Two")
    #expect(queue.takeMatches(saved: [first, second], windows: [one], launchDates: [:]) == [first.id: one.id])
    #expect(queue.takeMatches(saved: [first, second], windows: [one, two], launchDates: [:]) == [second.id: two.id])
    #expect(queue.takeMatches(saved: [second], windows: [one, two], launchDates: [:]).isEmpty)
}
