import Darwin
import Foundation
import Testing

@testable import SpaceTabsCore

private func storageDirectory() -> URL {
    FileManager.default.temporaryDirectory.appendingPathComponent("SpaceTabsStorage-\(UUID())")
}

@Test func localConfigurationWritesPrivateAtomicFilesAndLeavesNoTemporaryFiles() throws {
    let directory = storageDirectory()
    let url = directory.appendingPathComponent("layout.json")
    defer { try? FileManager.default.removeItem(at: directory) }
    #expect(try LocalConfigurationFile.read(at: url) == nil)
    for text in ["first", "second"] {
        try LocalConfigurationFile.write(Data(text.utf8), to: url)
        #expect(try LocalConfigurationFile.read(at: url) == Data(text.utf8))
        let attributes = try FileManager.default.attributesOfItem(atPath: url.path)
        #expect((attributes[.posixPermissions] as? NSNumber)?.intValue == 0o600)
        #expect(try FileManager.default.contentsOfDirectory(atPath: directory.path) == ["layout.json"])
    }
    let attributes = try FileManager.default.attributesOfItem(atPath: directory.path)
    #expect((attributes[.posixPermissions] as? NSNumber)?.intValue == 0o700)
}

@Test func symbolicLinkConfigurationCannotReadOrOverwriteItsTarget() throws {
    let directory = storageDirectory()
    let target = directory.appendingPathComponent("target.json")
    let link = directory.appendingPathComponent("layout.json")
    defer { try? FileManager.default.removeItem(at: directory) }
    let original = Data("keep me".utf8)
    try LocalConfigurationFile.write(original, to: target)
    try FileManager.default.createSymbolicLink(at: link, withDestinationURL: target)
    #expect(throws: (any Error).self) { try LocalConfigurationFile.read(at: link) }
    #expect(throws: (any Error).self) { try LocalConfigurationFile.write(Data("overwrite".utf8), to: link) }
    #expect(try Data(contentsOf: target) == original)
}

@Test func oversizedAndSharedWritableConfigurationsAreRejected() throws {
    let directory = storageDirectory()
    let url = directory.appendingPathComponent("layout.json")
    defer { try? FileManager.default.removeItem(at: directory) }
    try LocalConfigurationFile.write(Data("valid".utf8), to: url)
    let large = Data(repeating: 32, count: LocalConfigurationFile.maximumBytes + 1)
    #expect(throws: (any Error).self) { try LocalConfigurationFile.write(large, to: url) }
    #expect(try LocalConfigurationFile.read(at: url) == Data("valid".utf8))
    try large.write(to: url)
    #expect(throws: (any Error).self) { try LocalConfigurationFile.read(at: url) }
    try LocalConfigurationFile.write(Data("valid".utf8), to: url)
    try FileManager.default.setAttributes([.posixPermissions: 0o666], ofItemAtPath: url.path)
    #expect(throws: (any Error).self) { try LocalConfigurationFile.read(at: url) }
}

@Test func executableTextAndRemoteAppPathsAreRejectedAsConfigurationData() throws {
    let directory = storageDirectory()
    let url = directory.appendingPathComponent("layout.json")
    defer { try? FileManager.default.removeItem(at: directory) }
    let store = PersistenceStore(url: url)
    try LocalConfigurationFile.write(Data("$(touch /tmp/never-execute-this)".utf8), to: url)
    #expect(throws: (any Error).self) { try store.load() }
    let invalid = ApplicationAssignment(
        url: URL(string: "https://example.com/Bad.app")!, name: "Bad", bundleID: "test.bad", zone: .a)
    #expect(throws: (any Error).self) { try store.save(PersistedLayout(applicationAssignments: [invalid])) }
    let selfTab = SavedTab(
        id: UUID(), identity: WindowIdentity(bundleID: "dev.spacetabs.mac", title: "Settings"), zone: .a, selected: true
    )
    #expect(throws: (any Error).self) { try store.save(PersistedLayout(tabs: [selfTab])) }
}
