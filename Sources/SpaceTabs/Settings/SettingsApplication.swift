import AppKit
import SpaceTabsCore
import SwiftUI

@MainActor enum SettingsApplication {
    static func run() {
        let app = NSApplication.shared
        let delegate = SettingsAppDelegate()
        app.delegate = delegate
        app.setActivationPolicy(.regular)
        withExtendedLifetime(delegate) { app.run() }
    }
}

@MainActor private final class SettingsAppDelegate: NSObject, NSApplicationDelegate {
    private let model = AppModel()
    private let responsiveness = ResponsivenessMonitor()
    private var window: NSWindow?
    private var languageObserver: NSObjectProtocol?
    private var localeObserver: NSObjectProtocol?
    private var connectionTask: Task<Void, Never>?
    func applicationDidFinishLaunching(_ notification: Notification) {
        responsiveness.start()
        let arguments = CommandLine.arguments
        guard let index = arguments.firstIndex(of: "--settings-socket"), arguments.indices.contains(index + 1) else {
            let alert = NSAlert()
            alert.messageText = L10n.tr("Open Settings from SpaceTabs")
            alert.informativeText = L10n.tr(
                "Use Windows and Settings in the SpaceTabs menu, or the + button in a zone.")
            alert.runModal()
            NSApp.terminate(nil)
            return
        }
        let remote = RemoteSettingsModel(model: model)
        model.remoteSettings = remote
        model.showTabBars = { [weak model] in model?.remoteSettings?.send(.showTabs) }
        model.restartShortcuts = { [weak model] in model?.remoteSettings?.send(.restartShortcuts) }
        model.openSettings = { [weak self] in
            NSApp.activate()
            self?.showWindow()
        }
        languageObserver = NotificationCenter.default.addObserver(
            forName: .spaceTabsLanguageDidChange, object: nil, queue: .main
        ) { [weak self] _ in
            Task { @MainActor in
                guard let self else { return }
                self.installMenu()
                self.window?.title = L10n.tr("SpaceTabs Settings")
            }
        }
        localeObserver = NotificationCenter.default.addObserver(
            forName: NSLocale.currentLocaleDidChangeNotification, object: nil, queue: .main
        ) { [weak self] _ in
            Task { @MainActor in
                guard let self else { return }
                L10n.configure(self.model.preferences.language)
            }
        }
        installMenu()
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 1100, height: 760),
            styleMask: [.titled, .closable, .miniaturizable, .resizable], backing: .buffered, defer: false)
        window.title = L10n.tr("SpaceTabs Settings")
        window.contentMinSize = NSSize(width: 980, height: 620)
        window.collectionBehavior = [.moveToActiveSpace]
        window.isReleasedWhenClosed = false
        window.contentView = NSHostingView(rootView: ControlView(model: model))
        window.center()
        self.window = window
        showWindow()
        let path = arguments[index + 1]
        connectionTask = Task {
            do { try await remote.connect(path: path) } catch is CancellationError {} catch {
                DiagnosticLog.shared.failure(error, operation: "settings.connect")
                let alert = NSAlert()
                alert.messageText = L10n.tr("Could not connect to SpaceTabs")
                alert.informativeText = error.localizedDescription
                alert.runModal()
                NSApp.terminate(nil)
            }
        }
    }
    func applicationWillTerminate(_ notification: Notification) {
        responsiveness.stop()
        DiagnosticLog.shared.record("session.end")
        DiagnosticLog.shared.flush()
        connectionTask?.cancel()
        if let languageObserver { NotificationCenter.default.removeObserver(languageObserver) }
        if let localeObserver { NotificationCenter.default.removeObserver(localeObserver) }
    }
    func applicationDidBecomeActive(_ notification: Notification) {
        model.refreshLoginStatus()
        showWindow()
    }
    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        showWindow()
        return false
    }
    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { false }
    @objc private func showWindow() {
        if window?.isMiniaturized == true { window?.deminiaturize(nil) }
        window?.makeKeyAndOrderFront(nil)
    }
    private func installMenu() {
        let menu = NSMenu()
        let application = NSMenu(title: L10n.tr("SpaceTabs Settings"))
        let item = NSMenuItem()
        item.submenu = application
        menu.addItem(item)
        let settings = application.addItem(
            withTitle: L10n.tr("Show Settings"), action: #selector(showWindow), keyEquivalent: ",")
        settings.target = self
        application.addItem(.separator())
        application.addItem(
            withTitle: L10n.tr("Hide Settings"), action: #selector(NSApplication.hide(_:)), keyEquivalent: "h")
        application.addItem(
            withTitle: L10n.tr("Close Settings"), action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        let edit = NSMenu(title: L10n.tr("Edit"))
        let editItem = NSMenuItem(title: L10n.tr("Edit"), action: nil, keyEquivalent: "")
        editItem.submenu = edit
        menu.addItem(editItem)
        for (title, action, key) in [
            (L10n.tr("Undo"), "undo:", "z"), (L10n.tr("Cut"), "cut:", "x"), (L10n.tr("Copy"), "copy:", "c"),
            (L10n.tr("Paste"), "paste:", "v"), (L10n.tr("Select All"), "selectAll:", "a"),
        ] {
            edit.addItem(withTitle: title, action: Selector(action), keyEquivalent: key)
        }
        let windows = NSMenu(title: L10n.tr("Window"))
        let windowsItem = NSMenuItem(title: L10n.tr("Window"), action: nil, keyEquivalent: "")
        windowsItem.submenu = windows
        menu.addItem(windowsItem)
        windows.addItem(
            withTitle: L10n.tr("Minimize"), action: #selector(NSWindow.performMiniaturize(_:)), keyEquivalent: "m")
        windows.addItem(withTitle: L10n.tr("Close"), action: #selector(NSWindow.performClose(_:)), keyEquivalent: "w")
        NSApp.mainMenu = menu
        NSApp.windowsMenu = windows
    }
}
