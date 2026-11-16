import Foundation
import Testing

@testable import SpaceTabsCore

@Test func workspaceStorePreservesSeparateAssignmentsAndRejectsInvalidUpdatesAtomically() throws {
    let folder = FileManager.default.temporaryDirectory.appendingPathComponent("Workspaces-\(UUID())")
    defer { try? FileManager.default.removeItem(at: folder) }
    let store = WorkspaceStore(url: folder.appendingPathComponent("workspaces.json"))
    let tab = SavedTab(
        id: UUID(), identity: WindowIdentity(bundleID: "test.editor", title: "Work"), zone: .b, selected: true)
    let first = WorkspaceRecord(name: "Work", displayID: "landscape", layout: PersistedLayout(tabs: [tab]))
    let second = WorkspaceRecord(name: "Reference", displayID: "portrait", layout: PersistedLayout(ratio: 0.6))
    let document = WorkspaceDocument(records: [first, second])
    try store.save(document)
    #expect(try store.load() == document)
    var invalid = document
    invalid.records[1].layout.ratio = .nan
    #expect(throws: (any Error).self) { try store.save(invalid) }
    #expect(try store.load() == document)
    #expect(try store.load()?.records[1].layout.tabs.isEmpty == true)
}

@Test func workspaceRegistryRejectsDuplicateInstancesUnsupportedVersionsAndUnboundedMetadata() throws {
    var record = WorkspaceRecord(name: "Work", profileID: UUID(), displayID: "display")
    #expect(throws: (any Error).self) { try WorkspaceDocument(records: [record, record]).validate() }
    var second = record
    second.id = UUID()
    #expect(throws: (any Error).self) { try WorkspaceDocument(records: [record, second]).validate() }
    var document = WorkspaceDocument(records: [record])
    document.version = 2
    #expect(throws: (any Error).self) { try document.validate() }
    record.zoneNames[.b] = String(repeating: "x", count: PreferenceLimits.zoneNameCharacters + 1)
    #expect(throws: (any Error).self) { try WorkspaceDocument(records: [record]).validate() }
    #expect(throws: (any Error).self) {
        try WorkspaceDocument(records: (0..<17).map { WorkspaceRecord(name: "\($0)", displayID: "display") }).validate()
    }
}
