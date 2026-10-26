import CoreGraphics
import Foundation
import Testing

@testable import SpaceTabsCore

private func candidate(_ title: String, document: String? = nil) -> WindowSnapshot {
    WindowSnapshot(
        id: UUID(), pid: 100, appName: "Editor",
        identity: WindowIdentity(bundleID: "test.editor", title: title, document: document),
        state: OriginalWindowState(frame: CGRect(x: 50, y: 60, width: 600, height: 700), minimized: false))
}

@Test func restorationRejectsAmbiguousTitlesAndDuplicateSavedWindows() {
    let a = candidate("Untitled")
    let b = candidate("Untitled")
    let saved = SavedTab(id: UUID(), identity: a.identity, zone: .a, selected: true)
    #expect(WindowReconciler.matches(saved: [saved], windows: [a, b]).isEmpty)
    let duplicate = SavedTab(id: UUID(), identity: a.identity, zone: .b, selected: true)
    #expect(WindowReconciler.matches(saved: [saved, duplicate], windows: [a]).isEmpty)
    #expect(WindowReconciler.matches(saved: [saved], windows: [a]) == [saved.id: a.id])
}

@Test func documentsMatchDespiteTitleChangesAndUntitledDoesNotGuess() {
    let saved = SavedTab(
        id: UUID(), identity: WindowIdentity(bundleID: "test.editor", title: "Before", document: "file:///doc.txt"),
        zone: .b, selected: true)
    let live = candidate("After", document: "file:///doc.txt")
    #expect(WindowReconciler.matches(saved: [saved], windows: [live]) == [saved.id: live.id])
    let blank = SavedTab(
        id: UUID(), identity: WindowIdentity(bundleID: "test.editor", title: ""), zone: .a, selected: true)
    #expect(WindowReconciler.matches(saved: [blank], windows: [candidate("")]).isEmpty)
}

@Test func persistenceRoundTripsAndRejectsCorruptionWithoutOverwriting() throws {
    let directory = FileManager.default.temporaryDirectory.appendingPathComponent("SpaceTabsTests-\(UUID())")
    defer { try? FileManager.default.removeItem(at: directory) }
    let store = PersistenceStore(url: directory.appendingPathComponent("layout.json"))
    #expect(try store.load() == nil)
    let window = candidate("Document")
    let layout = PersistedLayout(
        ratio: 0.42, screenID: "42",
        tabs: [SavedTab(id: window.id, identity: window.identity, zone: .a, selected: true, original: window.state)])
    try store.save(layout)
    #expect(try store.load() == layout)
    let corrupt = Data("{incompleto".utf8)
    try corrupt.write(to: store.url)
    #expect(throws: (any Error).self) { try store.load() }
    #expect(try Data(contentsOf: store.url) == corrupt)
}

@Test func persistenceRejectsUnknownSchemaAndInvalidRatios() throws {
    let url = FileManager.default.temporaryDirectory.appendingPathComponent("SpaceTabsInvalid-\(UUID()).json")
    defer { try? FileManager.default.removeItem(at: url) }
    let store = PersistenceStore(url: url)
    var layout = PersistedLayout()
    layout.version = 2
    #expect(throws: (any Error).self) { try store.save(layout) }
    layout.version = 1
    layout.ratio = .nan
    #expect(throws: (any Error).self) { try store.save(layout) }
}

@Test func legacySessionsKeepAutoHideAndHeaderPreferenceRoundTrips() throws {
    let url = FileManager.default.temporaryDirectory.appendingPathComponent("SpaceTabsLegacy-\(UUID()).json")
    defer { try? FileManager.default.removeItem(at: url) }
    let store = PersistenceStore(url: url)
    try Data(#"{"version":1,"ratio":0.3,"screenID":"42","tabs":[]}"#.utf8).write(to: url)
    let loaded = try store.load()
    var layout = try #require(loaded)
    #expect(layout.autoHideTabBars && layout.screenID == "42")
    #expect(!layout.revealTabsAtTopEdge)
    #expect(!PersistedLayout().revealTabsAtTopEdge)
    layout.revealTabsAtTopEdge = true
    layout.autoHideTabBars = false
    try store.save(layout)
    #expect(try store.load() == layout)
}
