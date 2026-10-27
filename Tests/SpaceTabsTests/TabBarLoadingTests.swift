import Foundation
import SpaceTabsCore
import Testing

@testable import SpaceTabs

@MainActor @Test func tabLoadingCoversInitialDiscoveryAndRecoveryButNotUnmatchedIdleWindows() {
    let model = AppModel()
    model.trusted = true
    #expect(model.isLoadingTabs)
    model.scanning = true
    #expect(model.isLoadingTabs)
    model.hasCompletedDiscovery = true
    model.scanning = false
    let saved = SavedTab(
        id: UUID(), identity: WindowIdentity(bundleID: "test.editor", title: "Saved"), zone: .b, selected: true)
    model.pendingTabs = [saved]
    model.refreshInFlight = true
    #expect(model.isLoadingTabs)
    model.refreshInFlight = false
    model.busy = true
    #expect(model.isLoadingTabs)
    model.busy = false
    #expect(!model.isLoadingTabs)
    #expect(model.pendingTabs == [saved])
    model.pendingTabs = []
    model.scanning = true  // Later unrelated discovery must not imply lost tabs.
    #expect(!model.isLoadingTabs)
}

@MainActor @Test func tabLoadingDoesNotSpinWhilePermissionOrConfigurationPreventsWork() {
    let model = AppModel()
    model.trusted = false
    #expect(!model.isLoadingTabs)
    model.trusted = true
    model.paused = true
    #expect(!model.isLoadingTabs)
    model.paused = false
    model.configurationBlocked = true
    #expect(!model.isLoadingTabs)
    model.configurationBlocked = false
    model.demo = true
    #expect(!model.isLoadingTabs)
    model.demo = false
    #expect(model.isLoadingTabs)
    model.terminating = true
    #expect(!model.isLoadingTabs)
}
