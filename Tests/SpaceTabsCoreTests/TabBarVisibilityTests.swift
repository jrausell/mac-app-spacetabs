import CoreGraphics
import Foundation
import Testing

@testable import SpaceTabsCore

@Test func tabBarsStartHiddenAndExpireAfterFiveSeconds() {
    var state = TabBarVisibility()
    #expect(!state.isVisible)
    state.reveal(at: 10)
    state.expire(at: 14.9)
    #expect(state.isVisible)
    state.expire(at: 15)
    #expect(!state.isVisible)
}

@Test func tabBarsRemainVisibleWhileHoveredAndGiveTimeAfterLeaving() {
    var state = TabBarVisibility()
    state.reveal(at: 0)
    state.setHovered(true, at: 2)
    state.expire(at: 100)
    #expect(state.isVisible)
    state.setHovered(false, at: 100)
    state.expire(at: 104)
    #expect(state.isVisible)
    state.expire(at: 105)
    #expect(!state.isVisible)
    state.setHovered(true, at: 110)
    #expect(!state.isVisible)  // moving over an invisible bar is not a hot zone
}

@Test func tabContextMenusPreventExpiryAndShortcutRenewsTimeout() {
    var state = TabBarVisibility()
    state.reveal(at: 0)
    state.setMenuTracking(true, at: 1)
    state.expire(at: 60)
    #expect(state.isVisible)
    state.setMenuTracking(false, at: 60)
    state.reveal(at: 64)
    state.expire(at: 65)
    #expect(state.isVisible)
    state.expire(at: 69)
    #expect(!state.isVisible)
    state.reveal(at: 70)
    state.hide()
    #expect(!state.isVisible && state.deadline == nil)
}

@Test func topEdgeUsesChosenMonitorAndDoesNotTriggerDuringDragging() {
    let screen = CGRect(x: -1600, y: -200, width: 1600, height: 1000)
    #expect(TabBarVisibility.atTopEdge(CGPoint(x: -800, y: 799), screen: screen, dragging: false))
    #expect(!TabBarVisibility.atTopEdge(CGPoint(x: -800, y: 799), screen: screen, dragging: true))
    #expect(!TabBarVisibility.atTopEdge(CGPoint(x: 20, y: 799), screen: screen, dragging: false))
    #expect(!TabBarVisibility.atTopEdge(CGPoint(x: -800, y: 780), screen: screen, dragging: false))
}

@Test func outsideClickDismissesImmediatelyDespiteHoverAndMenuTimeoutHolds() {
    var state = TabBarVisibility()
    let frames = [CGRect(x: 0, y: 500, width: 300, height: 42), CGRect(x: 308, y: 500, width: 700, height: 42)]
    state.reveal(at: 0)
    state.setHovered(true, at: 1)
    state.setMenuTracking(true, at: 1)
    state.pointerDown(at: CGPoint(x: 150, y: 450), interactiveFrames: frames)
    #expect(!state.isVisible && state.deadline == nil)
    state.setHovered(false, at: 2)
    state.setMenuTracking(false, at: 2)
    #expect(!state.isVisible)  // late mouse/menu events cannot restore a dismissal
    state.reveal(at: 3)
    #expect(state.isVisible && state.canExpire)
}

@Test func clickingTabsOrDividerDoesNotDismissOrResetTheirDeadline() {
    var state = TabBarVisibility()
    let frames = [
        CGRect(x: 0, y: 500, width: 300, height: 42), CGRect(x: 300, y: 500, width: 8, height: 42),
        CGRect(x: 308, y: 500, width: 700, height: 42),
    ]
    state.reveal(at: 10)
    for point in [CGPoint(x: 100, y: 520), CGPoint(x: 304, y: 520), CGPoint(x: 500, y: 520)] {
        state.pointerDown(at: point, interactiveFrames: frames)
        #expect(state.isVisible && state.deadline == 15)
    }
}

@Test func permanentlyVisibleHeadersIgnoreTimeoutAndOutsideClicksButStillPause() {
    var state = TabBarVisibility()
    state.setAutoHide(false, at: 0)
    state.expire(at: 100)
    state.pointerDown(at: CGPoint(x: 0, y: 0), interactiveFrames: [])
    #expect(state.isVisible && state.deadline == nil && !state.canExpire)
    state.hide()  // pause/desktop change still removes persistent headers
    #expect(!state.isVisible)
    state.reveal(at: 200)
    #expect(state.isVisible && state.deadline == nil)
    state.setAutoHide(true, at: 201)
    #expect(!state.isVisible)
    state.reveal(at: 202)
    state.expire(at: 207)
    #expect(!state.isVisible)
}
