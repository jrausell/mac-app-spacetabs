import AppKit
import SpaceTabsCore
import SwiftUI

struct ShortcutSettingsView: View {
    private let localization = AppLocalization.shared
    @Bindable var model: AppModel
    var body: some View {
        let _ = localization.language
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                HStack {
                    VStack(alignment: .leading, spacing: 4) {
                        Text(L10n.tr("Global Shortcuts")).font(.headline)
                        Text(L10n.tr("⌃ Control · ⌥ Option · ⇧ Shift · ⌘ Command")).font(.caption).foregroundStyle(
                            .secondary)
                    }
                    Spacer()
                    Text(
                        L10n.tr(
                            "\(model.registeredShortcuts.count)/\(ShortcutManager.Action.allCases.count) registered")
                    ).font(
                        .caption)
                    Button(L10n.tr("Restore Defaults")) { model.resetShortcutBindings() }
                    Button(L10n.tr("Retry Registration")) { model.restartShortcuts() }
                }
                if model.paused {
                    Label(
                        L10n.tr("SpaceTabs is paused. Resume to switch or move windows."), systemImage: "pause.circle"
                    )
                    .font(.callout).foregroundStyle(.orange)
                }
                VStack(spacing: 0) {
                    ForEach(ShortcutManager.Action.allCases, id: \.rawValue) { action in
                        let parts = action.label.components(separatedBy: " · ")
                        let enabled = (model.preferences.shortcuts[action.rawValue] ?? action.defaultBinding).enabled
                        HStack {
                            Image(
                                systemName: !enabled
                                    ? "minus.circle"
                                    : model.registeredShortcuts.contains(action.rawValue)
                                        ? "checkmark.circle.fill" : "exclamationmark.circle"
                            )
                            .foregroundStyle(
                                !enabled
                                    ? Color.secondary
                                    : model.registeredShortcuts.contains(action.rawValue) ? Color.green : .orange)
                            Text(parts[0])
                            Spacer()
                            ShortcutEditor(model: model, action: action)
                            Button(L10n.tr("Test")) {
                                model.handleShortcut(action, source: L10n.tr("Test in Settings"))
                            }
                            .disabled((action == .focusC || action == .moveC) && !model.activeZones.contains(.c))
                        }.padding(10)
                        if action != ShortcutManager.Action.allCases.last { Divider() }
                    }
                }.background(.quaternary.opacity(0.4), in: RoundedRectangle(cornerRadius: 10))
                Text(
                    L10n.tr(
                        "Key shortcuts register with macOS; modifier-only shortcuts use passive observation and cannot report conflicts with other apps. Test runs the action without testing key delivery. Shortcuts for C require a three-zone template."
                    )
                )
                .font(.caption).foregroundStyle(.secondary)
                GroupBox(L10n.tr("Other Actions")) {
                    VStack(alignment: .leading, spacing: 10) {
                        LabeledContent(L10n.tr("Assign from Window Content"), value: L10n.tr("Control + right-drag"))
                        LabeledContent(L10n.tr("Native Drag"), value: L10n.tr("Command + Shift + window drag"))
                        LabeledContent(L10n.tr("Fill Zone"), value: L10n.tr("Double-click its tab"))
                        LabeledContent(
                            L10n.tr("Restore All Zones"),
                            value: L10n.tr("Command + Tab to SpaceTabs, or click its Dock icon"))
                        LabeledContent(
                            L10n.tr("Open Settings"), value: L10n.tr("Command + comma with SpaceTabs active"))
                    }.padding(8)
                }
                Text(L10n.tr("Global key presses received: \(model.globalShortcutEventCount)")).font(.caption)
                Text(L10n.tr("Last action: \(model.lastShortcutEvent)")).font(.caption).textSelection(.enabled)
                ForEach(model.shortcutWarnings, id: \.self) {
                    Text($0).foregroundStyle(.orange).textSelection(.enabled)
                }
            }.frame(maxWidth: .infinity, alignment: .leading).padding(16)
        }
    }
}
