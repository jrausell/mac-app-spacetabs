import AppKit
import Foundation
import SpaceTabsCore

struct SettingsState: Codable, Equatable, Sendable {
    let preferencesBlocked: Bool
    let preferences: UserPreferences
    let loginEnabled: Bool
    let loginNeedsApproval: Bool
    let loginMessage: String?
    let applicationAssignments: [ApplicationAssignment]
    let installedApplications: [InstalledApplication]
    let catalogMessage: String?
    let launchingApplications: Set<String>
    let tabAppearance: TabAppearance
    let layoutTemplate: LayoutTemplate
    let rowRatio: Double
    let revealTabsAtTopEdge: Bool
    let autoHideTabBars: Bool
    let ratio: Double
    let tabs: TabManager
    let demo: Bool
    let paused: Bool
    let spaceTransitioning: Bool
    let spaceChangeCount: Int
    let lastSpaceChange: String
    let accessibilityNotices: [String]
    let message: String?
    let titles: [UUID: String]
    let windows: [WindowSnapshot]
    let trusted: Bool
    let scanning: Bool
    let hasCompletedDiscovery: Bool
    let hasCompletedFullDiscovery: Bool
    let busy: Bool
    let displayConfigurationKey: String
    let rightDragDetails: String
    let rightDragStatus: String
    let selectionTimings: TimingStatistics
    let switchingTabs: Bool
    let warnings: [String]
    let shortcutWarnings: [String]
    let registeredShortcuts: Set<UInt32>
    let globalShortcutEventCount: Int
    let shortcutEventCount: Int
    let lastShortcutEvent: String
    let selectedScreenID: String
    let activeZone: Zone
    let originals: [UUID: OriginalWindowState]
    let pendingTabs: [SavedTab]
    let configurationBlocked: Bool
    let terminating: Bool
    let assignmentZone: Zone?
    let assignmentRequest: Int
    let workspaceActivationEvent: String
    let workspacePresentationRequests: Int
    let workspacePresentationStatus: String
    @MainActor init(_ model: AppModel) {
        preferencesBlocked = model.preferencesBlocked
        preferences = model.preferences
        loginEnabled = model.loginEnabled
        loginNeedsApproval = model.loginNeedsApproval
        loginMessage = model.loginMessage
        applicationAssignments = model.applicationAssignments
        installedApplications = model.installedApplications
        catalogMessage = model.catalogMessage
        launchingApplications = model.launchingApplications
        tabAppearance = model.tabAppearance
        layoutTemplate = model.layoutTemplate
        rowRatio = model.rowRatio
        revealTabsAtTopEdge = model.revealTabsAtTopEdge
        autoHideTabBars = model.autoHideTabBars
        ratio = model.ratio
        tabs = model.tabs
        demo = model.demo
        paused = model.paused
        spaceTransitioning = model.spaceTransitioning
        spaceChangeCount = model.spaceChangeCount
        lastSpaceChange = model.lastSpaceChange
        accessibilityNotices = model.accessibilityNotices
        message = model.message
        titles = model.titles
        windows = model.windows
        trusted = model.trusted
        scanning = model.scanning
        hasCompletedDiscovery = model.hasCompletedDiscovery
        hasCompletedFullDiscovery = model.hasCompletedFullDiscovery
        busy = model.busy
        displayConfigurationKey = model.displayConfigurationKey
        rightDragDetails = model.rightDragDetails
        rightDragStatus = model.rightDragStatus
        selectionTimings = model.selectionTimings
        switchingTabs = model.switchingTabs
        warnings = model.warnings
        shortcutWarnings = model.shortcutWarnings
        registeredShortcuts = model.registeredShortcuts
        globalShortcutEventCount = model.globalShortcutEventCount
        shortcutEventCount = model.shortcutEventCount
        lastShortcutEvent = model.lastShortcutEvent
        selectedScreenID = model.selectedScreenID
        activeZone = model.activeZone
        originals = model.originals
        pendingTabs = model.pendingTabs
        configurationBlocked = model.configurationBlocked
        terminating = model.terminating
        assignmentZone = model.assignmentZone
        assignmentRequest = model.assignmentRequest
        workspaceActivationEvent = model.workspaceActivationEvent
        workspacePresentationRequests = model.workspacePresentationRequests
        workspacePresentationStatus = model.workspacePresentationStatus
    }
    @MainActor func apply(to model: AppModel) {
        model.preferencesBlocked = preferencesBlocked
        if model.preferences != preferences { model.preferences = preferences }
        model.loginEnabled = loginEnabled
        model.loginNeedsApproval = loginNeedsApproval
        model.loginMessage = loginMessage
        if model.applicationAssignments != applicationAssignments {
            model.applicationAssignments = applicationAssignments
        }
        if model.installedApplications != installedApplications { model.installedApplications = installedApplications }
        if model.catalogMessage != catalogMessage { model.catalogMessage = catalogMessage }
        if model.launchingApplications != launchingApplications { model.launchingApplications = launchingApplications }
        if model.tabAppearance != tabAppearance { model.tabAppearance = tabAppearance }
        if model.layoutTemplate != layoutTemplate { model.layoutTemplate = layoutTemplate }
        if model.rowRatio != rowRatio { model.rowRatio = rowRatio }
        if model.revealTabsAtTopEdge != revealTabsAtTopEdge { model.revealTabsAtTopEdge = revealTabsAtTopEdge }
        if model.autoHideTabBars != autoHideTabBars { model.autoHideTabBars = autoHideTabBars }
        if model.ratio != ratio { model.ratio = ratio }
        if model.tabs != tabs { model.tabs = tabs }
        if model.demo != demo { model.demo = demo }
        if model.paused != paused { model.paused = paused }
        if model.spaceTransitioning != spaceTransitioning { model.spaceTransitioning = spaceTransitioning }
        if model.spaceChangeCount != spaceChangeCount { model.spaceChangeCount = spaceChangeCount }
        if model.lastSpaceChange != lastSpaceChange { model.lastSpaceChange = lastSpaceChange }
        if model.accessibilityNotices != accessibilityNotices { model.accessibilityNotices = accessibilityNotices }
        if model.message != message { model.message = message }
        if model.titles != titles { model.titles = titles }
        if model.windows != windows { model.windows = windows }
        if model.trusted != trusted { model.trusted = trusted }
        if model.scanning != scanning { model.scanning = scanning }
        if model.hasCompletedDiscovery != hasCompletedDiscovery { model.hasCompletedDiscovery = hasCompletedDiscovery }
        if model.hasCompletedFullDiscovery != hasCompletedFullDiscovery {
            model.hasCompletedFullDiscovery = hasCompletedFullDiscovery
        }
        if model.busy != busy { model.busy = busy }
        model.rightDragDetails = rightDragDetails
        model.rightDragStatus = rightDragStatus
        model.selectionTimings = selectionTimings
        if model.switchingTabs != switchingTabs { model.switchingTabs = switchingTabs }
        if model.warnings != warnings { model.warnings = warnings }
        if model.shortcutWarnings != shortcutWarnings { model.shortcutWarnings = shortcutWarnings }
        if model.registeredShortcuts != registeredShortcuts { model.registeredShortcuts = registeredShortcuts }
        if model.globalShortcutEventCount != globalShortcutEventCount {
            model.globalShortcutEventCount = globalShortcutEventCount
        }
        if model.shortcutEventCount != shortcutEventCount { model.shortcutEventCount = shortcutEventCount }
        if model.lastShortcutEvent != lastShortcutEvent { model.lastShortcutEvent = lastShortcutEvent }
        if model.selectedScreenID != selectedScreenID { model.selectedScreenID = selectedScreenID }
        if model.activeZone != activeZone { model.activeZone = activeZone }
        if model.originals != originals { model.originals = originals }
        if model.pendingTabs != pendingTabs { model.pendingTabs = pendingTabs }
        if model.configurationBlocked != configurationBlocked { model.configurationBlocked = configurationBlocked }
        if model.terminating != terminating { model.terminating = terminating }
        if model.assignmentZone != assignmentZone { model.assignmentZone = assignmentZone }
        if model.assignmentRequest != assignmentRequest { model.assignmentRequest = assignmentRequest }
        if model.workspaceActivationEvent != workspaceActivationEvent {
            model.workspaceActivationEvent = workspaceActivationEvent
        }
        if model.workspacePresentationRequests != workspacePresentationRequests {
            model.workspacePresentationRequests = workspacePresentationRequests
        }
        if model.workspacePresentationStatus != workspacePresentationStatus {
            model.workspacePresentationStatus = workspacePresentationStatus
        }
    }
}
