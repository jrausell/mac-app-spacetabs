import Foundation
import SpaceTabsCore
import Testing

@testable import SpaceTabs

@MainActor @Test func spaceNotificationsSettleAutomaticallyWithoutPermanentPauseOrRepositioning() async throws {
    let model = AppModel()
    let id = UUID()
    model.tabs.assign(id, to: .b)
    model.originals[id] = OriginalWindowState(frame: CGRect(x: 0, y: 0, width: 900, height: 800), minimized: false)
    let tabs = model.tabs
    let originals = model.originals
    var layouts = 0
    model.layoutChanged = { layouts += 1 }
    model.activeSpaceChanged()
    #expect(model.spaceTransitioning)
    #expect(!model.paused)
    #expect(model.desktopRevision == 1)
    let transition = try #require(model.spaceChangeTask)
    await transition.value
    #expect(!model.spaceTransitioning && !model.paused)
    #expect(layouts == 2)
    #expect(model.operationTask == nil)
    #expect(model.tabs == tabs && model.originals == originals)
    #expect(model.message == nil)
    #expect(!model.tabSelectionRunner.isPending)
}

@MainActor @Test func repeatedSpaceEventsCoalesceAndNeverResumeAManualPause() async throws {
    let model = AppModel()
    model.paused = true
    model.activeSpaceChanged()
    let first = try #require(model.spaceChangeTask)
    model.activeSpaceChanged()
    #expect(model.spaceChangeCount == 2)
    #expect(first.isCancelled)
    let transition = try #require(model.spaceChangeTask)
    await transition.value
    #expect(model.paused)
    #expect(!model.spaceTransitioning)
    #expect(model.desktopRevision == 2)
}

@MainActor @Test func realScreenOrPermissionFailureOverridesTemporarySpaceTransition() async throws {
    let model = AppModel()
    model.activeSpaceChanged()
    let transition = try #require(model.spaceChangeTask)
    model.suspendForDesktopChange("The selected display no longer exists")
    await transition.value
    #expect(model.paused && !model.spaceTransitioning)
    #expect(model.message == "The selected display no longer exists")
}

@MainActor @Test func spaceNotificationDoesNotEndALongerPhysicalDisplayTransition() async throws {
    let model = AppModel()
    model.displayProfileTask = Task { try? await Task.sleep(for: .seconds(5)) }
    model.activeSpaceChanged()
    let transition = try #require(model.spaceChangeTask)
    await transition.value
    #expect(model.spaceTransitioning && model.managementSuspended)
    #expect(!model.paused)
    model.displayProfileTask?.cancel()
    model.displayProfileTask = nil
    model.suspendForDesktopChange("Cancellation test")
    #expect(!model.spaceTransitioning && model.paused)
}

@MainActor @Test func automaticProfilesNeverResumeAManualPauseOrLoseThePendingChoice() {
    let model = AppModel()
    let id = UUID()
    model.pendingAutomaticProfile = id
    model.paused = true
    #expect(model.applyAutomaticProfileIfReady())
    #expect(model.pendingAutomaticProfile == id && model.paused)
    #expect(model.operationTask == nil)
    model.suspendForDesktopChange("Access revoked")
    #expect(model.pendingAutomaticProfile == nil && model.paused)
}

@MainActor @Test func missingDisplaySuspensionDoesNotBecomeAManualPauseOrBlockAutomaticProfiles() {
    let model = AppModel()
    model.selectedScreenID = "display-that-is-no-longer-connected"
    let profile = UUID()
    model.pendingAutomaticProfile = profile
    model.checkEnvironment()
    #expect(!model.paused && model.pendingAutomaticProfile == profile)
    model.pendingAutomaticProfile = nil
    model.checkEnvironment()
    #expect(!model.paused && model.displayUnavailable && model.managementSuspended)
}

@MainActor @Test func unlinkedDisplayChangesRecoverBarsAndShortcutHandlingWithoutReapplyingLayout() async throws {
    let model = AppModel()
    model.selectedScreenID = "1"
    let displays = [DisplayIdentity(runtimeID: "1", stableID: "monitor-a")]
    model.updateDisplayAvailability(displays: displays)
    var enabled = true
    var reveals = 0
    var registrations = 0
    model.layoutChanged = { enabled = !model.managementSuspended }
    model.showTabBars = { if enabled { reveals += 1 } }
    model.restartShortcuts = { registrations += 1 }
    let selected = UUID()
    model.tabs.assign(selected, to: .b)
    let tabs = model.tabs
    model.physicalDisplaysChanged(displays: displays)
    #expect(model.spaceTransitioning && !model.paused && !enabled)
    await model.displayProfileTask?.value
    #expect(!model.managementSuspended && enabled)
    #expect(model.tabs == tabs && model.operationTask == nil)
    #expect(registrations == 1)
    model.handleShortcut(.showTabs, source: "Test after wake")
    #expect(reveals == 1)
}

@MainActor @Test func displayAndSpaceEventsInEitherOrderNeverLeaveAnOrphanedTransition() async throws {
    let displays = [DisplayIdentity(runtimeID: "1", stableID: "monitor-a")]
    let first = AppModel()
    first.selectedScreenID = "1"
    first.updateDisplayAvailability(displays: displays)
    first.activeSpaceChanged()
    let cancelled = try #require(first.spaceChangeTask)
    first.physicalDisplaysChanged(displays: displays)
    #expect(cancelled.isCancelled && first.spaceChangeTask == nil)
    await first.displayProfileTask?.value
    await cancelled.value
    #expect(!first.managementSuspended && first.spaceChangeTask == nil && first.displayProfileTask == nil)

    let second = AppModel()
    second.selectedScreenID = "1"
    second.updateDisplayAvailability(displays: displays)
    second.physicalDisplaysChanged(displays: displays)
    let display = try #require(second.displayProfileTask)
    second.activeSpaceChanged()
    let space = try #require(second.spaceChangeTask)
    await space.value
    await display.value
    #expect(!second.managementSuspended && second.spaceChangeTask == nil && second.displayProfileTask == nil)
    #expect(second.operationTask == nil)
}

@MainActor @Test func monitorReconnectRecoversAvailabilityButNeverClearsAManualOrFailurePause() throws {
    let model = AppModel()
    model.selectedScreenID = "1"
    model.updateDisplayAvailability(displays: [DisplayIdentity(runtimeID: "1", stableID: "monitor-a")])
    model.appliedScreenID = "1"
    var registrations = 0
    model.restartShortcuts = { registrations += 1 }
    model.updateDisplayAvailability(displays: [DisplayIdentity(runtimeID: "2", stableID: "monitor-b")])
    #expect(model.displayUnavailable && !model.paused)
    #expect(model.selectedScreenID == "1")
    let unavailableHelper = AppModel()
    let unavailableSnapshot = try JSONDecoder().decode(
        SettingsState.self, from: JSONEncoder().encode(SettingsState(model)))
    unavailableSnapshot.apply(to: unavailableHelper)
    #expect(unavailableHelper.displayUnavailable && !unavailableHelper.paused && unavailableHelper.managementSuspended)
    model.paused = true
    model.updateDisplayAvailability(displays: [DisplayIdentity(runtimeID: "77", stableID: "monitor-a")])
    #expect(!model.displayUnavailable && model.selectedScreenID == "77" && model.appliedScreenID == "77")
    #expect(model.paused && model.managementSuspended && model.operationTask == nil)
    #expect(registrations == 1)
    let helper = AppModel()
    SettingsState(model).apply(to: helper)
    #expect(helper.paused && !helper.displayUnavailable && helper.managementSuspended)

    let automatic = AppModel()
    automatic.selectedScreenID = "1"
    automatic.updateDisplayAvailability(displays: [DisplayIdentity(runtimeID: "1", stableID: "monitor-a")])
    automatic.updateDisplayAvailability(displays: [])
    #expect(automatic.managementSuspended && !automatic.paused)
    automatic.updateDisplayAvailability(displays: [DisplayIdentity(runtimeID: "77", stableID: "monitor-a")])
    #expect(!automatic.managementSuspended && !automatic.paused && automatic.selectedScreenID == "77")
    #expect(automatic.operationTask == nil)
}

@MainActor @Test func displayDebouncePreservesExistingPauseAndCoalescesRepeatedWakeEvents() async throws {
    let model = AppModel()
    model.paused = true
    model.selectedScreenID = "1"
    let displays = [DisplayIdentity(runtimeID: "1", stableID: "monitor-a")]
    model.updateDisplayAvailability(displays: displays)
    model.physicalDisplaysChanged(applyLinkedProfile: false, displays: displays)
    let first = try #require(model.displayProfileTask)
    model.physicalDisplaysChanged(applyLinkedProfile: false, displays: displays)
    let last = try #require(model.displayProfileTask)
    #expect(first.isCancelled)
    await first.value
    await last.value
    #expect(model.paused && !model.spaceTransitioning && model.displayProfileTask == nil)
    #expect(model.operationTask == nil && model.pendingAutomaticProfile == nil)
}
