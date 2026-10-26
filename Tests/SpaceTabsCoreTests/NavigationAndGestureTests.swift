import CoreGraphics
import Foundation
import Testing

@testable import SpaceTabsCore

@Test func rightDragRequiresMovementAndCancellationCannotBeRearmedBeforeMouseUp() {
    let zones: [Zone: CGRect] = [
        .a: .init(x: -1000, y: 0, width: 250, height: 800), .b: .init(x: -750, y: 0, width: 750, height: 800),
    ]
    var state = RightDragState()
    state.begin(at: .init(x: -900, y: 500))
    state.update(at: .init(x: -898, y: 500), controlHeld: true)
    #expect(!state.isVisible && state.end(controlHeld: true, zones: zones) == nil)
    state.begin(at: .init(x: -900, y: 500))
    state.update(at: .init(x: -400, y: 500), controlHeld: true)
    #expect(state.isVisible)
    state.update(at: .init(x: -300, y: 500), controlHeld: false)
    state.update(at: .init(x: -200, y: 500), controlHeld: true)
    #expect(state.tracking && !state.isVisible)
    #expect(state.end(controlHeld: true, zones: zones) == nil)
    #expect(!state.tracking)
    state.begin(at: .init(x: -900, y: 500))
    state.update(at: .init(x: -400, y: 500), controlHeld: true)
    #expect(state.end(controlHeld: true, zones: zones) == .b)
}

@Test func rightDragIgnoresDropOutsideZonesAndLosesLateUpdatesAfterCancel() {
    var state = RightDragState()
    let zones: [Zone: CGRect] = [.a: .init(x: 0, y: 0, width: 100, height: 100)]
    state.begin(at: .init(x: 30, y: 30))
    state.update(at: .init(x: 200, y: 50), controlHeld: true)
    #expect(state.end(controlHeld: true, zones: zones) == nil)
    state.begin(at: .init(x: 30, y: 30))
    state.cancel()
    state.update(at: .init(x: 50, y: 50), controlHeld: true)
    #expect(!state.isVisible && state.end(controlHeld: true, zones: zones) == nil)
    state.update(at: .init(x: 50, y: 50), controlHeld: true)
    #expect(!state.tracking && !state.isVisible)
}

@Test func directionalNavigationFollowsReversedColumnsAndBothRows() {
    let engine = LayoutEngine()
    for template in LayoutTemplate.allCases {
        let zones = engine.geometry(
            visibleFrame: .init(x: -1600, y: -200, width: 1600, height: 1000), ratio: template.defaultRatio,
            reserveHeader: false, template: template
        ).mapValues(\.content)
        let towardB: NavigationDirection = template == .splitRight ? .left : .right
        let awayFromB: NavigationDirection = template == .splitRight ? .right : .left
        #expect(LayoutNavigation.neighbor(from: .a, direction: towardB, zones: zones) == .b)
        #expect(LayoutNavigation.neighbor(from: .b, direction: awayFromB, zones: zones) == .a)
        #expect(LayoutNavigation.neighbor(from: .b, direction: towardB, zones: zones) == nil)
        if template != .twoColumns {
            #expect(LayoutNavigation.neighbor(from: .a, direction: .down, zones: zones) == .c)
            #expect(LayoutNavigation.neighbor(from: .c, direction: .up, zones: zones) == .a)
            #expect(LayoutNavigation.neighbor(from: .c, direction: towardB, zones: zones) == .b)
        }
    }
}

@Test func tabReorderingPreservesSelectionAndDoesNotDuplicateOrChangeOtherGroups() {
    var tabs = TabManager()
    let a = UUID()
    let b = UUID()
    let c = UUID()
    let d = UUID()
    tabs.assign(a, to: .a)
    tabs.assign(b, to: .a)
    tabs.assign(c, to: .a)
    tabs.assign(d, to: .b)
    let selected = tabs.selected
    tabs.reorder(c, in: .a, before: a)
    #expect(tabs.windows[.a] == [c, a, b] && tabs.selected == selected)
    tabs.reorder(c, in: .a, before: nil)
    #expect(tabs.windows[.a] == [a, b, c] && tabs.selected == selected)
    tabs.reorder(c, in: .a, before: c)
    tabs.reorder(d, in: .a, before: a)
    #expect(tabs.windows[.a] == [a, b, c] && tabs.windows[.b] == [d])
}

@Test func newGestureAndDisplayPreferencesMigrateAndValidateReferences() throws {
    let old = Data(#"{"shortcuts":[],"zoneNames":[],"profiles":[]}"#.utf8)
    // Zone-keyed dictionaries use Codable's alternating key/value array.
    var value = try JSONDecoder().decode(UserPreferences.self, from: old)
    #expect(value.controlRightDrag && value.displayProfiles.isEmpty)
    let profile = WorkspaceProfile(name: "Laptop", layout: PersistedLayout(), zoneNames: [:])
    value.profiles = [profile]
    value.displayProfiles["display:1920x1080"] = profile.id
    try value.validate()
    #expect(try JSONDecoder().decode(UserPreferences.self, from: JSONEncoder().encode(value)) == value)
    value.displayProfiles["missing"] = UUID()
    #expect(throws: (any Error).self) { try value.validate() }
}

@Test func latencySamplesStayBoundedAndPercentilesReflectRecentWork() {
    var timings = TimingStatistics()
    #expect(timings.summary == "No samples")
    for _ in 0..<200 { timings.record(.milliseconds(10)) }
    #expect(timings.count == 200 && timings.milliseconds.count == 128)
    #expect(timings.summary.contains("median 10 ms") && timings.summary.contains("p95 10 ms"))
    timings.record(.milliseconds(-5))
    #expect(timings.count == 200)
}

@Test func filteredRightDragAcceptsQuartzMouseMovedAsWellAsDraggedEvents() {
    #expect(RightDragState.eventTypes.contains(.mouseMoved))
    #expect(RightDragState.eventTypes.contains(.rightMouseDragged))
    var state = RightDragState()
    let zones: [Zone: CGRect] = [
        .a: .init(x: -1000, y: -400, width: 250, height: 900), .b: .init(x: -750, y: -400, width: 750, height: 900),
    ]
    let idle = state.receiveMotion(.mouseMoved, pointer: .zero, controlHeld: true)
    #expect(!idle)
    state.begin(at: .init(x: -900, y: -100))
    let wrongButton = state.receiveMotion(.leftMouseDragged, pointer: .zero, controlHeld: true)
    let moved = state.receiveMotion(.mouseMoved, pointer: .init(x: -400, y: -150), controlHeld: true)
    #expect(!wrongButton)
    #expect(moved)
    #expect(state.isVisible)
    #expect(state.end(controlHeld: true, zones: zones) == .b)
    let ended = state.receiveMotion(.mouseMoved, pointer: .zero, controlHeld: true)
    #expect(!ended)
}

@Test func rightDragCaptureCanCompleteAfterMouseUpForTheSameDrop() {
    var lease = RightDragCaptureLease()
    let ticket = lease.begin()
    #expect(lease.accepts(ticket))
    lease.dropped()
    #expect(lease.pendingDrop && lease.accepts(ticket))
    lease.invalidate()
    #expect(!lease.pendingDrop && !lease.accepts(ticket))
}

@Test func releasingControlOrStartingANewGestureRejectsLateCaptureReplies() {
    var lease = RightDragCaptureLease()
    let first = lease.begin()
    lease.dropped()
    let second = lease.begin()
    #expect(!lease.accepts(first) && lease.accepts(second))
    lease.invalidate()
    #expect(!lease.accepts(first) && !lease.accepts(second))
}
