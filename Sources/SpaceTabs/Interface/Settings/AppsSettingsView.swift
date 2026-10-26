import AppKit
import SpaceTabsCore
import SwiftUI

struct AppsSettingsView: View {
    private let localization = AppLocalization.shared
    @Bindable var model: AppModel
    let showDebug: () -> Void
    @State private var search = ""
    private var filteredApplications: [InstalledApplication] {
        model.installedApplications.filter {
            search.isEmpty || $0.name.localizedStandardContains(search) || $0.url.path.localizedStandardContains(search)
        }
    }
    private var filtered: [WindowSnapshot] {
        model.windows.filter { search.isEmpty || $0.label.localizedStandardContains(search) }
    }
    private var noticeCount: Int {
        model.warnings.count + model.shortcutWarnings.count + (model.message == nil ? 0 : 1)
            + (model.configurationBlocked ? 1 : 0) + (model.catalogMessage == nil ? 0 : 1)
    }
    var body: some View {
        let _ = localization.language
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 14) {
                LayoutTemplatePreview(template: model.layoutTemplate, ratio: model.ratio, rowRatio: model.rowRatio)
                    .frame(width: 130, height: 62)
                VStack(alignment: .leading, spacing: 4) {
                    Text(model.layoutTemplate.title).font(.headline)
                    Text(L10n.tr("Left \(Int(model.ratio * 100)) % · Right \(100 - Int(model.ratio * 100)) %"))
                        .font(.caption).foregroundStyle(.secondary)
                }
                Spacer()
                Text(L10n.tr("\(model.originals.count) windows in zones")).font(.caption).foregroundStyle(.secondary)
            }
            HStack {
                Text(
                    L10n.tr("\(model.windows.count) windows found")
                        + (model.pendingTabs.isEmpty ? "" : L10n.tr(" · \(model.pendingTabs.count) waiting to restore"))
                )
                .font(.caption).foregroundStyle(.secondary).lineLimit(1)
                Spacer()
                if !model.pendingTabs.isEmpty {
                    Button(L10n.tr("Restore")) { model.restoreSavedSession() }
                        .disabled(
                            !model.discoveryStatus.canReportMatches || model.restorableCount == 0 || model.busy
                                || model.paused)
                }
            }
            if !model.trusted {
                HStack {
                    Label(L10n.tr("Accessibility access needed"), systemImage: "lock").foregroundStyle(.orange)
                    Spacer()
                    Button(L10n.tr("Grant Access")) { model.requestPermission() }
                    Button(L10n.tr("Check")) { model.recheckPermission() }
                }.font(.caption)
            }
            if noticeCount > 0 {
                HStack {
                    Label(
                        model.message ?? model.catalogMessage ?? L10n.tr("\(noticeCount) notices available"),
                        systemImage: "exclamationmark.circle"
                    )
                    .lineLimit(1).help(model.message ?? L10n.tr("See Diagnostics for all notices"))
                    Spacer()
                    Button(L10n.tr("View Details"), action: showDebug)
                }.font(.caption).foregroundStyle(.orange)
            }
            HStack(spacing: 10) {
                Picker(L10n.tr("Show"), selection: $model.settingsShowsApplications) {
                    Text(L10n.tr("All Apps")).tag(true)
                    Text(L10n.tr("Open Windows")).tag(false)
                }.pickerStyle(.segmented).frame(width: 270)
                TextField(L10n.tr("Search"), text: $search).textFieldStyle(.roundedBorder)
                if model.settingsShowsApplications { Button(L10n.tr("Add App…")) { model.addApplications() } }
                Button {
                    if model.settingsShowsApplications { model.refreshApplications() } else { model.refresh() }
                } label: {
                    Image(systemName: "arrow.clockwise")
                }
                .help(L10n.tr("Refresh List"))
                .disabled(!model.settingsShowsApplications && (model.scanning || model.demo))
            }
            if let zone = model.assignmentZone {
                HStack {
                    Text(L10n.tr("Assign to Zone \(zone.title)")).font(.caption.bold())
                    Spacer()
                    Button(L10n.tr("Show All Zones")) { model.clearAssignmentFilter() }.font(.caption)
                }
            }
            applicationList.layoutPriority(1)
        }
        .padding(14).frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .onChange(of: model.assignmentRequest) { search = "" }
        .onChange(of: model.settingsShowsApplications) {
            if !model.settingsShowsApplications && !model.hasCompletedFullDiscovery { model.refresh() }
        }
    }
    @ViewBuilder private var applicationList: some View {
        if model.settingsShowsApplications {
            List(filteredApplications) { application in
                HStack(spacing: 10) {
                    Image(nsImage: NSWorkspace.shared.icon(forFile: application.url.path)).resizable().frame(
                        width: 28, height: 28)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(application.name).lineLimit(1)
                        Text(application.url.path).font(.caption).foregroundStyle(.secondary).lineLimit(1)
                    }
                    Spacer()
                    if let rule = model.applicationAssignment(for: application) {
                        Text(model.zoneLabel(rule.zone)).font(.caption.bold())
                            .foregroundStyle(rule.zone == .a ? .orange : rule.zone == .b ? .blue : .green)
                        Button(L10n.tr("Remove")) { model.removeApplicationAssignment(rule) }
                            .disabled(model.busy || model.scanning || model.spaceTransitioning)
                    }
                    if let zone = model.assignmentZone {
                        Button(L10n.tr("Assign to \(zone.title)")) { model.assignApplication(application, to: zone) }
                            .disabled(model.busy || model.scanning || model.configurationBlocked || model.demo)
                    } else {
                        ForEach(model.activeZones) { zone in
                            Button(zone.title) { model.assignApplication(application, to: zone) }
                                .tint(zone == .a ? .orange : zone == .b ? .blue : .green)
                                .disabled(model.busy || model.scanning || model.configurationBlocked || model.demo)
                        }
                    }
                    Button(model.launchingApplications.contains(application.id) ? L10n.tr("Opening…") : L10n.tr("Open"))
                    {
                        model.launchApplication(application)
                    }.disabled(model.launchingApplications.contains(application.id))
                }.padding(.vertical, 4)
                    .contextMenu {
                        Button(L10n.tr("Show in Finder")) {
                            NSWorkspace.shared.activateFileViewerSelecting([application.url])
                        }
                    }
            }.listStyle(.inset(alternatesRowBackgrounds: true)).frame(maxHeight: .infinity)
        } else if model.demo {
            ContentUnavailableView(
                L10n.tr("Demo Mode"), systemImage: "rectangle.split.2x1",
                description: Text(L10n.tr("No external windows are changed.")))
        } else if !model.trusted {
            ContentUnavailableView(
                L10n.tr("Accessibility access needed"), systemImage: "lock",
                description: Text(L10n.tr("You can browse all apps. Accessibility access is needed to manage windows."))
            )
        } else {
            List(filtered) { window in windowRow(window) }
                .listStyle(.inset(alternatesRowBackgrounds: true))
                .overlay {
                    if filtered.isEmpty && !model.scanning {
                        ContentUnavailableView(
                            L10n.tr("No Windows Available"), systemImage: "macwindow",
                            description: Text(L10n.tr("Open another app's window, then select Refresh.")))
                    }
                }
        }
    }
    private func windowRow(_ window: WindowSnapshot) -> some View {
        HStack(spacing: 10) {
            if let icon = NSRunningApplication(processIdentifier: window.pid)?.icon {
                Image(nsImage: icon).resizable().frame(width: 28, height: 28)
            }
            VStack(alignment: .leading, spacing: 2) {
                Text(window.identity.title.isEmpty ? L10n.tr("Untitled") : window.identity.title).lineLimit(1)
                Text(window.incompatibility ?? window.appName).font(.caption).foregroundStyle(.secondary).lineLimit(2)
            }
            Spacer()
            if let zone = model.tabs.zone(of: window.id) {
                Text(model.zoneLabel(zone)).font(.caption.bold()).foregroundStyle(
                    zone == .a ? .orange : zone == .b ? .blue : .green)
                Button(L10n.tr("Release")) { model.release(window.id) }
            } else if let zone = model.assignmentZone {
                Button(L10n.tr("Add to \(zone.title)")) { model.assign(window.id, to: zone) }
                    .tint(zone == .a ? .orange : zone == .b ? .blue : .green)
            } else {
                ForEach(model.activeZones) { zone in
                    Button(zone.title) { model.assign(window.id, to: zone) }
                        .tint(zone == .a ? .orange : zone == .b ? .blue : .green)
                }
            }
        }
        .padding(.vertical, 5)
        .disabled(model.busy || (model.tabs.zone(of: window.id) == nil && (model.paused || !window.compatible)))
        .help(window.incompatibility ?? window.label)
    }
}
