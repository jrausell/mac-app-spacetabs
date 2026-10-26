import AppKit
import SpaceTabsCore

struct SettingsLayoutPreferences: Codable, Equatable {
    let ratio: Double
    let rowRatio: Double
    let screenID: String
    let autoHide: Bool
    let revealAtTop: Bool
    @MainActor init(_ model: AppModel) {
        ratio = model.ratio
        rowRatio = model.rowRatio
        screenID = model.selectedScreenID
        autoHide = model.autoHideTabBars
        revealAtTop = model.revealTabsAtTopEdge
    }
    var isValid: Bool {
        ratio.isFinite && (0.2...0.8).contains(ratio) && rowRatio.isFinite && (0.25...0.75).contains(rowRatio)
    }
}

enum SettingsCommand: Codable {
    case bindProfile(UUID, Bool)
    case zoom, openSwitcher
    case reorderTab(UUID, Zone, UUID?)
    case rightDrag(Bool)
    case language(AppLanguage)
    case resetPreferences
    case binding(UInt32, ShortcutBinding)
    case resetBindings
    case zoneName(Zone, String)
    case saveProfile(String, UUID?)
    case applyProfile(UUID)
    case deleteProfile(UUID)
    case login(Bool)
    case loginSettings, loginStatus
    case showTabs, refreshApps, refreshWindows, permission, recheck, releaseAll, pause
    case assign(UUID, Zone)
    case release(UUID)
    case template(LayoutTemplate)
    case layout(SettingsLayoutPreferences)
    case appearance(TabAppearance)
    case launch(String)
    case assignApp(String, Zone)
    case removeApp(String)
    case restore, forget, demo, reset, reapply, diagnostics, restartShortcuts
    case shortcut(UInt32)
    case addApps([URL])
    case filter(Zone?)
    case clearMessage, revealApplication
}
