import AppKit
import ApplicationServices

@MainActor
enum PermissionService {
    static var trusted: Bool { AXIsProcessTrusted() }

    // One user action opens one settings pane. Do not also issue the AX prompt:
    // it remains open until the user clicks its own Open Settings button.
    static func openSettings() {
        guard let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility")
        else { return }
        NSWorkspace.shared.open(url)
    }

    static func revealCurrentApplication() {
        NSWorkspace.shared.activateFileViewerSelecting([Bundle.main.bundleURL])
    }
}
