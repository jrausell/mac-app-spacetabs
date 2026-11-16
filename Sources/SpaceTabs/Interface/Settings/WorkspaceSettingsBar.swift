import AppKit
import SpaceTabsCore
import SwiftUI

struct WorkspaceSettingsBar: View {
    private let localization = AppLocalization.shared
    @Bindable var model: AppModel
    @State private var renameTarget: WorkspaceSummary?
    var body: some View {
        let _ = localization.language
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Picker(
                    L10n.tr("Workspace"),
                    selection: Binding(
                        get: { model.workspaceID },
                        set: { if let id = $0 { _ = model.sendToManager(.selectWorkspace(id)) } }
                    )
                ) {
                    ForEach(model.workspaceSummaries) { summary in
                        Text("\(summary.name) · \(summary.displayName)").tag(Optional(summary.id))
                    }
                }.frame(maxWidth: 370)
                Button {
                    renameTarget = model.workspaceSummaries.first { $0.id == model.workspaceID }
                } label: {
                    Image(systemName: "pencil")
                }.help(L10n.tr("Rename Workspace")).accessibilityLabel(L10n.tr("Rename Workspace"))
                    .disabled(model.workspaceID == nil || model.configurationBlocked || model.terminating)
                Spacer()
                if let id = model.workspaceID,
                    model.workspaceSummaries.first(where: { $0.id == id })?.isOpen == false
                {
                    Menu(L10n.tr("Open profile here")) {
                        ForEach(NSScreen.screens, id: \.self) { screen in
                            Button(L10n.tr("Open here on \(screen.localizedName)")) {
                                _ = model.sendToManager(.openWorkspaceHere(id, AppModel.screenID(screen)))
                            }
                        }
                    }.fixedSize()
                }
                Menu(L10n.tr("New workspace")) {
                    ForEach(NSScreen.screens, id: \.self) { screen in
                        Button(L10n.tr("New workspace on \(screen.localizedName)…")) {
                            _ = model.sendToManager(.newWorkspace(AppModel.screenID(screen)))
                        }
                    }
                }.fixedSize()
                if let id = model.workspaceID {
                    Menu {
                        Button(L10n.tr("Show")) { _ = model.sendToManager(.showWorkspace(id)) }
                            .disabled(!model.workspaceDesktopAvailable)
                        Button(L10n.tr("Restore")) { _ = model.sendToManager(.restoreWorkspace(id)) }
                            .disabled(!model.workspaceDesktopAvailable || model.busy)
                        if model.workspaceSummaries.first(where: { $0.id == id })?.isOpen == false {
                            ForEach(NSScreen.screens, id: \.self) { screen in
                                Button(L10n.tr("Open here on \(screen.localizedName)")) {
                                    _ = model.sendToManager(.openWorkspaceHere(id, AppModel.screenID(screen)))
                                }
                            }
                        } else {
                            Button(L10n.tr("Close workspace")) { _ = model.sendToManager(.closeWorkspace(id)) }
                                .disabled(!model.workspaceDesktopAvailable || model.busy)
                        }
                    } label: {
                        Image(systemName: "ellipsis.circle")
                    }.fixedSize()
                }
            }
            if !model.workspaceDesktopAvailable {
                Text(
                    L10n.tr(
                        "Open this workspace here, or switch to the desktop where it is already open. After restarting SpaceTabs, choose a desktop for each saved workspace."
                    )
                )
                .font(.caption).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
            }
        }.padding(16)
            .sheet(item: $renameTarget) { workspace in
                RenameSetupSheet(title: L10n.tr("Rename Workspace"), name: workspace.name) {
                    _ = model.sendToManager(.renameWorkspace(workspace.id, $0))
                }
            }
    }
}
