import Foundation
import SpaceTabsCore
import Testing

@testable import SpaceTabs

@MainActor @Test func tabLoadingCoversStartupAndOnlyTheZonesActuallyBeingRestored() {
    let model = AppModel()
    model.trusted = true
    #expect(Zone.allCases.allSatisfy { model.isLoadingTabs(in: $0) })
    model.scanning = true
    #expect(Zone.allCases.allSatisfy { model.isLoadingTabs(in: $0) })
    model.hasCompletedDiscovery = true
    model.scanning = false
    let saved = SavedTab(
        id: UUID(), identity: WindowIdentity(bundleID: "test.editor", title: "Saved"), zone: .b, selected: true)
    model.pendingTabs = [saved]
    model.refreshInFlight = true
    #expect(Zone.allCases.allSatisfy { !model.isLoadingTabs(in: $0) })
    model.refreshInFlight = false
    model.busy = true
    model.switchingTabs = true
    // Selecting a known tab does not load any zones, even with unmatched saved windows.
    #expect(Zone.allCases.allSatisfy { !model.isLoadingTabs(in: $0) })
    model.switchingTabs = false
    model.restoringTabZones = [.b]
    #expect(model.isLoadingTabs(in: .b))
    #expect(!model.isLoadingTabs(in: .a) && !model.isLoadingTabs(in: .c))
    model.restoringTabZones.removeAll()
    #expect(Zone.allCases.allSatisfy { !model.isLoadingTabs(in: $0) })
    model.busy = false
    #expect(model.pendingTabs == [saved])
    model.scanning = true
    #expect(Zone.allCases.allSatisfy { !model.isLoadingTabs(in: $0) })
}

@MainActor @Test func tabLoadingDoesNotSpinWhilePermissionOrConfigurationPreventsWork() {
    let model = AppModel()
    model.trusted = false
    #expect(!model.isLoadingTabs(in: .a))
    model.trusted = true
    model.paused = true
    #expect(!model.isLoadingTabs(in: .a))
    model.paused = false
    model.configurationBlocked = true
    #expect(!model.isLoadingTabs(in: .a))
    model.configurationBlocked = false
    model.demo = true
    #expect(!model.isLoadingTabs(in: .a))
    model.demo = false
    #expect(model.isLoadingTabs(in: .a))
    model.terminating = true
    #expect(!model.isLoadingTabs(in: .a))
}
