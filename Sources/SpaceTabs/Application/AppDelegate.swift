import AppKit
import SpaceTabsCore
import SwiftUI

private final class SavedProfilesMenu: NSMenu {}

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate, NSMenuDelegate {
    private var item: NSStatusItem?
    private let model = AppModel()
    private let responsiveness = ResponsivenessMonitor()
    private let panels = PanelController()
    private let windowDrag = WindowDragController()
    private let rightDrag = RightButtonDragController()
    private let quickSwitcher = QuickSwitcher()
    private lazy var settingsHost = SettingsHost(model: model)
    private var environmentTask: Task<Void, Never>?
    private var axObserver: NSObjectProtocol?
    private let shortcuts = ShortcutManager()
    private var spaceObserver: NSObjectProtocol?
    private var screenObserver: NSObjectProtocol?
    private var workspaceObservers: [NSObjectProtocol] = []
    private var pauseItem: NSMenuItem?
    private var releaseItem: NSMenuItem?
    private var terminationPending = false
    private var activationPolicy = WorkspaceActivationPolicy()
    private var screenTopology: [String: CGRect] = [:]
    private var localizationObservers: [NSObjectProtocol] = []
    private var activationTask: Task<Void, Never>?

    func applicationDidFinishLaunching(_ notification: Notification) {
        responsiveness.start()
        if CommandLine.arguments.contains("--smoke-test") {
            print("SpaceTabs: AppKit started; displays=\(NSScreen.screens.count)")
            DispatchQueue.main.asyncAfter(deadline: .now() + 1) { NSApp.terminate(nil) }
            return
        }
        model.loadConfiguration()
        model.loadUserPreferences()
        model.refreshLoginStatus()
        model.pendingAutomaticProfile = model.linkedProfile?.id
        screenTopology = currentScreenTopology()
        panels.start()
        windowDrag.start(model: model)
        rightDrag.start(model: model)
        model.catalogMonitor.changed = { [weak self] in self?.model.refreshApplications() }
        model.tabDragVisibility = { [weak self] in self?.panels.setTabDragging($0) }
        model.showTabBars = { [weak self] in self?.panels.reveal() }
        item = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        item?.button?.image = NSImage(systemSymbolName: "rectangle.split.2x1", accessibilityDescription: "SpaceTabs")
        item?.button?.toolTip = "SpaceTabs"
        installStatusMenu()
        installMainMenu()
        observeLanguage()
        shortcuts.handler = { [weak self] action in self?.model.handleShortcut(action) }
        model.restartShortcuts = { [weak self] in self?.registerShortcuts() }
        registerShortcuts()
        model.showQuickSwitcher = { [weak self] in
            guard let self else { return }
            quickSwitcher.show(model: model)
        }
        model.openSettings = { [weak self] in self?.showSettings() }
        model.layoutChanged = { [weak self] in
            guard let self else { return }
            windowDrag.update()
            rightDrag.update()
            guard !model.managementSuspended, !model.terminating, let screen = model.screen else {
                panels.hide()
                return
            }
            panels.update(model: model, screen: screen)
        }
        axObserver = NotificationCenter.default.addObserver(forName: .spaceTabsAXChanged, object: nil, queue: .main) {
            [weak self] event in
            guard let pid = event.userInfo?["pid"] as? Int32, let name = event.userInfo?["notification"] as? String
            else { return }
            Task { @MainActor in self?.model.accessibilityChanged(pid: pid, notification: name) }
        }
        for name in [
            NSWorkspace.didLaunchApplicationNotification, NSWorkspace.didTerminateApplicationNotification,
            NSWorkspace.didActivateApplicationNotification, NSWorkspace.didUnhideApplicationNotification,
        ] {
            let token = NSWorkspace.shared.notificationCenter.addObserver(forName: name, object: nil, queue: .main) {
                [weak self] event in
                guard let application = event.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication
                else { return }
                let pid = application.processIdentifier
                let activated = event.name == NSWorkspace.didActivateApplicationNotification
                Task { @MainActor in
                    guard let self else { return }
                    if activated {
                        let ownApplication = pid == ProcessInfo.processInfo.processIdentifier
                        let present = self.activationPolicy.applicationActivated(isSpaceTabs: ownApplication)
                        if ownApplication {
                            self.model.workspaceActivationEvent = L10n.tr("NSWorkspace; restore=\(present)")
                        }
                        if !ownApplication {
                            self.activationTask?.cancel()
                            self.model.cancelWorkspacePresentation(activatedPID: pid)
                        } else if present {
                            self.requestWorkspacePresentation(source: "NSWorkspace")
                        }
                    }
                    self.model.applicationChanged(pid: pid, activated: activated)
                }
            }
            workspaceObservers.append(token)
        }
        for name in [NSWorkspace.didWakeNotification, NSWorkspace.sessionDidBecomeActiveNotification] {
            let token = NSWorkspace.shared.notificationCenter.addObserver(forName: name, object: nil, queue: .main) {
                [weak self] _ in
                Task { @MainActor in
                    guard let self, !self.model.terminating else { return }
                    self.registerShortcuts()
                }
            }
            workspaceObservers.append(token)
        }
        spaceObserver = NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.activeSpaceDidChangeNotification, object: nil, queue: .main
        ) { [weak self] _ in
            Task { @MainActor in self?.model.activeSpaceChanged() }
        }
        screenObserver = NotificationCenter.default.addObserver(
            forName: NSApplication.didChangeScreenParametersNotification, object: nil, queue: .main
        ) { [weak self] _ in
            Task { @MainActor in
                guard let self else { return }
                let topology = self.currentScreenTopology()
                guard topology != self.screenTopology else { return }
                self.screenTopology = topology
                self.model.physicalDisplaysChanged()
            }
        }
        environmentTask = Task { [weak self] in
            while !Task.isCancelled {
                if let self {
                    self.responsiveness.update(self.model.diagnosticContext)
                    self.model.checkEnvironment()
                }
                do { try await Task.sleep(for: .seconds(5)) } catch { break }
            }
        }
        model.layoutChanged()
        if CommandLine.arguments.contains("--demo") {
            model.startDemo()
            showSettings()
        } else {
            model.startInitialDiscovery()
            model.applyAutomaticProfileIfReady()
            // Existing sessions restore before any unrelated app is inspected.
            // Settings open from the menu and + buttons in their own app.
            if !model.trusted
                || (!model.loginEnabled && model.pendingTabs.isEmpty && model.applicationAssignments.isEmpty)
            {
                showSettings()
            }
        }
        activationPolicy.ready = true
    }

    private func installStatusMenu() {
        let menu = NSMenu()
        menu.delegate = self
        menu.autoenablesItems = false
        let settings = menu.addItem(
            withTitle: L10n.tr("Windows and Settings…"), action: #selector(showSettings), keyEquivalent: ",")
        settings.target = self
        let showTabs = menu.addItem(
            withTitle: L10n.tr("Show Tabs · ⌃⌥T"), action: #selector(revealTabs), keyEquivalent: "")
        showTabs.target = self
        menu.addItem(makeProfilesMenu())
        pauseItem = menu.addItem(
            withTitle: L10n.tr("Pause and Restore Windows"), action: #selector(togglePause), keyEquivalent: "")
        pauseItem?.target = self
        let reapply = menu.addItem(
            withTitle: L10n.tr("Reapply Layout"), action: #selector(reapplyLayout), keyEquivalent: "")
        reapply.target = self
        releaseItem = menu.addItem(
            withTitle: L10n.tr("Release All Windows"), action: #selector(releaseAll), keyEquivalent: "")
        releaseItem?.target = self
        menu.addItem(.separator())
        let quit = menu.addItem(withTitle: L10n.tr("Quit SpaceTabs"), action: #selector(quitApp), keyEquivalent: "q")
        quit.target = self
        item?.menu = menu
    }

    private func observeLanguage() {
        localizationObservers.append(
            NotificationCenter.default.addObserver(
                forName: .spaceTabsLanguageDidChange, object: nil, queue: .main
            ) { [weak self] _ in
                Task { @MainActor in
                    guard let self else { return }
                    self.installMainMenu()
                    self.installStatusMenu()
                    self.model.layoutChanged()
                }
            })
        localizationObservers.append(
            NotificationCenter.default.addObserver(
                forName: NSLocale.currentLocaleDidChangeNotification, object: nil, queue: .main
            ) { [weak self] _ in
                Task { @MainActor in
                    guard let self else { return }
                    L10n.configure(self.model.preferences.language)
                }
            })
    }

    // A normal application owns a menu bar and Dock entry even after its
    // settings window closes. Avoid accessory/regular activation transitions.
    func installMainMenu() {
        let main = NSMenu()
        let application = NSMenu(title: "SpaceTabs")
        let appItem = NSMenuItem(title: "SpaceTabs", action: nil, keyEquivalent: "")
        appItem.submenu = application
        main.addItem(appItem)
        let settings = application.addItem(
            withTitle: L10n.tr("Windows and Settings…"), action: #selector(showSettings), keyEquivalent: ",")
        settings.target = self
        application.addItem(makeProfilesMenu())
        application.addItem(.separator())
        application.addItem(
            withTitle: L10n.tr("Hide SpaceTabs"), action: #selector(NSApplication.hide(_:)), keyEquivalent: "h")
        let hideOthers = application.addItem(
            withTitle: L10n.tr("Hide Others"), action: #selector(NSApplication.hideOtherApplications(_:)),
            keyEquivalent: "h")
        hideOthers.keyEquivalentModifierMask = [.command, .option]
        application.addItem(
            withTitle: L10n.tr("Show All"), action: #selector(NSApplication.unhideAllApplications(_:)),
            keyEquivalent: "")
        application.addItem(.separator())
        let quit = application.addItem(
            withTitle: L10n.tr("Quit SpaceTabs"), action: #selector(quitApp), keyEquivalent: "q")
        quit.target = self

        let edit = NSMenu(title: L10n.tr("Edit"))
        let editItem = NSMenuItem(title: L10n.tr("Edit"), action: nil, keyEquivalent: "")
        editItem.submenu = edit
        main.addItem(editItem)
        for (title, action, key) in [
            (L10n.tr("Undo"), "undo:", "z"), (L10n.tr("Cut"), "cut:", "x"),
            (L10n.tr("Copy"), "copy:", "c"), (L10n.tr("Paste"), "paste:", "v"),
            (L10n.tr("Select All"), "selectAll:", "a"),
        ] {
            edit.addItem(withTitle: title, action: Selector(action), keyEquivalent: key)
        }
        let windows = NSMenu(title: L10n.tr("Window"))
        let windowItem = NSMenuItem(title: L10n.tr("Window"), action: nil, keyEquivalent: "")
        windowItem.submenu = windows
        main.addItem(windowItem)
        windows.addItem(
            withTitle: L10n.tr("Minimize"), action: #selector(NSWindow.performMiniaturize(_:)), keyEquivalent: "m")
        windows.addItem(withTitle: L10n.tr("Close"), action: #selector(NSWindow.performClose(_:)), keyEquivalent: "w")
        NSApp.mainMenu = main
        NSApp.windowsMenu = windows
    }

    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        let present = activationPolicy.reopenRequested()
        model.workspaceActivationEvent = L10n.tr("Dock / reopen; restore=\(present)")
        if present { requestWorkspacePresentation(source: L10n.tr("Dock / reopen")) }
        // Reopening represents the workspace, never an implicit Settings request.
        return false
    }

    private func currentScreenTopology() -> [String: CGRect] {
        Dictionary(uniqueKeysWithValues: NSScreen.screens.map { (AppModel.screenID($0), $0.frame) })
    }

    private func registerShortcuts() {
        model.shortcutWarnings = shortcuts.start(bindings: model.preferences.shortcuts)
        model.registeredShortcuts = Set(shortcuts.registeredActions.map(\.rawValue))
    }

    @objc private func revealTabs() { panels.reveal() }

    private func makeProfilesMenu() -> NSMenuItem {
        let menu = SavedProfilesMenu(title: L10n.tr("Profiles"))
        menu.delegate = self
        menu.autoenablesItems = false
        menu.addItem(
            withTitle: L10n.tr("No saved profiles. Save one in Settings → Profiles."), action: nil, keyEquivalent: ""
        ).isEnabled = false
        let item = NSMenuItem(title: L10n.tr("Profiles"), action: nil, keyEquivalent: "")
        item.submenu = menu
        return item
    }

    @objc private func applySavedProfile(_ sender: NSMenuItem) {
        guard let value = sender.representedObject as? String, let id = UUID(uuidString: value) else { return }
        model.applyProfile(id)
    }

    @objc private func quitApp() { NSApp.terminate(nil) }
    @objc private func togglePause() { model.togglePause() }
    @objc private func reapplyLayout() { model.reapplyLayout() }
    @objc private func releaseAll() { model.releaseAll() }

    func applicationDidBecomeActive(_ notification: Notification) {
        // Returning from System Settings must update the banner immediately.
        model.recheckPermission()
        let present = activationPolicy.applicationActivated(isSpaceTabs: true)
        model.workspaceActivationEvent = L10n.tr("AppKit / Cmd-Tab; restore=\(present)")
        if present { requestWorkspacePresentation(source: L10n.tr("AppKit / Cmd-Tab")) }
    }

    private func requestWorkspacePresentation(source: String) {
        activationTask?.cancel()
        activationTask = Task { [weak self] in
            // Coalesce AppKit, workspace activation and Dock reopen signals.
            do { try await Task.sleep(for: .milliseconds(120)) } catch { return }
            guard let self else { return }
            model.presentSelectedWindows(source: source)
        }
    }

    func menuNeedsUpdate(_ menu: NSMenu) {
        if menu is SavedProfilesMenu {
            menu.removeAllItems()
            if model.preferences.profiles.isEmpty {
                let item = menu.addItem(
                    withTitle: L10n.tr("No saved profiles. Save one in Settings → Profiles."), action: nil,
                    keyEquivalent: "")
                item.isEnabled = false
            }
            for profile in model.preferences.profiles {
                let item = menu.addItem(
                    withTitle: profile.name, action: #selector(applySavedProfile(_:)), keyEquivalent: "")
                item.target = self
                item.representedObject = profile.id.uuidString
                item.isEnabled = model.canApplyProfile
            }
            return
        }
        if let item = menu.items.first(where: { $0.action == #selector(revealTabs) }) {
            item.title =
                L10n.tr("Show Tabs · ")
                + (model.preferences.shortcuts[ShortcutManager.Action.showTabs.rawValue]
                ?? ShortcutManager.Action.showTabs.defaultBinding).display
        }
        pauseItem?.title = model.paused ? L10n.tr("Resume on This Desktop") : L10n.tr("Pause and Restore Windows")
        pauseItem?.isEnabled = !model.busy && !model.scanning && !model.terminating
        releaseItem?.isEnabled =
            (!model.originals.isEmpty || !model.applicationAssignments.isEmpty) && !model.busy && !model.scanning
            && !model.terminating
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { false }

    func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
        if CommandLine.arguments.contains("--smoke-test") { return .terminateNow }
        guard !terminationPending else { return .terminateLater }
        terminationPending = true
        windowDrag.stop()
        rightDrag.stop()
        panels.hide()
        Task {
            let errors = await model.prepareForTermination()
            if !errors.isEmpty {
                let alert = NSAlert()
                alert.messageText = L10n.tr("SpaceTabs could not finish quitting")
                alert.informativeText = errors.joined(separator: "\n")
                alert.addButton(withTitle: L10n.tr("Cancel Quit"))
                alert.addButton(withTitle: L10n.tr("Quit Anyway"))
                NSApp.activate()
                if alert.runModal() == .alertFirstButtonReturn {
                    model.terminating = false
                    model.paused = true
                    model.message = L10n.tr("Quit cancelled. SpaceTabs is paused. You can resume or release windows.")
                    terminationPending = false
                    windowDrag.start(model: model)
                    rightDrag.start(model: model)
                    sender.reply(toApplicationShouldTerminate: false)
                    showSettings()
                    return
                }
            }
            await model.windowManager.shutdown()
            sender.reply(toApplicationShouldTerminate: true)
        }
        return .terminateLater
    }

    func applicationWillTerminate(_ notification: Notification) {
        responsiveness.stop()
        DiagnosticLog.shared.record("session.end")
        DiagnosticLog.shared.flush()
        for observer in localizationObservers { NotificationCenter.default.removeObserver(observer) }
        localizationObservers.removeAll()
        quickSwitcher.close()
        settingsHost.stop()
        model.spaceChangeTask?.cancel()
        model.displayProfileTask?.cancel()
        model.zoomRequestTask?.cancel()
        environmentTask?.cancel()
        activationTask?.cancel()
        panels.stop()
        windowDrag.stop()
        rightDrag.stop()
        model.catalogMonitor.stop()
        shortcuts.stop()
        if let axObserver { NotificationCenter.default.removeObserver(axObserver) }
        if let screenObserver { NotificationCenter.default.removeObserver(screenObserver) }
        if let spaceObserver { NSWorkspace.shared.notificationCenter.removeObserver(spaceObserver) }
        for token in workspaceObservers { NSWorkspace.shared.notificationCenter.removeObserver(token) }
    }

    @objc private func showSettings() {
        activationTask?.cancel()
        model.noteUserInteraction()
        settingsHost.show()
        model.refreshApplications()
        if !model.hasCompletedDiscovery { model.startInitialDiscovery() }
    }
}
