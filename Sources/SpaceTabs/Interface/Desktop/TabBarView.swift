import AppKit
import SpaceTabsCore
import SwiftUI

struct TabBarView: View {
    private let localization = AppLocalization.shared
    @Bindable var model: AppModel
    let zone: Zone
    @State private var dropTargeted = false
    @Environment(\.colorScheme) private var systemScheme
    private var palette: TabPalette { model.tabAppearance.palette(systemIsDark: systemScheme == .dark) }
    private var accent: Color {
        Color(tabColor: model.tabAppearance.accent(for: zone, systemIsDark: systemScheme == .dark))
    }

    private func icon(for id: UUID) -> NSImage? {
        guard let snapshot = model.windows.first(where: { $0.id == id }) else { return nil }
        return NSRunningApplication(processIdentifier: snapshot.pid)?.icon
    }

    var body: some View {
        let _ = localization.language
        HStack(spacing: 5) {
            Text(model.zoneLabel(zone)).lineLimit(1).help(model.zoneLabel(zone)).font(
                .system(size: 11, weight: .heavy, design: .rounded)
            )
            .foregroundStyle(accent).frame(
                minWidth: 20, maxWidth: model.preferences.zoneNames[zone, default: ""].isEmpty ? 20 : 110)
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 4) {
                    if model.isLoadingTabs {
                        HStack(spacing: 6) {
                            ProgressView().controlSize(.small)
                            Text(L10n.tr("Loading tabs…")).font(.system(size: 11))
                        }.padding(.horizontal, 8).accessibilityElement(children: .combine)
                    }
                    ForEach(model.tabs.windows[zone, default: []], id: \.self) { id in
                        WindowTabButton(
                            windowID: id, title: model.titles[id] ?? L10n.tr("Window"), icon: icon(for: id),
                            foreground: NSColor(Color(tabColor: palette.foreground)),
                            dragVisibility: model.tabDragVisibility
                        ) { clickCount in
                            model.select(id, zone: zone, fillZone: clickCount == 2)
                        }
                        .padding(.vertical, 1)
                        .background(
                            model.tabs.selected[zone] == id
                                ? accent.opacity(0.25) : Color(tabColor: palette.foreground).opacity(0.09),
                            in: RoundedRectangle(cornerRadius: 7)
                        )
                        .disabled(model.paused)
                        .help(
                            L10n.tr(
                                "\(model.titles[id] ?? L10n.tr("Window")) · Double-click to fill its zone · Drag to move"
                            )
                        )
                        .onDrop(of: [spaceTabsPasteboard.rawValue], isTargeted: nil) { providers in
                            TabDropReceiver.accept(providers, model: model, zone: zone, before: id)
                        }
                        .contextMenu {
                            ForEach(model.activeZones.filter { $0 != zone }) { destination in
                                Button(L10n.tr("Move to Zone \(destination.title)")) { model.move(id, to: destination) }
                                    .disabled(model.busy || model.scanning)
                            }
                            Divider()
                            Button(L10n.tr("Release Window")) { model.release(id) }.disabled(
                                model.busy || model.scanning)
                        }
                    }
                    ForEach(model.isLoadingTabs ? [] : model.pendingApplicationAssignments(in: zone)) { rule in
                        Button {
                            model.launchApplication(
                                InstalledApplication(url: rule.url, name: rule.name, bundleID: rule.bundleID))
                        } label: {
                            HStack(spacing: 5) {
                                Image(nsImage: NSWorkspace.shared.icon(forFile: rule.url.path)).resizable().frame(
                                    width: 14, height: 14)
                                Text(L10n.tr("\(rule.name) · no window")).font(.system(size: 11)).lineLimit(1)
                            }.padding(.horizontal, 10).padding(.vertical, 7)
                                .background(accent.opacity(0.08), in: RoundedRectangle(cornerRadius: 7))
                        }.buttonStyle(.plain).help(L10n.tr("Open \(rule.name) in \(zone.title)"))
                            .disabled(model.launchingApplications.contains(rule.id) || model.busy || model.scanning)
                            .contextMenu {
                                ForEach(model.activeZones.filter { $0 != zone }) { destination in
                                    Button(L10n.tr("Move Assignment to \(destination.title)")) {
                                        model.assignApplication(
                                            InstalledApplication(
                                                url: rule.url, name: rule.name, bundleID: rule.bundleID),
                                            to: destination)
                                    }
                                }
                                Button(L10n.tr("Remove Assignment")) { model.removeApplicationAssignment(rule) }
                            }
                    }
                    if model.tabs.windows[zone, default: []].isEmpty
                        && model.pendingApplicationAssignments(in: zone).isEmpty
                        && !model.isLoadingTabs
                    {
                        Text(
                            model.pendingTabs.contains(where: { $0.zone == zone })
                                ? L10n.tr("Saved windows unavailable") : L10n.tr("Add a window")
                        ).font(.system(size: 11)).foregroundStyle(.secondary)
                    }
                }
            }
            Button {
                model.openAssignment(for: zone)
            } label: {
                Image(systemName: "plus").frame(width: 22, height: 26)
            }
            .buttonStyle(.plain).help(L10n.tr("Open Settings to add windows to zone \(zone.title)"))
        }
        .padding(.horizontal, 8)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background {
            RoundedRectangle(cornerRadius: 10)
                .fill(Color(tabColor: palette.background).opacity(model.tabAppearance.backgroundOpacity))
        }
        .foregroundStyle(Color(tabColor: palette.foreground))
        .environment(\.colorScheme, palette.isDark ? .dark : .light)
        .overlay(
            RoundedRectangle(cornerRadius: 10).strokeBorder(
                accent.opacity(dropTargeted ? 1 : 0.75), lineWidth: dropTargeted ? 3 : 1.5)
        )
        .shadow(color: .black.opacity(0.22), radius: 5, y: 2)
        .onDrop(of: [spaceTabsPasteboard.rawValue], isTargeted: $dropTargeted) { providers in
            TabDropReceiver.accept(providers, model: model, zone: zone)
        }
        .disabled(model.terminating)
    }
}

struct ColumnResizeGuide: View {
    private let localization = AppLocalization.shared
    @Bindable var model: AppModel
    @Environment(\.colorScheme) private var systemScheme
    var body: some View {
        let _ = localization.language
        Color(tabColor: model.tabAppearance.accent(for: .a, systemIsDark: systemScheme == .dark))
            .opacity(0.9)
    }
}

struct DemoZoneView: View {
    private let localization = AppLocalization.shared
    @Bindable var model: AppModel
    let zone: Zone
    var body: some View {
        let _ = localization.language
        VStack(spacing: 16) {
            Image(systemName: "rectangle.split.2x1").font(.system(size: 40)).foregroundStyle(
                zone == .a ? .orange : zone == .b ? .blue : .green)
            Text(model.tabs.selected[zone].flatMap { model.titles[$0] } ?? L10n.tr("Empty Zone")).font(.title2.bold())
            Text(L10n.tr("Demo · A real window will be placed here")).foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 12))
    }
}
