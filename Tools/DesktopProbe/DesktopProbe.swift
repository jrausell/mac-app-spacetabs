import AppKit
import SpaceTabsCore

/// Disposable desktop experiment. Never reads production configuration or AX.
@main
@MainActor
enum DesktopProbe {
    static func main() {
        L10n.configure(.automatic)
        let application = NSApplication.shared
        let delegate = ProbeDelegate()
        application.delegate = delegate
        application.setActivationPolicy(.accessory)
        withExtendedLifetime(delegate) { application.run() }
    }
}

@MainActor
private final class ProbeDelegate: NSObject, NSApplicationDelegate, NSMenuDelegate {
    private struct Marker {
        let id: Int
        let displayID: String
        let panel: NSPanel
        let hiddenAnchor: NSPanel
    }

    private var markers: [Marker] = []
    private var status: NSStatusItem?
    private var transitionTask: Task<Void, Never>?
    private var revision = 0
    private var nextID = 1
    private var logURL: URL?
    private var logHandle: FileHandle?
    private var writtenBytes = 0
    private var loggingFailed = false

    func applicationDidFinishLaunching(_ notification: Notification) {
        do {
            guard let directory = Bundle.main.object(forInfoDictionaryKey: "ProbeReportDirectory") as? String else {
                throw CocoaError(.fileNoSuchFile)
            }
            let url = URL(fileURLWithPath: directory, isDirectory: true)
            try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
            let report = url.appendingPathComponent("desktop-probe-\(UUID()).jsonl")
            guard
                FileManager.default.createFile(
                    atPath: report.path, contents: nil, attributes: [.posixPermissions: 0o600])
            else { throw CocoaError(.fileWriteUnknown) }
            logURL = report
            logHandle = try FileHandle(forWritingTo: report)
        } catch {
            let alert = NSAlert(error: error)
            alert.runModal()
            NSApp.terminate(nil)
            return
        }
        status = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        status?.button?.title = "ST?"
        status?.button?.toolTip = L10n.tr("Desktop probe")
        let menu = NSMenu()
        menu.delegate = self
        status?.menu = menu
        NSWorkspace.shared.notificationCenter.addObserver(
            self, selector: #selector(spaceChanged), name: NSWorkspace.activeSpaceDidChangeNotification, object: nil)
        NotificationCenter.default.addObserver(
            self, selector: #selector(displaysChanged), name: NSApplication.didChangeScreenParametersNotification,
            object: nil)
        snapshot("started")
    }

    func menuNeedsUpdate(_ menu: NSMenu) {
        menu.removeAllItems()
        menu.addItem(withTitle: L10n.tr("Desktop probe"), action: nil, keyEquivalent: "")
        for (index, screen) in NSScreen.screens.enumerated() {
            let item = menu.addItem(
                withTitle: L10n.tr("Create marker on \(screen.localizedName)"), action: #selector(createMarker(_:)),
                keyEquivalent: "")
            item.representedObject = index
            item.target = self
            item.isEnabled = markers.count < 24
        }
        menu.addItem(.separator())
        for marker in markers {
            let connected = NSScreen.screens.contains { displayID($0) == marker.displayID }
            let state =
                !connected
                ? L10n.tr("Disconnected")
                : marker.panel.isOnActiveSpace
                    ? L10n.tr("Current desktop") : L10n.tr("Other desktop")
            menu.addItem(
                withTitle: L10n.tr("Marker \(marker.id) · \(state)"), action: nil, keyEquivalent: "")
            let item = menu.addItem(
                withTitle: L10n.tr("Hide visible marker \(marker.id)"), action: #selector(hideMarker(_:)),
                keyEquivalent: "")
            item.representedObject = marker.id
            item.target = self
            item.isEnabled = connected && marker.panel.isOnActiveSpace && marker.panel.isVisible
        }
        menu.addItem(.separator())
        add(menu, L10n.tr("Record checkpoint"), #selector(checkpoint))
        add(menu, L10n.tr("Copy probe report path"), #selector(copyReportPath))
        add(menu, L10n.tr("Quit desktop probe"), #selector(quit))
        snapshot("menu_opened")
    }

    private func add(_ menu: NSMenu, _ title: String, _ action: Selector) {
        let item = menu.addItem(withTitle: title, action: action, keyEquivalent: "")
        item.target = self
    }

    private func displayID(_ screen: NSScreen) -> String {
        guard let number = screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber,
            let uuid = CGDisplayCreateUUIDFromDisplayID(number.uint32Value)?.takeRetainedValue()
        else { return "unavailable" }
        return CFUUIDCreateString(nil, uuid) as String
    }

    private func panel(frame: NSRect, color: NSColor) -> NSPanel {
        let panel = NSPanel(
            contentRect: frame, styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        panel.collectionBehavior = [.managed, .fullScreenNone]
        panel.level = .floating
        panel.hidesOnDeactivate = false
        panel.isReleasedWhenClosed = false
        panel.isMovable = false
        panel.isOpaque = true
        panel.backgroundColor = color
        panel.ignoresMouseEvents = true
        panel.animationBehavior = .none
        return panel
    }

    @objc private func createMarker(_ sender: NSMenuItem) {
        guard let index = sender.representedObject as? Int,
            NSScreen.screens.indices.contains(index), markers.count < 24
        else { return }
        let screen = NSScreen.screens[index]
        let bounds = screen.visibleFrame
        let offset = CGFloat(markers.filter { $0.displayID == displayID(screen) }.count % 5) * 52
        let frame = NSRect(x: bounds.minX + 20, y: bounds.maxY - 64 - offset, width: 310, height: 40)
        let colors: [NSColor] = [.systemBlue, .systemOrange, .systemPurple, .systemTeal, .systemPink]
        let visible = panel(frame: frame, color: colors[(nextID - 1) % colors.count])
        let label = NSTextField(labelWithString: L10n.tr("Desktop probe · Marker \(nextID)"))
        label.frame = NSRect(x: 10, y: 9, width: 290, height: 22)
        label.textColor = .white
        label.font = .boldSystemFont(ofSize: 15)
        visible.contentView?.addSubview(label)
        // Briefly order an ordinary in-bounds anchor, then retain it ordered out.
        // Its active-Space signal is the experiment, not a trusted identity.
        let hidden = panel(frame: NSRect(x: frame.minX, y: frame.minY, width: 2, height: 2), color: .gray)
        hidden.orderFrontRegardless()
        hidden.orderOut(nil)
        visible.orderFrontRegardless()
        markers.append(Marker(id: nextID, displayID: displayID(screen), panel: visible, hiddenAnchor: hidden))
        nextID += 1
        snapshot("marker_created")
        scheduleSnapshot("marker_creation_settled")
    }

    @objc private func hideMarker(_ sender: NSMenuItem) {
        guard let id = sender.representedObject as? Int, let marker = markers.first(where: { $0.id == id }),
            marker.panel.isOnActiveSpace
        else { return }
        marker.panel.orderOut(nil)
        snapshot("marker_hidden")
        scheduleSnapshot("marker_hide_settled")
    }

    @objc private func spaceChanged() {
        snapshot("space_change_received")
        scheduleSnapshot("space_change_settled")
    }

    @objc private func displaysChanged() {
        snapshot("displays_changed")
        scheduleSnapshot("display_change_settled")
    }

    private func scheduleSnapshot(_ reason: String) {
        transitionTask?.cancel()
        revision += 1
        let expected = revision
        transitionTask = Task { [weak self] in
            do { try await Task.sleep(for: .milliseconds(800)) } catch { return }
            guard let self, revision == expected else { return }
            snapshot(reason)
            transitionTask = nil
        }
    }

    @objc private func checkpoint() { snapshot("manual_checkpoint") }

    private func windowState(_ window: NSWindow) -> [String: Any] {
        [
            "number": window.windowNumber, "onActiveSpace": window.isOnActiveSpace,
            "orderedIn": window.isVisible, "occlusionVisible": window.occlusionState.contains(.visible),
            "frame": NSStringFromRect(window.frame),
        ]
    }

    private func snapshot(_ reason: String) {
        guard !loggingFailed else { return }
        let screens = NSScreen.screens
        let record: [String: Any] = [
            "timestamp": Date.now.ISO8601Format(), "event": reason, "runPID": ProcessInfo.processInfo.processIdentifier,
            "osVersion": ProcessInfo.processInfo.operatingSystemVersionString,
            "separateSpaces": NSScreen.screensHaveSeparateSpaces,
            "frontmostPID": NSWorkspace.shared.frontmostApplication?.processIdentifier ?? -1,
            "screens": screens.map { ["id": displayID($0), "frame": NSStringFromRect($0.frame)] },
            "markers": markers.map { marker in
                [
                    "id": marker.id, "displayID": marker.displayID,
                    "displayConnected": screens.contains { displayID($0) == marker.displayID },
                    "visibleMarker": windowState(marker.panel), "hiddenAnchor": windowState(marker.hiddenAnchor),
                ] as [String: Any]
            },
        ]
        do {
            var data = try JSONSerialization.data(withJSONObject: record, options: [.sortedKeys])
            data.append(0x0A)
            guard writtenBytes + data.count <= 2 * 1024 * 1024 else {
                throw CocoaError(.fileWriteOutOfSpace)
            }
            try logHandle?.write(contentsOf: data)
            writtenBytes += data.count
        } catch {
            loggingFailed = true
            status?.button?.title = "ST?!"
            status?.button?.toolTip = error.localizedDescription
        }
    }

    @objc private func copyReportPath() {
        guard let logURL else { return }
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(logURL.path, forType: .string)
    }

    @objc private func quit() { NSApp.terminate(nil) }

    func applicationWillTerminate(_ notification: Notification) {
        transitionTask?.cancel()
        snapshot("stopped")
        try? logHandle?.synchronize()
        try? logHandle?.close()
        for marker in markers {
            marker.panel.close()
            marker.hiddenAnchor.close()
        }
        NSWorkspace.shared.notificationCenter.removeObserver(self)
        NotificationCenter.default.removeObserver(self)
    }
}
