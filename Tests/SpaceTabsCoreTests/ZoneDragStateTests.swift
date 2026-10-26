import CoreGraphics
import Testing

@testable import SpaceTabsCore

private let dragZones: [Zone: CGRect] = [
    .a: CGRect(x: -1600, y: 0, width: 400, height: 1000),
    .b: CGRect(x: -1200, y: 0, width: 1200, height: 1000),
]

@Test func modifierAndContentDragsAloneNeverShowTargetsOrAssignWindows() {
    var state = ZoneDragState()
    state.begin()
    state.modifiersChanged(held: true)
    #expect(!state.isVisible)
    state.update(pointer: CGPoint(x: -1500, y: 800), modifierHeld: true, windowMoved: false, zones: dragZones)
    #expect(!state.isVisible && state.hovered == nil)
    #expect(state.end(modifierHeld: true) == nil)
    state.begin()
    state.update(pointer: CGPoint(x: -1500, y: 800), modifierHeld: false, windowMoved: true, zones: dragZones)
    #expect(!state.isVisible && state.end(modifierHeld: false) == nil)
}

@Test func releasingModifierBeforeMouseUpCancelsAndLateAXRepliesCannotReshowTargets() {
    var state = ZoneDragState()
    state.begin()
    state.update(pointer: CGPoint(x: -1500, y: 800), modifierHeld: true, windowMoved: true, zones: dragZones)
    #expect(state.isVisible && state.hovered == .a)
    state.modifiersChanged(held: false)
    #expect(!state.isVisible && state.hovered == nil)
    state.update(
        pointer: CGPoint(x: -500, y: 800), modifierHeld: state.modifierHeld, windowMoved: true, zones: dragZones)
    #expect(!state.isVisible)
    #expect(state.end(modifierHeld: false) == nil)
    state.update(pointer: CGPoint(x: -500, y: 800), modifierHeld: true, windowMoved: true, zones: dragZones)
    #expect(!state.isVisible && !state.tracking)
    // Mouse-up flags are authoritative even if flagsChanged was missed.
    state.begin()
    state.update(pointer: CGPoint(x: -1500, y: 800), modifierHeld: true, windowMoved: true, zones: dragZones)
    #expect(state.end(modifierHeld: false) == nil)
}

@Test func dropUsesLastHoveredZoneAndKeyReleaseAfterMouseUpDoesNotUndoTheDrop() {
    var state = ZoneDragState()
    state.begin()
    state.update(pointer: CGPoint(x: -1500, y: 800), modifierHeld: true, windowMoved: true, zones: dragZones)
    #expect(state.hovered == .a)
    state.update(pointer: CGPoint(x: -500, y: 800), modifierHeld: true, windowMoved: false, zones: dragZones)
    #expect(state.hovered == .b)
    let drop = state.end(modifierHeld: true)
    state.modifiersChanged(held: false)
    #expect(drop == .b && !state.isVisible && !state.tracking)
}

@Test func droppingOutsideOrCancellingForDesktopChangeNeverAssignsAZone() {
    var state = ZoneDragState()
    state.begin()
    state.update(pointer: CGPoint(x: 500, y: 800), modifierHeld: true, windowMoved: true, zones: dragZones)
    #expect(state.isVisible && state.hovered == nil)
    #expect(state.end(modifierHeld: true) == nil)
    state.begin()
    state.update(pointer: CGPoint(x: -1500, y: 800), modifierHeld: true, windowMoved: true, zones: dragZones)
    state.cancel()
    #expect(state.end(modifierHeld: true) == nil)
}

@Test func dragTargetsFollowBothTemplatesAndFixedOrFloatingTabBars() throws {
    let screen = CGRect(x: -1920, y: -600, width: 1920, height: 1080)
    for template in LayoutTemplate.allCases {
        for fixed in [true, false] {
            let geometry = LayoutEngine().geometry(
                visibleFrame: screen, ratio: 0.25,
                reserveHeader: fixed, template: template, rowRatio: 0.6)
            let targets = geometry.mapValues { $0.content.union($0.bar) }
            for zone in template.zones {
                let frame = try #require(targets[zone])
                var state = ZoneDragState()
                state.begin()
                state.update(
                    pointer: CGPoint(x: frame.midX, y: frame.midY), modifierHeld: true, windowMoved: true,
                    zones: targets)
                #expect(state.hovered == zone && state.end(modifierHeld: true) == zone)
            }
        }
    }
}

@Test func movementValidationRejectsResizeContentDragAndInvalidFrames() {
    let initial = CGRect(x: 100, y: 200, width: 800, height: 600)
    #expect(ZoneDragState.isWindowMove(from: initial, to: initial.offsetBy(dx: -200, dy: 100)))
    #expect(!ZoneDragState.isWindowMove(from: initial, to: initial))
    #expect(!ZoneDragState.isWindowMove(from: initial, to: initial.offsetBy(dx: 0.2, dy: 0.2)))
    #expect(!ZoneDragState.isWindowMove(from: initial, to: CGRect(x: 50, y: 200, width: 850, height: 600)))
    #expect(!ZoneDragState.isWindowMove(from: initial, to: .zero))
}
