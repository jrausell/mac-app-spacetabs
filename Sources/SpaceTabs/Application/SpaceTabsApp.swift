import AppKit
import ApplicationServices
import SpaceTabsCore
import SwiftUI

@main
enum SpaceTabsApp {
    @MainActor static func main() {
        let arguments = CommandLine.arguments
        let choice: AppLanguage
        if let index = arguments.firstIndex(of: "--language"), arguments.indices.contains(index + 1) {
            choice = AppLanguage(rawValue: arguments[index + 1]) ?? .automatic
        } else {
            // Resolve the saved override before constructing models and menus.
            // The manager loads preferences again for ownership and error reporting.
            choice = (try? UserPreferencesStore.standard.load().language) ?? .automatic
        }
        L10n.configure(choice)
        if Bundle.main.bundleIdentifier == SettingsHost.helperID {
            SettingsApplication.run()
            return
        }
        if CommandLine.arguments.contains("--diagnostics") {
            let info: [String: Any] = [
                "app": "SpaceTabs",
                "language": L10n.language.rawValue,
                "settingsAppName": L10n.tr("SpaceTabs Settings"),
                "version": Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "development",
                "macOS": ProcessInfo.processInfo.operatingSystemVersionString,
                "accessibilityTrusted": AXIsProcessTrusted(),
                "bundleIdentifier": Bundle.main.bundleIdentifier ?? "no bundle",
                "configurationPath": PersistenceStore.standard.url.path,
            ]
            if let data = try? JSONSerialization.data(withJSONObject: info, options: [.prettyPrinted, .sortedKeys]),
                let output = String(data: data, encoding: .utf8)
            {
                print(output)
            }
            return
        }
        if CommandLine.arguments.contains("--smoke-test") {
            FileHandle.standardError.write(Data("SpaceTabs smoke: starting NSApplication…\n".utf8))
        }
        let app = NSApplication.shared
        if CommandLine.arguments.contains("--smoke-test") {
            FileHandle.standardError.write(Data("SpaceTabs smoke: NSApplication created.\n".utf8))
        }
        let delegate = AppDelegate()
        app.delegate = delegate
        app.setActivationPolicy(.regular)
        delegate.installMainMenu()
        withExtendedLifetime(delegate) { app.run() }
    }
}
