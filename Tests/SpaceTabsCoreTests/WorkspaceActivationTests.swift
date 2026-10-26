import Testing

@testable import SpaceTabsCore

@Test func dockReopenAndAppSwitcherPresentWorkspaceWithoutSettingsWindows() {
    var policy = WorkspaceActivationPolicy()
    let result1 = !policy.reopenRequested()
    #expect(result1)
    let result2 = !policy.applicationActivated(isSpaceTabs: true)
    #expect(result2)
    policy.ready = true
    // No Settings window exists: neither entry depends on visible windows.
    let result3 = policy.applicationActivated(isSpaceTabs: true)
    #expect(result3)
    let result4 = policy.reopenRequested()
    #expect(result4)
    // Clicking the Dock again also works while SpaceTabs is already active.
    let result5 = policy.reopenRequested()
    #expect(result5)
}

@Test func explicitSettingsSuppressesDuplicateActivationUntilLeavingOrDockReopen() {
    var policy = WorkspaceActivationPolicy()
    policy.ready = true
    policy.settingsRequested()
    let result6 = !policy.applicationActivated(isSpaceTabs: true)
    #expect(result6)
    let result7 = !policy.applicationActivated(isSpaceTabs: true)
    #expect(result7)
    let result8 = !policy.applicationActivated(isSpaceTabs: false)
    #expect(result8)
    let result9 = policy.applicationActivated(isSpaceTabs: true)
    #expect(result9)
    policy.settingsRequested()
    let result10 = policy.reopenRequested()
    #expect(result10)
    let result11 = policy.applicationActivated(isSpaceTabs: true)
    #expect(result11)
}
