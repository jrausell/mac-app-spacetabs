import SpaceTabsCore
import SwiftUI

struct GeneralSettingsView: View {
    private let localization = AppLocalization.shared
    @Bindable var model: AppModel
    var body: some View {
        let _ = localization.language
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                SettingsCard(
                    title: L10n.tr("Language"), subtitle: L10n.tr("Choose the language used throughout SpaceTabs.")
                ) {
                    Picker(
                        L10n.tr("App Language"),
                        selection: Binding(
                            get: { model.preferences.language }, set: { model.setLanguage($0) }
                        )
                    ) {
                        ForEach(AppLanguage.allCases) { language in
                            Text(language.displayName).tag(language)
                        }
                    }
                    Text(
                        L10n.tr(
                            "Automatic follows your Mac’s preferred languages. English is used when a language is not available. Changes apply immediately."
                        )
                    )
                    .font(.caption).foregroundStyle(.secondary)
                }
                SettingsCard(
                    title: L10n.tr("At login"), subtitle: L10n.tr("Have your zones ready when you start your Mac.")
                ) {
                    Toggle(
                        L10n.tr("Launch SpaceTabs at login"),
                        isOn: Binding(
                            get: { model.loginEnabled || model.loginNeedsApproval }, set: { model.setLoginEnabled($0) })
                    )
                    .toggleStyle(.switch)
                    if model.loginNeedsApproval {
                        Label(
                            L10n.tr("Waiting for approval in macOS System Settings."),
                            systemImage: "exclamationmark.circle"
                        )
                        .foregroundStyle(.orange)
                    }
                    if let message = model.loginMessage { Text(message).font(.caption).foregroundStyle(.orange) }
                    HStack {
                        Text(L10n.tr("Settings stays closed unless Accessibility access is missing.")).font(.caption)
                            .foregroundStyle(.secondary)
                        Spacer()
                        Button(L10n.tr("Login Items…")) { model.openLoginSettings() }
                    }
                }
                SettingsCard(
                    title: L10n.tr("Drag to assign"),
                    subtitle: L10n.tr("Assign a window by dragging from anywhere in its content.")
                ) {
                    Toggle(
                        L10n.tr("Control + right mouse button"),
                        isOn: Binding(get: { model.preferences.controlRightDrag }, set: { model.setRightDrag($0) }))
                    Text(
                        L10n.tr(
                            "Hold Control, press the right button over a window, and drag to a zone. Release the button to assign it, or release Control first to cancel. An outline follows the pointer. The real window moves when you release the button."
                        )
                    )
                    .font(.caption).foregroundStyle(.secondary)
                    Text(model.rightDragStatus).font(.caption).foregroundStyle(.secondary)
                    Text(
                        L10n.tr(
                            "Control + right-click is reserved while this gesture is enabled. Normal right-click and Command + Shift dragging still work."
                        )
                    )
                    .font(.caption).foregroundStyle(.secondary)
                }
                SettingsCard(
                    title: L10n.tr("Your zones"),
                    subtitle: L10n.tr("Add optional names. Zones keep their A, B, and C labels.")
                ) {
                    ForEach(Zone.allCases) { zone in
                        ZoneNameField(model: model, zone: zone)
                        if zone != .c { Divider() }
                    }
                    Text(
                        L10n.tr(
                            "B is always the main zone and receives focus when the workspace is restored. C is used in three-zone templates."
                        )
                    )
                    .font(.caption).foregroundStyle(.secondary)
                }
                SettingsCard(
                    title: L10n.tr("Window access"),
                    subtitle: L10n.tr("SpaceTabs needs Accessibility access to move and focus windows from other apps.")
                ) {
                    HStack {
                        Label(
                            model.trusted
                                ? L10n.tr("Accessibility access granted") : L10n.tr("Accessibility access needed"),
                            systemImage: model.trusted ? "checkmark.shield.fill" : "lock.shield"
                        )
                        .foregroundStyle(model.trusted ? Color.green : .orange)
                        Spacer()
                        Button(model.trusted ? L10n.tr("Check") : L10n.tr("Grant Access")) {
                            model.trusted ? model.recheckPermission() : model.requestPermission()
                        }
                    }
                }
            }.padding(24).frame(maxWidth: 850, alignment: .leading).frame(maxWidth: .infinity)
        }.onAppear { model.refreshLoginStatus() }
    }
}

private struct ZoneNameField: View {
    private let localization = AppLocalization.shared
    let model: AppModel
    let zone: Zone
    @State private var name = ""
    @FocusState private var focused: Bool
    var body: some View {
        let _ = localization.language
        HStack(spacing: 12) {
            Text(zone.title).font(.system(.body, design: .rounded).bold())
                .frame(width: 30, height: 30)
                .background(
                    (zone == .a ? Color.orange : zone == .b ? .blue : .green).opacity(0.15),
                    in: RoundedRectangle(cornerRadius: 7))
            TextField(zone == .b ? L10n.tr("Main") : L10n.tr("Optional name"), text: $name)
                .textFieldStyle(.roundedBorder).focused($focused)
                .onSubmit { save() }
                .onChange(of: focused) { if !focused { save() } }
                .onChange(of: name) {
                    if name.count > PreferenceLimits.zoneNameCharacters {
                        name = String(name.prefix(PreferenceLimits.zoneNameCharacters))
                    }
                }
            Text(zone == .b ? L10n.tr("Main") : L10n.tr("Secondary")).font(.caption).foregroundStyle(.secondary).frame(
                width: 75, alignment: .trailing)
        }
        .onAppear { name = model.preferences.zoneNames[zone, default: ""] }
        .onChange(of: model.preferences.zoneNames) {
            if !focused { name = model.preferences.zoneNames[zone, default: ""] }
        }
    }
    private func save() {
        if name != model.preferences.zoneNames[zone, default: ""] { model.setZoneName(zone, name: name) }
    }
}
