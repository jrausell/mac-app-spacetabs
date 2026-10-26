import CoreGraphics
import Foundation
import Testing

@testable import SpaceTabsCore

@Test func splitLeftTemplateTilesThreeIndependentZonesAndReservesEachFixedHeader() throws {
    let engine = LayoutEngine()
    for frame in [CGRect(x: 0, y: 70, width: 1600, height: 1000), CGRect(x: -1920, y: -400, width: 1920, height: 1080)]
    {
        for width in [0.2, 0.25, 0.5, 0.75, 0.8] {
            for rows in [0.25, 0.5, 0.75] {
                let zones = engine.geometry(
                    visibleFrame: frame, ratio: width, reserveHeader: false, template: .splitLeft, rowRatio: rows)
                let a = try #require(zones[.a])
                let b = try #require(zones[.b])
                let c = try #require(zones[.c])
                #expect(a.content.minY == c.content.maxY)
                #expect(a.content.minX == c.content.minX && a.content.width == c.content.width)
                #expect(a.content.maxX == b.content.minX)
                #expect(a.content.union(c.content).union(b.content) == frame)
                #expect(
                    !a.content.intersects(c.content) && !a.content.intersects(b.content)
                        && !c.content.intersects(b.content))
                #expect(abs(a.content.height / frame.height - rows) < 0.001)
                let fixed = engine.geometry(visibleFrame: frame, ratio: width, template: .splitLeft, rowRatio: rows)
                for zone in LayoutTemplate.splitLeft.zones {
                    let reserved = try #require(fixed[zone])
                    let floating = try #require(zones[zone])
                    #expect(reserved.bar == floating.bar)
                    #expect(reserved.content.maxY == reserved.bar.minY - 4)
                    #expect(reserved.content.minY == floating.content.minY)
                }
                let value = engine.columnHeaders(for: zones)
                let headers = try #require(value)
                let rowHandle = try #require(headers.rowHandle)
                let lowerBar = try #require(headers.bars[.c])
                #expect(!rowHandle.intersects(lowerBar))
                #expect(rowHandle.maxY == c.content.maxY)
            }
        }
    }
}

@Test func floatingLowerHeaderStaysAlignedWithItsOwnZoneWhenMacMenuIsHidden() throws {
    let frame = CGRect(x: 100, y: -200, width: 1600, height: 1000)
    let result = LayoutEngine().desktopGeometry(
        visibleFrame: frame, screenFrame: frame, menuBarHeight: 24,
        ratio: 0.25, reserveHeader: false, template: .splitLeft, rowRatio: 0.6)
    let a = try #require(result[.a])
    let b = try #require(result[.b])
    let c = try #require(result[.c])
    #expect(a.bar.maxY == frame.maxY - 24 && b.bar.maxY == frame.maxY - 24)
    #expect(a.content.maxY == frame.maxY && b.content.maxY == frame.maxY)
    #expect(c.bar.maxY == c.content.maxY && c.content.maxY == a.content.minY)
}

@Test func foldingThirdZonePreservesEveryTabAndBothExistingSelections() {
    var tabs = TabManager()
    let a = UUID()
    let b = UUID()
    let c1 = UUID()
    let c2 = UUID()
    tabs.assign(a, to: .a)
    tabs.assign(b, to: .b)
    tabs.assign(c1, to: .c)
    tabs.assign(c2, to: .c)
    tabs.select(c1, in: .c)
    #expect(tabs.selected[.a] == a && tabs.selected[.b] == b)
    #expect(tabs.adjacent(in: .c, offset: 1) == c2)
    tabs.adapt(to: .twoColumns)
    #expect(tabs.windows[.a] == [a, c1, c2])
    #expect(tabs.windows[.c]?.isEmpty == true && tabs.selected[.c] == nil)
    #expect(tabs.selected[.a] == a && tabs.selected[.b] == b)
    tabs.adapt(to: .splitLeft)
    #expect(tabs.windows[.a] == [a, c1, c2])
}

@Test func templateAndRowsPersistAndFoldingPendingSessionsKeepsOriginalRecoveryData() throws {
    let file = FileManager.default.temporaryDirectory.appendingPathComponent("SpaceTabsTemplate-\(UUID()).json")
    defer { try? FileManager.default.removeItem(at: file) }
    let store = PersistenceStore(url: file)
    let original = OriginalWindowState(frame: CGRect(x: 100, y: 120, width: 900, height: 700), minimized: false)
    let c = SavedTab(
        id: UUID(), identity: WindowIdentity(bundleID: "test.editor", title: "C"), zone: .c,
        selected: true, original: original, processID: 42, launchDate: Date(timeIntervalSince1970: 123))
    let a = SavedTab(
        id: UUID(), identity: WindowIdentity(bundleID: "test.editor", title: "A"), zone: .a, selected: true)
    let rule = ApplicationAssignment(
        url: URL(fileURLWithPath: "/Applications/Editor.app"), name: "Editor", bundleID: "test.editor", zone: .c)
    var saved = PersistedLayout(
        ratio: 0.2, tabs: [c, a], applicationAssignments: [rule], template: .splitLeft, rowRatio: 0.65)
    try store.save(saved)
    #expect(try store.load() == saved)
    saved.adapt(to: .twoColumns)
    try store.save(saved)
    #expect(saved.tabs.map(\.id) == [c.id, a.id])
    #expect(saved.tabs.allSatisfy { $0.zone == .a })
    #expect(saved.tabs.filter(\.selected).map(\.id) == [a.id])
    #expect(
        saved.tabs[0].original == original && saved.tabs[0].processID == 42 && saved.tabs[0].launchDate == c.launchDate)
    #expect(saved.applicationAssignments[0].zone == .a)
    #expect(try store.load() == saved)
    saved.rowRatio = 0.1
    #expect(throws: (any Error).self) { try store.save(saved) }
}

@Test func oldRatiosAndColorsMigrateWithoutLosingExistingPreferences() throws {
    let json =
        #"{"version":1,"ratio":0.15,"screenID":"42","tabs":[],"tabAppearance":{"mode":"dark","colorA":{"red":1,"green":0.5,"blue":0},"colorB":{"red":0,"green":0.5,"blue":1}}}"#
    let saved = try JSONDecoder().decode(PersistedLayout.self, from: Data(json.utf8))
    #expect(saved.template == .twoColumns && saved.ratio == 0.2 && saved.rowRatio == 0.5)
    #expect(saved.tabAppearance.mode == .dark && saved.tabAppearance.colorC.isValid)
    #expect(saved.tabAppearance.accent(for: .c, systemIsDark: false).contrast(with: .black) >= 4.5)
    #expect(PersistedLayout().ratio == 0.25)
}

@Test func reversedTemplateCoversDesktopAndSeparatorsTrackActualColumnBoundary() throws {
    let engine = LayoutEngine()
    for origin in [CGPoint.zero, CGPoint(x: -1920, y: -200)] {
        let frame = CGRect(origin: origin, size: CGSize(width: 1600, height: 1000))
        for ratio in [0.2, 0.5, 0.75, 0.8] {
            for rows in [0.25, 0.5, 0.75] {
                let zones = engine.geometry(
                    visibleFrame: frame, ratio: ratio, reserveHeader: false, template: .splitRight, rowRatio: rows)
                let a = try #require(zones[.a])
                let b = try #require(zones[.b])
                let c = try #require(zones[.c])
                #expect(b.content.maxX == a.content.minX && a.content.minX == c.content.minX)
                #expect(a.content.minY == c.content.maxY)
                #expect(a.content.union(b.content).union(c.content) == frame)
                #expect(!a.content.intersects(b.content) && !a.content.intersects(c.content))
                let headers = try #require(engine.columnHeaders(for: zones))
                #expect(headers.handle.midX == b.content.maxX)
                #expect(try #require(headers.bars[.b]).maxX < headers.handle.minX)
                #expect(try #require(headers.bars[.a]).minX > headers.handle.maxX)
                #expect(try #require(headers.rowHandle).minX == c.bar.minX)
                #expect(try #require(headers.bars[.c]).minX > c.bar.minX)
                let fixed = engine.geometry(
                    visibleFrame: frame, ratio: ratio, reserveHeader: true, template: .splitRight, rowRatio: rows)
                for zone in Zone.allCases {
                    let geometry = try #require(fixed[zone])
                    #expect(geometry.content.maxY == geometry.bar.minY - 4)
                }
            }
        }
    }
    #expect(LayoutTemplate.splitRight.defaultRatio == 0.75)
}
