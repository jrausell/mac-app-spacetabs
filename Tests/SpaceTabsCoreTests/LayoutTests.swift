import CoreGraphics
import Foundation
import Testing

@testable import SpaceTabsCore

@Test func layoutReservesDockAndBarsWithoutOverlap() throws {
    let visible = CGRect(x: -1600, y: 80, width: 1600, height: 970)
    let result = LayoutEngine().geometry(visibleFrame: visible, ratio: 0.3)
    let a = try #require(result[.a])
    let b = try #require(result[.b])
    #expect(a.bar.maxX <= b.bar.minX)
    #expect(a.content.maxY < a.bar.minY)
    #expect(a.content.minY >= visible.minY)
    #expect(b.bar.maxY <= visible.maxY)
    #expect(abs(a.bar.width / (a.bar.width + b.bar.width) - 0.3) < 0.001)
}

@Test func coordinatesRoundTripAcrossOffsetDisplays() {
    let rect = CGRect(x: -1200, y: -400, width: 800, height: 650)
    let ax = LayoutEngine.accessibilityFrame(from: rect, primaryDisplayTop: 1080)
    #expect(ax == CGRect(x: -1200, y: 830, width: 800, height: 650))
    #expect(LayoutEngine.appKitFrame(from: ax, primaryDisplayTop: 1080) == rect)
}

@Test func selectionAndMovesPreserveOtherZone() {
    var tabs = TabManager()
    let a1 = UUID()
    let a2 = UUID()
    let b = UUID()
    tabs.assign(a1, to: .a)
    tabs.assign(a2, to: .a)
    tabs.assign(b, to: .b)
    tabs.select(a1, in: .a)
    #expect(tabs.selected[.b] == b)
    #expect(tabs.adjacent(in: .a, offset: -1) == a2)
    tabs.assign(a1, to: .b)
    #expect(tabs.windows[.a] == [a2])
    #expect(tabs.windows[.b] == [b, a1])
    #expect(tabs.selected[.a] == a2)
}

@Test func invalidFramesAreRejectedAndInvalidRatiosStayFinite() throws {
    let engine = LayoutEngine()
    #expect(engine.geometry(visibleFrame: CGRect(x: 0, y: 0, width: 10, height: 10), ratio: 0.3).isEmpty)
    let frame = CGRect(x: 0, y: 0, width: 1440, height: 900)
    for ratio in [Double.nan, .infinity, -1, 5] {
        let result = engine.geometry(visibleFrame: frame, ratio: ratio)
        let a = try #require(result[.a])
        let b = try #require(result[.b])
        #expect(a.bar.width.isFinite && a.bar.width > 0)
        #expect(b.bar.width.isFinite && b.bar.width > 0)
        #expect(a.bar.maxX <= b.bar.minX)
    }
}

@Test func releasingInactiveAndClosingSelectedKeepsOtherZone() {
    let a1 = UUID()
    let a2 = UUID()
    let a3 = UUID()
    let b = UUID()
    var tabs = TabManager()
    for id in [a1, a2, a3] { tabs.assign(id, to: .a) }
    tabs.assign(b, to: .b)
    tabs.select(a2, in: .a)
    tabs.remove(a1)
    #expect(tabs.selected[.a] == a2)
    tabs.remove(a2)
    #expect(tabs.selected[.a] == a3)
    #expect(tabs.selected[.b] == b)
    let accepted = tabs.select(b, in: .a)
    #expect(!accepted)
    tabs.remove(a3)
    #expect(tabs.selected[.a] == nil)
    #expect(tabs.adjacent(in: .a, offset: 1) == nil)
}

@Test func cellSizedWindowsCanFitButOversizedOrShiftedWindowsCannot() {
    let target = CGRect(x: -1000, y: 60, width: 450, height: 900)
    #expect(LayoutEngine.accepts(actual: CGRect(x: -1000, y: 60, width: 444, height: 886), target: target))
    #expect(!LayoutEngine.accepts(actual: CGRect(x: -1000, y: 60, width: 600, height: 900), target: target))
    #expect(!LayoutEngine.accepts(actual: CGRect(x: -1000, y: 60, width: 450, height: 950), target: target))
    #expect(!LayoutEngine.accepts(actual: CGRect(x: -900, y: 60, width: 450, height: 900), target: target))
}

@Test func sharedHeaderReservationIsIdenticalWithVisibleOrAutoHiddenMenu() throws {
    let screen = CGRect(x: -1920, y: 100, width: 1920, height: 1080)
    let hiddenMenu = CGRect(x: -1850, y: 160, width: 1850, height: 1020)
    let visibleMenu = CGRect(x: -1850, y: 160, width: 1850, height: 996)
    let hiddenUsable = LayoutEngine.usableFrame(visibleFrame: hiddenMenu, screenFrame: screen, menuBarHeight: 24)
    let visibleUsable = LayoutEngine.usableFrame(visibleFrame: visibleMenu, screenFrame: screen, menuBarHeight: 24)
    #expect(hiddenUsable == visibleUsable)
    #expect(hiddenUsable.minX == hiddenMenu.minX && hiddenUsable.minY == hiddenMenu.minY)
    for ratio in [0.15, 0.3, 0.7, 0.85] {
        let geometry = LayoutEngine().geometry(visibleFrame: hiddenUsable, ratio: ratio)
        for zone in LayoutTemplate.twoColumns.zones {
            let rects = try #require(geometry[zone])
            #expect(rects.bar.height == 42)
            #expect(rects.bar.minY - rects.content.maxY == 4)
            let barAX = LayoutEngine.accessibilityFrame(from: rects.bar, primaryDisplayTop: 1080)
            let windowAX = LayoutEngine.accessibilityFrame(from: rects.content, primaryDisplayTop: 1080)
            #expect(windowAX.minY - barAX.maxY == 4)
            #expect(!barAX.intersects(windowAX))
        }
    }
}

@Test func sharedUsableFrameRespectsNotchAndDockWithoutDoubleSubtractingMenu() {
    let screen = CGRect(x: 200, y: -900, width: 1600, height: 1000)
    let visible = CGRect(x: 200, y: -830, width: 1540, height: 930)
    let usable = LayoutEngine.usableFrame(
        visibleFrame: visible, screenFrame: screen, menuBarHeight: 24, safeTopInset: 74)
    #expect(usable.maxY == 26)
    #expect(usable.minY == -830 && usable.maxX == 1740)
    let again = LayoutEngine.usableFrame(visibleFrame: usable, screenFrame: screen, menuBarHeight: 24, safeTopInset: 74)
    #expect(again == usable)
}

@Test func autoHiddenHeadersOverlayFullHeightContentWhileFixedHeadersReserveSpace() throws {
    let engine = LayoutEngine()
    for frame in [CGRect(x: 0, y: 80, width: 1600, height: 950), CGRect(x: -1920, y: -300, width: 1920, height: 1080)] {
        for ratio in [0.15, 0.3, 0.85] {
            let floating = engine.geometry(visibleFrame: frame, ratio: ratio, reserveHeader: false)
            let fixed = engine.geometry(visibleFrame: frame, ratio: ratio, reserveHeader: true)
            for zone in LayoutTemplate.twoColumns.zones {
                let overlay = try #require(floating[zone])
                let reserved = try #require(fixed[zone])
                #expect(overlay.bar == reserved.bar)
                #expect(overlay.content.origin == reserved.content.origin)
                #expect(overlay.content.width == reserved.content.width)
                #expect(overlay.content.height - reserved.content.height == 46)
                #expect(overlay.content.maxY == frame.maxY - engine.margin)
                #expect(overlay.content.intersects(overlay.bar))
                #expect(!reserved.content.intersects(reserved.bar))
            }
        }
    }
}

@Test func hiddenMacMenuDoesNotLeaveAnEmptyStripAboveFloatingModeWindows() throws {
    let screen = CGRect(x: -1920, y: -200, width: 1920, height: 1080)
    let hidden = CGRect(x: -1850, y: -140, width: 1850, height: 1020)
    let visible = CGRect(x: -1850, y: -140, width: 1850, height: 996)
    let engine = LayoutEngine()
    let floating = engine.desktopGeometry(
        visibleFrame: hidden, screenFrame: screen, menuBarHeight: 24, ratio: 0.3, reserveHeader: false)
    let menuVisible = engine.desktopGeometry(
        visibleFrame: visible, screenFrame: screen, menuBarHeight: 24, ratio: 0.3, reserveHeader: false)
    let fixed = engine.desktopGeometry(
        visibleFrame: hidden, screenFrame: screen, menuBarHeight: 24, ratio: 0.3, reserveHeader: true)
    for zone in LayoutTemplate.twoColumns.zones {
        let full = try #require(floating[zone])
        let protected = try #require(menuVisible[zone])
        let reserved = try #require(fixed[zone])
        #expect(full.content.maxY == screen.maxY - engine.margin)
        #expect(full.content.height - protected.content.height == 24)
        #expect(full.bar == protected.bar)
        #expect(reserved.bar.maxY == screen.maxY - engine.margin)
        #expect(full.bar.maxY <= screen.maxY - 24)
        #expect(reserved.content.maxY == reserved.bar.minY - 4)
        #expect(full.content.minY == hidden.minY + engine.margin)
        #expect(full.content.minX == reserved.content.minX && full.content.width == reserved.content.width)
    }
}

@Test func reclaimingHiddenMenuAreaStillProtectsCameraHousingAndDock() throws {
    let screen = CGRect(x: 0, y: 0, width: 1600, height: 1000)
    let visible = CGRect(x: 0, y: 70, width: 1540, height: 930)
    let result = LayoutEngine().desktopGeometry(
        visibleFrame: visible, screenFrame: screen, menuBarHeight: 24,
        safeTopInset: 74, ratio: 0.5, reserveHeader: false)
    let a = try #require(result[.a])
    let b = try #require(result[.b])
    #expect(a.content.maxY == CGFloat(926))
    #expect(a.content.minY == 70)
    #expect(b.content.maxX == 1540)
    #expect(a.bar.maxY == a.content.maxY)
}

@Test func draggingColumnDividerTracksScreenPixelsAndClampsBothDirections() {
    let engine = LayoutEngine()
    let width: CGFloat = 1600
    let usable = width - engine.margin * 2 - engine.gap
    let right = engine.ratioByDragging(initial: 0.3, translation: usable / 10, visibleWidth: width)
    #expect(abs(right - 0.4) < 0.00001)
    #expect(engine.ratioByDragging(initial: 0.3, translation: -10000, visibleWidth: width) == 0.2)
    #expect(engine.ratioByDragging(initial: 0.3, translation: 10000, visibleWidth: width) == 0.8)
    #expect(engine.ratioByDragging(initial: .nan, translation: 100, visibleWidth: width) == 0.25)
    #expect(engine.ratioByDragging(initial: 0.3, translation: 100, visibleWidth: 0) == 0.25)
}

@Test func edgeToEdgeWindowsCoverTheUsableDesktopWithoutOuterOrColumnGaps() throws {
    let engine = LayoutEngine()
    let visible = CGRect(x: -1800, y: -450, width: 1800, height: 1000)
    for ratio in [0.15, 0.3, 0.85] {
        let full = engine.geometry(visibleFrame: visible, ratio: ratio, reserveHeader: false)
        let a = try #require(full[.a])
        let b = try #require(full[.b])
        #expect(a.content.union(b.content) == visible)
        #expect(a.content.maxX == b.content.minX)
        #expect(a.content.width + b.content.width == visible.width)
        #expect(a.content.minY == visible.minY && a.content.maxY == visible.maxY)
        let fixed = engine.geometry(visibleFrame: visible, ratio: ratio, reserveHeader: true)
        let reservedA = try #require(fixed[.a])
        let reservedB = try #require(fixed[.b])
        #expect(reservedA.content.minX == visible.minX && reservedB.content.maxX == visible.maxX)
        #expect(reservedA.content.minY == visible.minY && reservedB.content.minY == visible.minY)
        #expect(reservedA.content.maxY == reservedA.bar.minY - 4)
    }
}

@Test func largeColumnHandleHasItsOwnHeaderSpaceWithoutShrinkingWindowAreas() throws {
    let engine = LayoutEngine()
    let visible = CGRect(x: 100, y: 50, width: 1600, height: 900)
    for ratio in [0.15, 0.3, 0.85] {
        let zones = engine.geometry(visibleFrame: visible, ratio: ratio, reserveHeader: false)
        let headerValue = engine.columnHeaders(for: zones)
        let headers = try #require(headerValue)
        let left = try #require(headers.bars[.a])
        let right = try #require(headers.bars[.b])
        let a = try #require(zones[.a])
        let b = try #require(zones[.b])
        #expect(headers.handle.width == 64 && headers.handle.height == 42)
        #expect(left.maxX + 4 == headers.handle.minX)
        #expect(right.minX - 4 == headers.handle.maxX)
        #expect(!left.intersects(headers.handle) && !right.intersects(headers.handle))
        #expect(headers.handle.midX == a.content.maxX)
        #expect(a.content.maxX == b.content.minX)
        #expect(a.content.union(b.content) == visible)
    }
}
