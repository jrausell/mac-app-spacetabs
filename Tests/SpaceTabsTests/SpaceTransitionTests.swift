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
    try await Task.sleep(for: .milliseconds(650))
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
    model.activeSpaceChanged()
    #expect(model.spaceChangeCount == 2)
    try await Task.sleep(for: .milliseconds(650))
    #expect(model.paused)
    #expect(!model.spaceTransitioning)
    #expect(model.desktopRevision == 2)
}

@MainActor @Test func realScreenOrPermissionFailureOverridesTemporarySpaceTransition() async throws {
    let model = AppModel()
    model.activeSpaceChanged()
    model.suspendForDesktopChange("The selected display no longer exists")
    try await Task.sleep(for: .milliseconds(650))
    #expect(model.paused && !model.spaceTransitioning)
    #expect(model.message == "The selected display no longer exists")
}

@MainActor @Test func spaceNotificationDoesNotEndALongerPhysicalDisplayTransition() async {
    let model = AppModel()
    model.displayProfileTask = Task { try? await Task.sleep(for: .seconds(5)) }
    model.activeSpaceChanged()
    try? await Task.sleep(for: .milliseconds(700))
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

@MainActor @Test func startupProfileCanReplaceADisconnectedSavedDisplayBeforePausing() {
    let model = AppModel()
    model.selectedScreenID = "display-that-is-no-longer-connected"
    let profile = UUID()
    model.pendingAutomaticProfile = profile
    model.checkEnvironment()
    #expect(!model.paused && model.pendingAutomaticProfile == profile)
    model.pendingAutomaticProfile = nil
    model.checkEnvironment()
    #expect(model.paused)
}
