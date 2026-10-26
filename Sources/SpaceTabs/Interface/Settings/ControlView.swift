import AppKit
import SpaceTabsCore
import SwiftUI

enum SettingsSection: String, CaseIterable, Identifiable {
    case general = "General"
    case apps = "Apps"
    case design = "Design"
    case profiles = "Profiles"
    case shortcuts = "Shortcuts"
    case debug = "Diagnostics"
    case about = "About"
    var id: String { rawValue }
    var title: String { L10n.text(rawValue) }
    var icon: String {
        switch self {
        case .general: "slider.horizontal.3"
        case .apps: "app.badge"
        case .design: "rectangle.split.2x1"
        case .profiles: "rectangle.stack"
        case .shortcuts: "keyboard"
        case .debug: "stethoscope"
        case .about: "info.circle"
        }
    }
    var subtitle: String {
        switch self {
        case .general: L10n.tr("Essential preferences for your desktop.")
        case .apps: L10n.tr("Choose which apps belong in each zone.")
        case .design: L10n.tr("Set the layout and appearance of your zones.")
        case .profiles: L10n.tr("Save a setup for each task.")
        case .shortcuts: L10n.tr("Control your zones with custom keyboard shortcuts.")
        case .debug: L10n.tr("Manager status, compatibility, and diagnostic tools.")
        case .about: L10n.tr("A more organized way to work on your Mac.")
        }
    }
}

struct ControlView: View {
    private let localization = AppLocalization.shared
    @Bindable var model: AppModel
    @State private var section: SettingsSection = .apps
    private var status: String {
        model.demo
            ? L10n.tr("Demo")
            : !model.trusted
                ? L10n.tr("Access needed")
                : model.spaceTransitioning
                    ? L10n.tr("Switching desktops") : model.paused ? L10n.tr("Paused") : L10n.tr("Active")
    }
    var body: some View {
        let _ = localization.language
        HStack(spacing: 0) {
            VStack(alignment: .leading, spacing: 22) {
                HStack(spacing: 10) {
                    Image(nsImage: NSWorkspace.shared.icon(forFile: model.applicationBundleURL.path))
                        .resizable().frame(width: 36, height: 36)
                    VStack(alignment: .leading, spacing: 2) {
                        Text("SpaceTabs").font(.headline)
                        Text(L10n.tr("Settings")).font(.caption).foregroundStyle(.secondary)
                    }
                }.padding(.horizontal, 16).padding(.top, 24)
                VStack(spacing: 4) {
                    ForEach(SettingsSection.allCases) { item in
                        Button {
                            section = item
                        } label: {
                            Label(item.title, systemImage: item.icon)
                                .font(.system(size: 13, weight: section == item ? .semibold : .regular))
                                .frame(maxWidth: .infinity, alignment: .leading).padding(.horizontal, 12).padding(
                                    .vertical, 10
                                )
                                .background(
                                    section == item ? Color.accentColor.opacity(0.15) : .clear,
                                    in: RoundedRectangle(cornerRadius: 8)
                                )
                                .contentShape(Rectangle())
                        }.buttonStyle(.plain)
                    }
                }.padding(.horizontal, 10)
                Spacer()
                Divider()
                HStack(spacing: 7) {
                    Circle().fill(model.trusted && !model.managementSuspended ? Color.green : .orange).frame(
                        width: 7, height: 7)
                    Text(status).font(.caption)
                    if model.busy || model.scanning { ProgressView().controlSize(.mini) }
                }.padding(.horizontal, 18)
                Text(L10n.tr("Version \(model.appVersion)")).font(.caption2).foregroundStyle(.secondary).padding(
                    .horizontal, 18
                )
                .padding(.bottom, 16)
            }.frame(width: 190).background(.regularMaterial)
            Divider()
            VStack(spacing: 0) {
                VStack(alignment: .leading, spacing: 5) {
                    Text(section.title).font(.system(size: 25, weight: .bold))
                    Text(section.subtitle).font(.callout).foregroundStyle(.secondary)
                }.frame(maxWidth: .infinity, alignment: .leading).padding(.horizontal, 24).padding(.vertical, 20)
                Divider()
                if section != .apps, let message = model.message {
                    HStack(alignment: .top, spacing: 10) {
                        Image(systemName: "info.circle").foregroundStyle(Color.accentColor)
                        Text(message).font(.caption).lineLimit(2).frame(maxWidth: .infinity, alignment: .leading)
                        Button(L10n.tr("Details")) { section = .debug }.controlSize(.small)
                        Button {
                            model.dismissMessage()
                        } label: {
                            Image(systemName: "xmark")
                        }.buttonStyle(.plain).help(L10n.tr("Dismiss Message"))
                    }.padding(.horizontal, 24).padding(.vertical, 10).background(Color.accentColor.opacity(0.06))
                }
                Group {
                    switch section {
                    case .general: GeneralSettingsView(model: model)
                    case .apps: AppsSettingsView(model: model, showDebug: { section = .debug })
                    case .design: DesignSettingsView(model: model)
                    case .profiles: ProfilesSettingsView(model: model)
                    case .shortcuts: ShortcutSettingsView(model: model)
                    case .debug: DebugSettingsView(model: model)
                    case .about: AboutSettingsView(model: model)
                    }
                }.frame(maxWidth: .infinity, maxHeight: .infinity)
                Divider()
                HStack {
                    Button(L10n.tr("Search…")) { if !model.sendToManager(.openSwitcher) { model.showQuickSwitcher() } }
                    Button(L10n.tr("Show Tabs")) { model.showTabBars() }
                        .help(
                            (model.preferences.shortcuts[ShortcutManager.Action.showTabs.rawValue]
                                ?? ShortcutManager.Action.showTabs.defaultBinding).display)
                    Button(model.paused ? L10n.tr("Resume") : L10n.tr("Pause")) { model.togglePause() }.disabled(
                        model.busy || model.spaceTransitioning)
                    Spacer()
                    Button(L10n.tr("Release All")) { model.releaseAll() }
                        .disabled((model.originals.isEmpty && model.applicationAssignments.isEmpty) || model.busy)
                }.controlSize(.small).padding(.horizontal, 24).padding(.vertical, 12)
            }.background(Color(nsColor: .windowBackgroundColor))
        }.frame(minWidth: 980, minHeight: 620)
            .environment(\.locale, Locale(identifier: localization.language.rawValue))
            .disabled(model.remoteSettings != nil && !model.remoteSettingsConnected)
            .overlay {
                if model.remoteSettings != nil && !model.remoteSettingsConnected {
                    ProgressView(L10n.tr("Connecting to SpaceTabs…")).padding(24).background(
                        .regularMaterial, in: RoundedRectangle(cornerRadius: 12))
                }
            }
            .onChange(of: model.assignmentRequest) {
                section = .apps
                model.settingsShowsApplications = true
            }
    }
}
