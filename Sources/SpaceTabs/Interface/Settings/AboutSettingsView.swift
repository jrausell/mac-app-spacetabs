import AppKit
import SpaceTabsCore
import SwiftUI

struct AboutSettingsView: View {
    private let localization = AppLocalization.shared
    let model: AppModel
    var body: some View {
        let _ = localization.language
        ScrollView {
            VStack(spacing: 16) {
                Image(nsImage: NSWorkspace.shared.icon(forFile: model.applicationBundleURL.path)).resizable().frame(
                    width: 80, height: 80)
                Text("SpaceTabs").font(.largeTitle.bold())
                Text(L10n.tr("Version \(model.appVersion)")).foregroundStyle(.secondary)
                Text(L10n.tr("Your windows. Your zones. One desktop.")).font(.headline)
                Text(
                    L10n.tr(
                        "Organize real macOS windows into zones with independent tabs. A native prototype built with Swift, SwiftUI, and AppKit."
                    )
                )
                .multilineTextAlignment(.center).frame(maxWidth: 440)
                Divider().frame(maxWidth: 440)
                Text(L10n.tr("Developed by Jorge Rausell"))
                Text(
                    L10n.tr(
                        "Windows still belong to their apps. macOS controls Spaces, native full screen, and floating windows."
                    )
                )
                .font(.caption).foregroundStyle(.secondary).multilineTextAlignment(.center).frame(maxWidth: 440)
            }.frame(maxWidth: .infinity).padding(32)
        }
    }
}
