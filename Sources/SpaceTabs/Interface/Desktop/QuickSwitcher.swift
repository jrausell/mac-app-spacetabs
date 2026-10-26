import AppKit
import SpaceTabsCore
import SwiftUI

private final class SwitcherPanel: NSPanel {
    override var canBecomeKey: Bool { true }
    override func cancelOperation(_ sender: Any?) { orderOut(nil) }
}

@MainActor final class QuickSwitcher: NSObject, NSWindowDelegate {
    private var panel: NSPanel?
    private var monitor: Any?
    func show(model: AppModel) {
        if panel?.isVisible == true {
            close()
            return
        }
        model.noteUserInteraction()
        let panel = SwitcherPanel(
            contentRect: CGRect(x: 0, y: 0, width: 580, height: 440),
            styleMask: [.titled, .nonactivatingPanel], backing: .buffered, defer: false)
        panel.title = L10n.tr("Go to a Tab or Profile")
        panel.level = .floating
        panel.hidesOnDeactivate = false
        panel.isReleasedWhenClosed = false
        panel.collectionBehavior = [.moveToActiveSpace, .fullScreenNone]
        panel.delegate = self
        panel.contentView = NSHostingView(
            rootView: QuickSwitcherView(model: model, dismiss: { [weak self] in self?.close() }))
        if let screen = model.screen {
            panel.setFrameOrigin(CGPoint(x: screen.visibleFrame.midX - 290, y: screen.visibleFrame.midY - 170))
        } else {
            panel.center()
        }
        self.panel = panel
        panel.makeKeyAndOrderFront(nil)
        monitor = NSEvent.addGlobalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown]) { [weak self] _ in
            MainActor.assumeIsolated { self?.close() }
        }
    }
    func windowDidResignKey(_ notification: Notification) { close() }
    func close() {
        if let monitor { NSEvent.removeMonitor(monitor) }
        monitor = nil
        panel?.orderOut(nil)
    }
}

private struct SwitcherItem: Identifiable {
    let id: String
    let title: String
    let detail: String
    let windowID: UUID?
    let zone: Zone?
    let profileID: UUID?
}

private struct QuickSwitcherView: View {
    private let localization = AppLocalization.shared
    let model: AppModel
    let dismiss: () -> Void
    @State private var search = ""
    @State private var index = 0
    @FocusState private var searching: Bool
    private var items: [SwitcherItem] {
        let windows = model.activeZones.flatMap { zone in
            model.tabs.windows[zone, default: []].map { id in
                SwitcherItem(
                    id: id.uuidString, title: model.titles[id] ?? L10n.tr("Window"), detail: model.zoneLabel(zone),
                    windowID: id,
                    zone: zone, profileID: nil)
            }
        }
        let profiles = model.preferences.profiles.map {
            SwitcherItem(
                id: "profile:\($0.id)", title: $0.name, detail: L10n.tr("Profile · \($0.layout.template.title)"),
                windowID: nil,
                zone: nil, profileID: $0.id)
        }
        return (windows + profiles).filter {
            search.isEmpty || "\($0.title) \($0.detail)".localizedStandardContains(search)
        }
    }
    var body: some View {
        let _ = localization.language
        VStack(spacing: 0) {
            HStack {
                Image(systemName: "magnifyingglass").foregroundStyle(.secondary)
                TextField(L10n.tr("Search tabs and profiles…"), text: $search).textFieldStyle(.plain).font(.title3)
                    .focused($searching).onSubmit { choose() }
            }.padding(18)
            Divider()
            ScrollViewReader { proxy in
                ScrollView {
                    LazyVStack(spacing: 3) {
                        ForEach(Array(items.enumerated()), id: \.element.id) { position, item in
                            Button {
                                index = position
                                choose()
                            } label: {
                                HStack(spacing: 12) {
                                    Image(systemName: item.profileID == nil ? "macwindow" : "rectangle.stack")
                                    VStack(alignment: .leading, spacing: 3) {
                                        Text(item.title).lineLimit(1)
                                        Text(item.detail).font(.caption).foregroundStyle(.secondary)
                                    }
                                    Spacer()
                                    if position == index { Image(systemName: "return").foregroundStyle(.secondary) }
                                }.padding(11).frame(maxWidth: .infinity, alignment: .leading)
                                    .background(
                                        position == index ? Color.accentColor.opacity(0.17) : .clear,
                                        in: RoundedRectangle(cornerRadius: 8)
                                    )
                                    .contentShape(Rectangle())
                            }.buttonStyle(.plain).id(position)
                        }
                        if items.isEmpty { Text(L10n.tr("No matches")).foregroundStyle(.secondary).padding(30) }
                    }.padding(8)
                }.onChange(of: index) { proxy.scrollTo(index) }
            }
            Divider()
            Text(L10n.tr("↑ ↓ Select · ↩ Open · Esc Close")).font(.caption).foregroundStyle(.secondary).padding(10)
        }
        .onAppear {
            searching = true
            if let selected = model.tabs.selected[model.activeZone],
                let position = items.firstIndex(where: { $0.windowID == selected })
            {
                index = position
            }
        }
        .onChange(of: search) { index = 0 }
        .onChange(of: items.map(\.id)) { index = min(index, max(0, items.count - 1)) }
        .onKeyPress(.downArrow) {
            index = min(index + 1, max(0, items.count - 1))
            return .handled
        }
        .onKeyPress(.upArrow) {
            index = max(0, index - 1)
            return .handled
        }
        .onExitCommand { dismiss() }
    }
    private func choose() {
        guard items.indices.contains(index) else { return }
        let item = items[index]
        dismiss()
        if let id = item.windowID, let zone = item.zone { model.select(id, zone: zone) }
        if let id = item.profileID { model.applyProfile(id) }
    }
}
