import CoreGraphics
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
