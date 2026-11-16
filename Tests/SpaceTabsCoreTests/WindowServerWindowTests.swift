import CoreGraphics
import Foundation
import Testing

@testable import SpaceTabsCore

@Test func windowNumbersResolveByProcessAndGeometryAcrossDisplaysWithoutPageTitles() {
    let main = CGRect(x: 640, y: 46, width: 1920, height: 1394)
    let external = CGRect(x: -2560, y: 0, width: 1280, height: 1440)
    let windows = [
        WindowServerWindow(pid: 42, number: 101, frame: main),
        WindowServerWindow(pid: 42, number: 102, frame: external),
        WindowServerWindow(pid: 42, number: 103, frame: external.offsetBy(dx: 1280, dy: 0)),
        WindowServerWindow(pid: 43, number: 104, frame: main),
    ]
    #expect(WindowServerWindow.number(for: main, pid: 42, in: windows) == 101)
    #expect(WindowServerWindow.number(for: external, pid: 42, in: windows) == 102)
    #expect(WindowServerWindow.number(for: main.offsetBy(dx: 100, dy: 0), pid: 42, in: windows) == nil)
    let overlapping = windows + [WindowServerWindow(pid: 42, number: 105, frame: main)]
    #expect(WindowServerWindow.number(for: main, pid: 42, in: overlapping) == nil)
    #expect(WindowServerWindow.number(for: main, pid: 42, in: []) == nil)
}

@Test func changingBrowserAXWrappersReusesOnePhysicalWindowWithoutMergingDifferentWindows() {
    let first = WindowSnapshot(
        id: UUID(), pid: 42, appName: "Browser",
        identity: WindowIdentity(bundleID: "test.browser", title: "Page A", document: "https://example.test/a"),
        state: OriginalWindowState(frame: CGRect(x: 0, y: 0, width: 900, height: 800), minimized: false),
        windowNumber: 101)
    let second = WindowSnapshot(
        id: UUID(), pid: 42, appName: "Browser",
        identity: WindowIdentity(bundleID: "test.browser", title: "Page A", document: "https://example.test/a"),
        state: first.state, windowNumber: 102)
    #expect(WindowServerWindow.existingID(for: 101, pid: 42, snapshots: [first, second]) == first.id)
    #expect(WindowServerWindow.existingID(for: 102, pid: 42, snapshots: [first, second]) == second.id)
    #expect(WindowServerWindow.existingID(for: 103, pid: 42, snapshots: [first, second]) == nil)
    #expect(WindowServerWindow.existingID(for: 101, pid: 43, snapshots: [first, second]) == nil)
    #expect(WindowServerWindow.existingID(for: nil, pid: 42, snapshots: [first]) == nil)
    #expect(WindowServerWindow.existingID(for: 101, pid: 42, snapshots: [first, first]) == nil)
}
