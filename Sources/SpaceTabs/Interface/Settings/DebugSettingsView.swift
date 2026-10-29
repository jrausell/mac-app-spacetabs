import AppKit
import SpaceTabsCore
import SwiftUI

struct DebugSettingsView: View {
    private let localization = AppLocalization.shared
    @Bindable var model: AppModel
    var body: some View {
        let _ = localization.language
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                HStack {
                    Text(L10n.tr("Status and Diagnostics")).font(.headline)
                    Spacer()
                    Button(L10n.tr("Copy Full Diagnostics")) { model.copyDiagnostics() }
                }
                GroupBox(L10n.tr("Problem History")) {
                    VStack(alignment: .leading, spacing: 8) {
                        Text(
                            L10n.tr(
                                "Errors, slow operations, and suspected UI freezes are logged automatically across restarts. Logs stay on this Mac and rotate at 4 MB total. They may contain app names, window titles, and file paths; review before sharing."
                            )
                        )
                        .font(.caption).foregroundStyle(.secondary)
                        HStack {
                            Button(L10n.tr("Show Logs in Finder")) { model.revealDiagnosticLogs() }
                            Button(L10n.tr("Copy Log History")) { model.copyDiagnosticLogs() }
                        }
                    }.padding(8)
                }
                GroupBox(L10n.tr("Current State")) {
                    VStack(alignment: .leading, spacing: 8) {
                        LabeledContent(
                            L10n.tr("Accessibility"), value: model.trusted ? L10n.tr("Granted") : L10n.tr("Pending"))
                        LabeledContent(
                            L10n.tr("Manager"),
                            value: model.spaceTransitioning
                                ? L10n.tr("Desktop transition") : (model.paused ? L10n.tr("Paused") : L10n.tr("Active"))
                        )
                        LabeledContent(L10n.tr("Desktop Changes"), value: "\(model.spaceChangeCount)")
                        Text(model.lastSpaceChange).font(.caption).textSelection(.enabled)
                        LabeledContent(
                            L10n.tr("Operation"), value: model.busy ? L10n.tr("In progress") : L10n.tr("Idle"))
                        LabeledContent(
                            L10n.tr("Windows"),
                            value: L10n.tr("\(model.windows.count) found · \(model.originals.count) managed"))
                        LabeledContent(
                            L10n.tr("Discovery"),
                            value: model.scanning
                                ? L10n.tr("Scanning")
                                : (model.hasCompletedFullDiscovery ? L10n.tr("Full index") : L10n.tr("Partial index")))
                        LabeledContent(
                            L10n.tr("Shortcuts"),
                            value:
                                L10n.tr(
                                    "\(model.registeredShortcuts.count)/\(ShortcutManager.Action.allCases.count) registered · \(model.shortcutEventCount) actions"
                                )
                        )
                        LabeledContent(L10n.tr("Global Key Presses"), value: "\(model.globalShortcutEventCount)")
                        Text(model.lastShortcutEvent).font(.caption).textSelection(.enabled)
                        LabeledContent(L10n.tr("Tab selection"), value: model.selectionTimings.summary)
                        LabeledContent(L10n.tr("Workspace Restores"), value: "\(model.workspacePresentationRequests)")
                        Text(model.workspaceActivationEvent).font(.caption).textSelection(.enabled)
                        Text(model.workspacePresentationStatus).font(.caption).textSelection(.enabled)
                    }.padding(8)
                }
                GroupBox(L10n.tr("Current Notices")) {
                    VStack(alignment: .leading, spacing: 10) {
                        if let message = model.message {
                            Text(message).textSelection(.enabled)
                            Button(L10n.tr("Dismiss Message")) { model.dismissMessage() }
                        }
                        if let message = model.catalogMessage { Text(message).font(.caption).textSelection(.enabled) }
                        ForEach(Array(model.warnings.enumerated()), id: \.offset) { _, warning in
                            Text(warning).textSelection(.enabled)
                        }
                        ForEach(model.shortcutWarnings, id: \.self) { Text($0).textSelection(.enabled) }
                        if model.message == nil && model.warnings.isEmpty && model.shortcutWarnings.isEmpty {
                            Text(L10n.tr("No reported problems.")).foregroundStyle(.secondary)
                        }
                    }.frame(maxWidth: .infinity, alignment: .leading).padding(8)
                }
                if !model.accessibilityNotices.isEmpty {
                    GroupBox(L10n.tr("AX Notification Support")) {
                        VStack(alignment: .leading, spacing: 8) {
                            Text(
                                L10n.tr(
                                    "These notices do not pause SpaceTabs or mean global access was lost. Refresh retries notifications and window discovery for the affected apps."
                                )
                            )
                            .font(.caption).foregroundStyle(.secondary)
                            ForEach(model.accessibilityNotices, id: \.self) {
                                Text($0).font(.caption).textSelection(.enabled)
                            }
                        }.frame(maxWidth: .infinity, alignment: .leading).padding(8)
                    }
                }
                GroupBox(L10n.tr("Control + Right-Drag Gesture")) {
                    VStack(alignment: .leading, spacing: 8) {
                        Text(model.rightDragStatus).font(.callout)
                        Text(model.rightDragDetails).font(.system(.caption, design: .monospaced)).textSelection(
                            .enabled)
                    }.frame(maxWidth: .infinity, alignment: .leading).padding(8)
                }
                if !model.pendingTabs.isEmpty {
                    GroupBox(L10n.tr("Pending Session")) {
                        VStack(alignment: .leading, spacing: 8) {
                            Text(model.savedSessionSummary)
                            ForEach(model.pendingTabs) { tab in
                                Text(
                                    "\(tab.zone.title) · \(tab.identity.title.isEmpty ? L10n.tr("Untitled") : tab.identity.title) · \(tab.identity.bundleID)"
                                )
                                .font(.caption).textSelection(.enabled)
                            }
                            Button(L10n.tr("Forget Pending Windows")) { model.forgetPending() }.disabled(model.busy)
                        }.frame(maxWidth: .infinity, alignment: .leading).padding(8)
                    }
                }
                GroupBox(L10n.tr("Access and Maintenance")) {
                    VStack(alignment: .leading, spacing: 10) {
                        Text(model.applicationBundleURL.path).font(.caption).textSelection(.enabled)
                        HStack {
                            Button(L10n.tr("Accessibility")) { model.requestPermission() }
                            Button(L10n.tr("Check Access")) { model.recheckPermission() }
                            Button(L10n.tr("Show This App")) { model.revealApplication() }
                        }
                        HStack {
                            Button(L10n.tr("Reapply Layout")) { model.reapplyLayout() }.disabled(
                                model.busy || model.paused)
                            Button(model.demo ? L10n.tr("Exit Demo") : L10n.tr("Try Demo")) {
                                model.demo ? model.stopDemo() : model.startDemo()
                            }
                            .disabled(model.busy || (!model.demo && !model.originals.isEmpty))
                        }
                        if model.preferencesBlocked {
                            Button(L10n.tr("Repair Preferences and Keep a Backup")) { model.resetUserPreferences() }
                        }
                        if model.configurationBlocked {
                            Button(L10n.tr("Reset Configuration and Keep a Backup")) { model.resetConfiguration() }
                        }
                        Text(
                            L10n.tr(
                                "The copied report includes the AX trace, zone frames, and discovery counters. It is collected only when you select the button."
                            )
                        )
                        .font(.caption).foregroundStyle(.secondary)
                    }.padding(8)
                }
            }.frame(maxWidth: .infinity, alignment: .leading).padding(16)
        }
    }
}
