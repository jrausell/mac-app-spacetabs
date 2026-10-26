import Foundation
import Testing

@testable import SpaceTabsCore

private actor ActualFocus: ManagedWindowFocusSource {
    let id: UUID?
    init(_ id: UUID?) { self.id = id }
    func focusedManagedID() -> UUID? { id }
}

@Test func zoomTargetsActualFocusedWindowEvenWhenAnotherZoneAndTabWereSelected() async {
    let a = UUID()
    let bSelected = UUID()
    let bFocused = UUID()
    var tabs = TabManager()
    tabs.assign(a, to: .a)
    tabs.assign(bSelected, to: .b)
    tabs.assign(bFocused, to: .b, selecting: false)
    let target = await FocusedZoomTarget.resolve(from: ActualFocus(bFocused), tabs: tabs)
    #expect(target?.windowID == bFocused && target?.zone == .b)
    #expect(tabs.selected[.a] == a && tabs.selected[.b] == bSelected)
}

@Test func zoomNeverFallsBackToZoneAWhenFocusedWindowIsUnknownOrUnmanaged() async {
    var tabs = TabManager()
    tabs.assign(UUID(), to: .a)
    #expect(await FocusedZoomTarget.resolve(from: ActualFocus(nil), tabs: tabs) == nil)
    #expect(await FocusedZoomTarget.resolve(from: ActualFocus(UUID()), tabs: tabs) == nil)
}
