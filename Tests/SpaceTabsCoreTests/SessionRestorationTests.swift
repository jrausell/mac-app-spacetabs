import CoreGraphics
import Foundation
import Testing

@testable import SpaceTabsCore

private let processDate = Date(timeIntervalSince1970: 12345)
private func live(_ title: String, document: String? = nil, compatible: Bool = true) -> WindowSnapshot {
    WindowSnapshot(
        id: UUID(), pid: 42, appName: "Browser",
        identity: WindowIdentity(bundleID: "test.browser", title: title, document: document),
        state: OriginalWindowState(frame: CGRect(x: 0, y: 0, width: 1000, height: 800), minimized: false),
        incompatibility: compatible ? nil : "Not resizable")
}
private func saved(_ title: String, document: String? = nil, date: Date = processDate) -> SavedTab {
    SavedTab(
        id: UUID(), identity: WindowIdentity(bundleID: "test.browser", title: title, document: document), zone: .c,
        selected: true, processID: 42, launchDate: date)
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
