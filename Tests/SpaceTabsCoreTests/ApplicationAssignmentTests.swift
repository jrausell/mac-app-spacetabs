import CoreGraphics
import Foundation
import Testing

@testable import SpaceTabsCore

private func assignedWindow(bundleID: String = "example.editor") -> WindowSnapshot {
    WindowSnapshot(
        id: UUID(), pid: 42, appName: "Editor", identity: WindowIdentity(bundleID: bundleID, title: "Document"),
        state: OriginalWindowState(frame: CGRect(x: 0, y: 0, width: 500, height: 500), minimized: false))
}
private func appRule(_ path: String = "/Applications/Editor.app", zone: Zone = .a) -> ApplicationAssignment {
    ApplicationAssignment(url: URL(fileURLWithPath: path), name: "Editor", bundleID: "example.editor", zone: zone)
}

@Test func closedApplicationAssignmentsPersistWithoutWindowsOrExistingAppFiles() throws {
    let url = FileManager.default.temporaryDirectory.appendingPathComponent("SpaceTabsAppRules-\(UUID()).json")
    defer { try? FileManager.default.removeItem(at: url) }
    let store = PersistenceStore(url: url)
    let rule = appRule("/Volumes/Offline/Editor.app", zone: .b)
    let layout = PersistedLayout(applicationAssignments: [rule])
    try store.save(layout)
    let saved = try store.load()
    #expect(saved == layout)
    #expect(saved?.tabs.isEmpty == true)
    #expect(saved?.applicationAssignments.first?.zone == .b)
}

@Test func applicationRulesDistinguishCopiesWithSameBundleIdentifier() {
    let first = appRule()
    let second = appRule("/Other/Editor.app", zone: .b)
    let window = assignedWindow()
    #expect(
        ApplicationAssignmentResolver.assignment(for: window, applicationURL: first.url, assignments: [first, second])
            == first)
    #expect(
        ApplicationAssignmentResolver.assignment(for: window, applicationURL: second.url, assignments: [first, second])
            == second)
    #expect(
        ApplicationAssignmentResolver.assignment(
            for: window, applicationURL: URL(fileURLWithPath: "/Unassigned/Editor.app"), assignments: [first, second])
            == nil)
    #expect(
        ApplicationAssignmentResolver.assignment(
            for: assignedWindow(bundleID: "another.app"), applicationURL: first.url, assignments: [first]) == nil)
}

@Test func missingApplicationURLOnlyMatchesAnUnambiguousSavedRule() {
    let first = appRule()
    let second = appRule("/Other/Editor.app", zone: .b)
    let window = assignedWindow()
    #expect(ApplicationAssignmentResolver.assignment(for: window, applicationURL: nil, assignments: [first]) == first)
    #expect(
        ApplicationAssignmentResolver.assignment(for: window, applicationURL: nil, assignments: [first, second]) == nil)
}

@Test func rulesRejectDuplicatesAndLegacyLayoutsDefaultToNoApplicationAssignments() throws {
    let url = FileManager.default.temporaryDirectory.appendingPathComponent("SpaceTabsRuleValidation-\(UUID()).json")
    defer { try? FileManager.default.removeItem(at: url) }
    let store = PersistenceStore(url: url)
    let duplicate = PersistedLayout(applicationAssignments: [appRule(), appRule(zone: .b)])
    #expect(throws: (any Error).self) { try store.save(duplicate) }
    try Data(#"{"version":1,"ratio":0.3,"screenID":"","tabs":[]}"#.utf8).write(to: url)
    let legacy = try store.load()
    #expect(legacy?.applicationAssignments.isEmpty == true)
}

@Test func manuallyReleasedOrFailedWindowsDoNotTriggerAnAutomaticAssignmentLoop() {
    let old = assignedWindow()
    let new = assignedWindow()
    let rule = appRule()
    let first = ApplicationAssignmentResolver.candidates(
        windows: [old, new], applicationURLs: [42: rule.url],
        assignments: [rule], assignedZones: [:], attempts: [old.id: rule.id])
    #expect(first[old.id] == nil && first[new.id] == rule)
    let alreadyAssigned = ApplicationAssignmentResolver.candidates(
        windows: [new], applicationURLs: [42: rule.url],
        assignments: [rule], assignedZones: [new.id: .a], attempts: [:])
    #expect(alreadyAssigned.isEmpty)
    let explicitRetry = ApplicationAssignmentResolver.candidates(
        windows: [old], applicationURLs: [42: rule.url],
        assignments: [rule], assignedZones: [:], attempts: [:])
    #expect(explicitRetry[old.id] == rule)
}
