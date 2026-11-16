/// Stable identities shared by the app, persistence checks, and app discovery.
/// Changing these values can break Accessibility access and saved assignments.
public enum SpaceTabsIdentity {
    public static let appBundleID = "dev.spacetabs.mac"
    public static let finderBundleID = "dev.spacetabs.mac.finder"
    public static let finderBundlePath = "Contents/PlugIns/SpaceTabs Desktop Menu.appex"
    public static let desktopMenuScheme = "spacetabs"
    public static let settingsBundleID = "dev.spacetabs.mac.settings"
    public static let settingsAppName = "SpaceTabs Settings"
    public static let settingsBundlePath = "Contents/Helpers/SpaceTabs Settings.app"
}
