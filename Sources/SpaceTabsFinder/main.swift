import AppKit
import FinderSync
import OSLog
import SpaceTabsCore

/// Finder calls the principal class through NSExtensionMain. This executable's
/// entry point is set by the linker, not a second NSApplication event loop.
@MainActor @objc(SpaceTabsFinder) final class SpaceTabsFinder: FIFinderSync, @unchecked Sendable {
    private nonisolated static let logger = Logger(
        subsystem: SpaceTabsIdentity.finderBundleID, category: "desktop-menu")

    private var requests: [Int: DesktopMenuRequest] = [:]
    private var nextTag = 0

    override init() {
        super.init()
        if let desktop = DesktopMenuStorage.desktop {
            let directories: Set<URL> = [desktop, desktop.resolvingSymlinksInPath()]
            FIFinderSyncController.default().directoryURLs = directories
            let containerHome = desktop.pathComponents.contains("Containers")
            Self.logger.notice(
                "Desktop registration ready; aliases=\(directories.count), containerHome=\(containerHome)")
        } else {
            Self.logger.error("Desktop registration failed: user home unavailable")
        }
    }

    nonisolated override func beginObservingDirectory(at url: URL) {
        MainThreadCallback.call {
            let matches = DesktopMenuStorage.desktop.map { DesktopMenuScope.matches(url, desktop: $0) } ?? false
            Self.logger.notice("Finder began observing a directory; desktop=\(matches)")
        }
    }

    // Finder may invoke extension callbacks on an XPC worker. Capture Finder's
    // request-local URLs there, then construct AppKit objects on the main queue.
    private struct MenuResult: @unchecked Sendable { let menu: NSMenu? }
    private struct MenuSender: @unchecked Sendable { let item: NSMenuItem }
    nonisolated override func menu(for menuKind: FIMenuKind) -> NSMenu? {
        Self.logger.notice("Finder entered menu callback; kind=\(menuKind.rawValue)")
        let controller = FIFinderSyncController.default()
        let target = controller.targetedURL()
        let selectedCount = controller.selectedItemURLs()?.count ?? 0
        return MainThreadCallback.call {
            MenuResult(menu: self.makeMenu(for: menuKind, target: target, selectedCount: selectedCount))
        }.menu
    }

    @MainActor private func makeMenu(for kind: FIMenuKind, target: URL?, selectedCount: Int) -> NSMenu? {
        let matches = DesktopMenuStorage.desktop.map { DesktopMenuScope.matches(target, desktop: $0) } ?? false
        Self.logger.notice(
            "Menu requested; kind=\(kind.rawValue), targetPresent=\(target != nil), desktop=\(matches), selected=\(selectedCount)"
        )
        guard kind == .contextualMenuForContainer, matches else { return nil }
        requests.removeAll()
        let menu = NSMenu()
        let root = NSMenuItem(title: "SpaceTabs", action: nil, keyEquivalent: "")
        root.image = NSImage(systemSymbolName: "rectangle.split.2x1", accessibilityDescription: "SpaceTabs")
        let actions = NSMenu()
        actions.autoenablesItems = false
        root.submenu = actions
        menu.addItem(root)
        let snapshot = DesktopMenuStorage.url.flatMap { try? DesktopMenuStorage.load(at: $0) }
        L10n.configure(snapshot?.language ?? .automatic)
        if let snapshot, let manager = NSRunningApplication(processIdentifier: snapshot.managerPID),
            !manager.isTerminated, manager.bundleIdentifier == SpaceTabsIdentity.appBundleID,
            manager.launchDate == snapshot.launchDate, snapshot.ready,
            let screen = NSScreen.screens.first(where: { $0.frame.contains(NSEvent.mouseLocation) })
        {
            let displayID = stableDisplayID(screen)
            let open = NSMenuItem(title: L10n.tr("Open here…"), action: nil, keyEquivalent: "")
            let choices = NSMenu()
            choices.autoenablesItems = false
            open.submenu = choices
            actions.addItem(open)
            add(choices, L10n.tr("New workspace"), action: .newWorkspace, snapshot: snapshot, displayID: displayID)
            if !snapshot.workspaces.isEmpty { choices.addItem(.separator()) }
            for workspace in snapshot.workspaces {
                let item = add(
                    choices, workspace.name, action: .openWorkspace(workspace.id), snapshot: snapshot,
                    displayID: displayID)
                item.isEnabled = !workspace.isOpen || (workspace.isHere && workspace.displayID == displayID)
                if workspace.isHere && workspace.displayID == displayID { item.state = .on }
                if workspace.isOpen && !workspace.isHere { item.title += " · " + L10n.tr("Other desktop") }
            }
            let bound = Set(snapshot.workspaces.compactMap(\.profileID))
            let profiles = snapshot.profiles.filter { !bound.contains($0.id) }
            if !profiles.isEmpty { choices.addItem(.separator()) }
            for profile in profiles {
                add(choices, profile.name, action: .openProfile(profile.id), snapshot: snapshot, displayID: displayID)
            }
            let current = snapshot.workspace(on: displayID)
            add(actions, L10n.tr("Show"), action: .show, snapshot: snapshot, displayID: displayID).isEnabled =
                current?.canRestore == true
            add(actions, L10n.tr("Restore"), action: .restore, snapshot: snapshot, displayID: displayID).isEnabled =
                current?.canRestore == true
            add(actions, L10n.tr("Show Tabs"), action: .showTabs, snapshot: snapshot, displayID: displayID).isEnabled =
                current?.canRestore == true
            actions.addItem(.separator())
        }
        let settings = actions.addItem(
            withTitle: L10n.tr("Windows and Settings…"), action: #selector(openSettings), keyEquivalent: "")
        settings.target = self
        Self.logger.notice("Desktop submenu returned; actions=\(actions.items.count)")
        return menu
    }

    @MainActor @discardableResult private func add(
        _ menu: NSMenu, _ title: String, action: DesktopMenuAction,
        snapshot: DesktopMenuSnapshot, displayID: String
    ) -> NSMenuItem {
        let item = menu.addItem(withTitle: title, action: #selector(performAction(_:)), keyEquivalent: "")
        item.target = self
        guard nextTag < Int.max else {
            item.isEnabled = false
            return item
        }
        nextTag += 1
        item.tag = nextTag
        // Only standard NSMenuItem tags cross Finder's menu transport. Keep
        // Swift request values in this process, bounded to the current menu.
        requests[item.tag] = DesktopMenuRequest(
            token: snapshot.token, context: snapshot.context, displayID: displayID, action: action)
        return item
    }
    @objc nonisolated private func performAction(_ sender: NSMenuItem) {
        let transferred = MenuSender(item: sender)
        MainThreadCallback.call {
            guard var request = self.requests.removeValue(forKey: transferred.item.tag) else {
                Self.logger.notice("Desktop menu action ignored: stale or unknown tag")
                return
            }
            request.nonce = UUID()
            request.created = .now
            Self.logger.notice("Desktop menu action selected")
            if let url = request.url() { self.deliver(url) }
        }
    }
    @objc nonisolated private func openSettings() {
        MainThreadCallback.call {
            if let url = URL(string: "\(SpaceTabsIdentity.desktopMenuScheme)://settings") { self.deliver(url) }
        }
    }
    @MainActor private func deliver(_ url: URL) {
        // Address the containing signed app explicitly, not another registered
        // handler for the scheme, and keep its own windows from activating first.
        let app = Bundle.main.bundleURL.deletingLastPathComponent().deletingLastPathComponent()
            .deletingLastPathComponent()
        let configuration = NSWorkspace.OpenConfiguration()
        configuration.activates = false
        NSWorkspace.shared.open([url], withApplicationAt: app, configuration: configuration) { _, error in
            if let error {
                Self.logger.error("Desktop menu delivery failed; code=\((error as NSError).code)")
            }
        }
    }
    @MainActor private func stableDisplayID(_ screen: NSScreen) -> String {
        guard let number = screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber,
            let uuid = CGDisplayCreateUUIDFromDisplayID(number.uint32Value)?.takeRetainedValue()
        else { return "" }
        return CFUUIDCreateString(nil, uuid) as String
    }
}
