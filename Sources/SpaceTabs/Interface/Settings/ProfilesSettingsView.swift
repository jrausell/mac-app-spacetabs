import AppKit
import SpaceTabsCore
import SwiftUI

struct ProfilesSettingsView: View {
    private let localization = AppLocalization.shared
    @Bindable var model: AppModel
    @State private var name = ""
    @State private var deleteTarget: WorkspaceProfile?
    @State private var updateTarget: WorkspaceProfile?
    var body: some View {
        let _ = localization.language
        ScrollView {
            VStack(alignment: .leading, spacing: 22) {
                SettingsCard(
                    title: L10n.tr("Save your setup"),
                    subtitle: L10n.tr("Create a profile for work, study, or another task.")
                ) {
                    HStack {
                        TextField(L10n.tr("Profile name"), text: $name).textFieldStyle(.roundedBorder)
                            .onChange(of: name) {
                                if name.count > PreferenceLimits.profileNameCharacters {
                                    name = String(name.prefix(PreferenceLimits.profileNameCharacters))
                                }
                            }
                        Button(L10n.tr("Save Profile")) {
                            model.saveProfile(name: name)
                            name = ""
                        }
                        .buttonStyle(.borderedProminent)
                        .disabled(
                            name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                                || model.preferences.profiles.count >= PreferenceLimits.profiles || model.busy)
                    }
                    Text(
                        L10n.tr(
                            "Saves the template, sizes, display, names, appearance, tabs, and app assignments. Choose below whether each profile opens closed assigned apps. Unlisted windows keep their current zone."
                        )
                    )
                    .font(.caption).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
                }
                if model.preferences.profiles.isEmpty {
                    ContentUnavailableView(
                        L10n.tr("Your first profile"), systemImage: "rectangle.stack",
                        description: Text(
                            L10n.tr("Set up your zones, then save the layout here to use it again later.")))
                }
                ForEach(model.preferences.profiles) { profile in
                    HStack(spacing: 18) {
                        LayoutTemplatePreview(
                            template: profile.layout.template, ratio: profile.layout.ratio,
                            rowRatio: profile.layout.rowRatio
                        )
                        .frame(width: 110, height: 75)
                        VStack(alignment: .leading, spacing: 5) {
                            Text(profile.name).font(.headline)
                            Text(profile.layout.template.title).foregroundStyle(.secondary)
                            if model.preferences.displayProfiles[model.displayConfigurationKey] == profile.id {
                                Label(L10n.tr("Automatic for these displays"), systemImage: "display.2").font(.caption)
                                    .foregroundStyle(.blue)
                            }
                            Text(
                                L10n.tr(
                                    "\(profile.layout.applicationAssignments.count) apps · \(profile.layout.tabs.count) windows"
                                )
                            ).font(.caption).foregroundStyle(.secondary)
                            Toggle(
                                L10n.tr("Open closed assigned apps when switching manually"),
                                isOn: Binding(
                                    get: { profile.openAssignedApps },
                                    set: { model.setProfileOpenAssignedApps(profile.id, enabled: $0) })
                            )
                            .toggleStyle(.checkbox).font(.caption)
                            .disabled(model.preferencesBlocked || model.busy)
                            .help(
                                L10n.tr(
                                    "Uses saved app assignments. Automatic display profiles keep closed apps closed. Browser tabs and documents are not recreated."
                                ))
                        }
                        Spacer()
                        Button(L10n.tr("Apply")) { model.applyProfile(profile.id) }
                            .disabled(!model.canApplyProfile)
                        Menu {
                            Button(
                                model.preferences.displayProfiles[model.displayConfigurationKey] == profile.id
                                    ? L10n.tr("Unlink from these displays")
                                    : L10n.tr("Use automatically with these displays")
                            ) {
                                model.bindProfile(
                                    profile.id,
                                    enabled: model.preferences.displayProfiles[model.displayConfigurationKey]
                                        != profile.id)
                            }
                            Button(L10n.tr("Replace with Current Setup…")) { updateTarget = profile }
                            Button(L10n.tr("Delete…"), role: .destructive) { deleteTarget = profile }
                        } label: {
                            Image(systemName: "ellipsis")
                        }.menuStyle(.borderlessButton).frame(width: 25)
                    }.padding(18).background(
                        Color(nsColor: .controlBackgroundColor), in: RoundedRectangle(cornerRadius: 12))
                }
                Text(L10n.tr("Save up to \(PreferenceLimits.profiles) profiles locally on this Mac.")).font(.caption)
                    .foregroundStyle(.secondary)
            }.padding(24).frame(maxWidth: 850).frame(maxWidth: .infinity)
        }
        .confirmationDialog(
            L10n.tr("Delete this profile?"),
            isPresented: Binding(get: { deleteTarget != nil }, set: { if !$0 { deleteTarget = nil } }),
            presenting: deleteTarget
        ) { profile in
            Button(L10n.tr("Delete"), role: .destructive) {
                model.deleteProfile(profile.id)
                deleteTarget = nil
            }
        }
        .confirmationDialog(
            L10n.tr("Replace this profile with the current setup?"),
            isPresented: Binding(get: { updateTarget != nil }, set: { if !$0 { updateTarget = nil } }),
            presenting: updateTarget
        ) { profile in
            Button(L10n.tr("Update Profile")) {
                model.saveProfile(name: profile.name, replacing: profile.id)
                updateTarget = nil
            }
        }
    }
}
