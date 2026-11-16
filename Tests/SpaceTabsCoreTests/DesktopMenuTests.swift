import Foundation
import Testing

@testable import SpaceTabsCore

@Test func desktopMenuRequestsRoundTripButRejectForeignOrAmbiguousURLs() throws {
    let auth = DesktopMenuAuthorization()
    let request = DesktopMenuRequest(
        token: auth.token, context: auth.context, displayID: "display", action: .openWorkspace(UUID()))
    let url = try #require(request.url())
    #expect(DesktopMenuRequest.decode(url) == request)
    var components = try #require(URLComponents(url: url, resolvingAgainstBaseURL: false))
    components.scheme = "https"
    #expect(DesktopMenuRequest.decode(try #require(components.url)) == nil)
    components.scheme = SpaceTabsIdentity.desktopMenuScheme
    components.queryItems?.append(URLQueryItem(name: "request", value: "duplicate"))
    #expect(DesktopMenuRequest.decode(try #require(components.url)) == nil)
    for text in [
        "spacetabs://desktop-menu/v1?request=broken", "spacetabs://desktop-menu/v1#fragment", "spacetabs://settings",
    ] {
        #expect(DesktopMenuRequest.decode(try #require(URL(string: text))) == nil)
    }
    var invalid = request
    invalid.version = 2
    #expect(DesktopMenuRequest.decode(try #require(invalid.url())) == nil)
    invalid = request
    invalid.displayID = String(repeating: "x", count: 257)
    #expect(DesktopMenuRequest.decode(try #require(invalid.url())) == nil)
}

@Test func desktopMenuAuthorizationRejectsReplayExpiredForgedAndOldDesktopCommands() {
    var auth = DesktopMenuAuthorization()
    let now = Date(timeIntervalSince1970: 1000)
    let request = DesktopMenuRequest(
        token: auth.token, context: auth.context, created: now, displayID: "display", action: .restore)
    var forged = request
    forged.token = UUID()
    let accepted1 = auth.accept(forged, now: now)
    #expect(!accepted1)
    forged = request
    forged.created = now.addingTimeInterval(3)
    let accepted2 = auth.accept(forged, now: now)
    #expect(!accepted2)
    let accepted3 = auth.accept(request, now: now)
    #expect(accepted3)
    let accepted4 = auth.accept(request, now: now)
    #expect(!accepted4)
    var expired = request
    expired.nonce = UUID()
    let accepted5 = auth.accept(expired, now: now.addingTimeInterval(31))
    #expect(!accepted5)
    let oldContext = auth.context
    auth.invalidateContext()
    #expect(auth.context != oldContext)
    let accepted6 = auth.accept(request, now: now)
    #expect(!accepted6)
    var fresh = request
    fresh.context = auth.context
    let accepted7 = auth.accept(fresh, now: now)
    #expect(accepted7)
}

@Test func desktopMenuReplayBudgetNeverEvictsUnexpiredNonces() {
    var auth = DesktopMenuAuthorization()
    let now = Date(timeIntervalSince1970: 1000)
    let first = DesktopMenuRequest(
        token: auth.token, context: auth.context, created: now, displayID: "display", action: .show)
    let accepted8 = auth.accept(first, now: now)
    #expect(accepted8)
    for _ in 1..<128 {
        let next = DesktopMenuRequest(
            token: auth.token, context: auth.context, created: now, displayID: "display", action: .show)
        let accepted9 = auth.accept(next, now: now)
        #expect(accepted9)
    }
    let accepted10 = auth.accept(first, now: now)
    #expect(!accepted10)
    let next = DesktopMenuRequest(
        token: auth.token, context: auth.context, created: now, displayID: "display", action: .show)
    let accepted11 = auth.accept(next, now: now)
    #expect(!accepted11)
    var later = next
    later.created = now.addingTimeInterval(31)
    let accepted12 = auth.accept(later, now: later.created)
    #expect(accepted12)
    let accepted13 = auth.accept(first, now: later.created)
    #expect(!accepted13)
}

@Test func desktopMenuTargetsOnlyOneWorkspaceOnTheClickedDisplayAndCurrentDesktop() {
    func workspace(display: String, here: Bool = true) -> DesktopMenuWorkspace {
        DesktopMenuWorkspace(
            id: UUID(), name: "Work", profileID: nil, displayID: display, isOpen: true, isHere: here, canRestore: true)
    }
    var snapshot = DesktopMenuSnapshot(
        token: UUID(), context: UUID(), managerPID: 123, launchDate: nil, language: .english,
        ready: true,
        workspaces: [workspace(display: "one"), workspace(display: "two"), workspace(display: "one", here: false)],
        profiles: [])
    #expect(snapshot.workspace(on: "one")?.id == snapshot.workspaces[0].id)
    #expect(snapshot.workspace(on: "two")?.id == snapshot.workspaces[1].id)
    #expect(snapshot.workspace(on: "missing") == nil)
    snapshot.workspaces.append(workspace(display: "one"))
    #expect(snapshot.workspace(on: "one") == nil)
}

@Test func desktopMenuSnapshotStorageIsBoundedAndRejectsInvalidReplacement() throws {
    let directory = FileManager.default.temporaryDirectory.appendingPathComponent("DesktopMenu-\(UUID())")
    defer { try? FileManager.default.removeItem(at: directory) }
    let url = directory.appendingPathComponent("menu.json")
    let snapshot = DesktopMenuSnapshot(
        token: UUID(), context: UUID(), managerPID: 123, launchDate: nil, language: .spanish,
        ready: true, workspaces: [], profiles: [DesktopMenuProfile(id: UUID(), name: "Jorge")])
    try DesktopMenuStorage.save(snapshot, at: url)
    #expect(try DesktopMenuStorage.load(at: url) == snapshot)
    var invalid = snapshot
    invalid.profiles.append(invalid.profiles[0])
    #expect(!invalid.isValid)
    #expect(throws: (any Error).self) { try DesktopMenuStorage.save(invalid, at: url) }
    #expect(try DesktopMenuStorage.load(at: url) == snapshot)
    invalid = snapshot
    invalid.version = 2
    try LocalConfigurationFile.write(JSONEncoder().encode(invalid), to: url)
    #expect(try DesktopMenuStorage.load(at: url) == nil)
}

@Test func desktopMenuScopeAcceptsDirectoryHintsButRejectsFilesAndOtherFolders() throws {
    let directory = FileManager.default.temporaryDirectory.appendingPathComponent(
        "DesktopScope-\(UUID())", isDirectory: true)
    defer { try? FileManager.default.removeItem(at: directory) }
    let desktop = directory.appendingPathComponent("Desktop", isDirectory: true)
    try FileManager.default.createDirectory(at: desktop, withIntermediateDirectories: true)
    let withoutHint = try #require(URL(string: desktop.absoluteString.dropLast().description))
    #expect(desktop != withoutHint)
    #expect(DesktopMenuScope.matches(withoutHint, desktop: desktop))
    #expect(DesktopMenuScope.matches(desktop, desktop: withoutHint))
    #expect(!DesktopMenuScope.matches(desktop.appendingPathComponent("file.txt"), desktop: desktop))
    #expect(!DesktopMenuScope.matches(directory.appendingPathComponent("Documents"), desktop: desktop))
    #expect(!DesktopMenuScope.matches(nil, desktop: desktop))
    #expect(!DesktopMenuScope.matches(URL(string: "https://example.com/Desktop"), desktop: desktop))
    let alias = directory.appendingPathComponent("DesktopAlias", isDirectory: true)
    try FileManager.default.createSymbolicLink(at: alias, withDestinationURL: desktop)
    #expect(DesktopMenuScope.matches(alias, desktop: desktop))
}
