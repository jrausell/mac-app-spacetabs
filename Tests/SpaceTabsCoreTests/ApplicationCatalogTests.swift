import Foundation
import Testing

@testable import SpaceTabsCore

private func makeApplication(_ parent: URL, _ name: String, id: String) throws -> URL {
    let app = parent.appendingPathComponent("\(name).app")
    let contents = app.appendingPathComponent("Contents")
    try FileManager.default.createDirectory(at: contents, withIntermediateDirectories: true)
    let info = [
        "CFBundlePackageType": "APPL", "CFBundleIdentifier": id, "CFBundleName": name, "CFBundleExecutable": name,
    ]
    try PropertyListSerialization.data(fromPropertyList: info, format: .xml, options: 0).write(
        to: contents.appendingPathComponent("Info.plist"))
    return app
}
private func catalogDirectory() throws -> URL {
    let url = FileManager.default.temporaryDirectory.appendingPathComponent("SpaceTabsCatalog-\(UUID())")
    try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
    return url
}

@Test func catalogIncludesClosedApplicationsAndUtilitiesButNotEmbeddedHelpersOrSelf() async throws {
    let base = try catalogDirectory()
    defer { try? FileManager.default.removeItem(at: base) }
    let root = base.appendingPathComponent("Applications")
    let main = try makeApplication(root, "Main", id: "example.main")
    _ = try makeApplication(main.appendingPathComponent("Contents/Helpers"), "Helper", id: "example.helper")
    _ = try makeApplication(root.appendingPathComponent("Utilities"), "Utility", id: "example.utility")
    _ = try makeApplication(root, "SpaceTabs", id: "dev.spacetabs.mac")
    _ = try makeApplication(root, "SpaceTabs Ajustes", id: "dev.spacetabs.mac.settings")
    let catalog = ApplicationCatalog(roots: [root], configurationURL: base.appendingPathComponent("custom.json"))
    let result = try await catalog.scan()
    #expect(result.applications.map(\.bundleID) == ["example.main", "example.utility"])
    #expect(Set(result.directories.map(\.lastPathComponent)) == ["Applications", "Utilities"])
    #expect(result.directories.count == 2)
}

@Test func catalogRechecksAreEqualUntilAnApplicationIsAddedOrRemoved() async throws {
    let base = try catalogDirectory()
    defer { try? FileManager.default.removeItem(at: base) }
    let root = base.appendingPathComponent("Applications")
    _ = try makeApplication(root, "One", id: "example.one")
    let catalog = ApplicationCatalog(roots: [root], configurationURL: base.appendingPathComponent("custom.json"))
    let first = try await catalog.scan()
    #expect(try await catalog.scan() == first)
    let secondURL = try makeApplication(root, "Two", id: "example.two")
    let second = try await catalog.scan()
    #expect(second.applications.count == 2)
    #expect(second != first)
    try FileManager.default.removeItem(at: secondURL)
    #expect(try await catalog.scan() == first)
}

@Test func customApplicationPathsPersistAndDuplicatePathsCollapse() async throws {
    let base = try catalogDirectory()
    defer { try? FileManager.default.removeItem(at: base) }
    let app = try makeApplication(base.appendingPathComponent("Elsewhere"), "Custom", id: "example.custom")
    let config = base.appendingPathComponent("config/custom.json")
    let catalog = ApplicationCatalog(roots: [], configurationURL: config)
    let result = try await catalog.add([app, app])
    #expect(result.applications.count == 1)
    let reopened = ApplicationCatalog(roots: [], configurationURL: config)
    #expect(try await reopened.scan().applications == result.applications)
}

@Test func invalidCustomAppDoesNotOverwriteSavedPaths() async throws {
    let base = try catalogDirectory()
    defer { try? FileManager.default.removeItem(at: base) }
    let config = base.appendingPathComponent("custom.json")
    let app = try makeApplication(base, "Valid", id: "example.valid")
    let catalog = ApplicationCatalog(roots: [], configurationURL: config)
    _ = try await catalog.add([app])
    let before = try Data(contentsOf: config)
    do {
        _ = try await catalog.add([base.appendingPathComponent("missing.app")])
        Issue.record("A missing app must be rejected.")
    } catch {}
    #expect(try Data(contentsOf: config) == before)
}

@Test func realSystemCatalogCanBeReadWithoutAccessibility() async throws {
    let base = try catalogDirectory()
    defer { try? FileManager.default.removeItem(at: base) }
    let catalog = ApplicationCatalog(
        roots: [URL(fileURLWithPath: "/Applications"), URL(fileURLWithPath: "/System/Applications")],
        configurationURL: base.appendingPathComponent("custom.json"))
    let snapshot = try await catalog.scan()
    #expect(!snapshot.applications.isEmpty)
    print(
        "System catalog: \(snapshot.applications.count) apps; \(snapshot.directories.count) watched directories."
    )
}
