import AppKit
import FinderSync
import SpaceTabsCore
import SwiftUI

private final class SavedProfilesMenu: NSMenu {}
private final class WorkspacesMenu: NSMenu {}
private final class StatusDashboardMenu: NSMenu {}

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate, NSMenuDelegate {
    private var item: NSStatusItem?
    private let discoveryModel = AppModel()
    private lazy var workspaces = WorkspaceCoordinator(discovery: discoveryModel)
    private var model: AppModel { workspaces.selected }
    private let responsiveness = ResponsivenessMonitor()
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
    private var desktopMenuCompatibilityTask: Task<Void, Never>?
    private var desktopMenuReady = false
    private var pendingDesktopURLs: [URL] = []
    private lazy var desktopMenuBridge = DesktopMenuBridge(
        snapshot: { [weak self] token, context in
            guard let self else {
                return DesktopMenuSnapshot(
                    token: token, context: context, managerPID: 0, launchDate: nil,
                    language: .english, ready: false, workspaces: [], profiles: [])
            }
            let entries = self.workspaces.document.records.map { record in
                let runtime = self.workspaces.runtimes[record.id]
                let model = runtime?.model
                return DesktopMenuWorkspace(
                    id: record.id, name: record.name, profileID: record.profileID,
                    displayID: record.displayID, isOpen: runtime?.anchor != nil,
                    isHere: model?.workspaceDesktopAvailable == true,
                    canRestore: model.map {
                        $0.trusted && !$0.managementSuspended && !$0.busy && !$0.scanning && !$0.terminating
                    } ?? false)
            }
            let preferences = self.discoveryModel.preferences
            return DesktopMenuSnapshot(
                token: token, context: context,
                managerPID: ProcessInfo.processInfo.processIdentifier,
                launchDate: NSRunningApplication.current.launchDate,
                language: preferences.language,
                ready: !self.terminationPending && !self.model.configurationBlocked
                    && !self.workspaces.models.contains {
                        $0.spaceTransitioning || $0.displayProfileTask != nil
                    }, workspaces: entries,
                profiles: preferences.profiles.map { DesktopMenuProfile(id: $0.id, name: $0.name) })
        }, perform: { [weak self] request in self?.performDesktopMenu(request) })
    private var activationTask: Task<Void, Never>?

    func applicationDidFinishLaunching(_ notification: Notification) {
        responsiveness.start()
        if CommandLine.arguments.contains("--smoke-test") {
            print("SpaceTabs: AppKit started; displays=\(NSScreen.screens.count)")
            DispatchQueue.main.asyncAfter(deadline: .now() + 1) { NSApp.terminate(nil) }
            return
        }
        discoveryModel.loadConfiguration()
        discoveryModel.loadUserPreferences()
        model.refreshLoginStatus()
        workspaces.presentationChanged = { [weak self] _ in
            self?.windowDrag.update()
            self?.rightDrag.update()
        }
        workspaces.configureModel = { [weak self] model in
            guard let self else { return }
            model.restartShortcuts = { [weak self] in self?.registerShortcuts() }
            model.openSettings = { [weak self, weak model] in
                guard let self, let id = model?.workspaceID else { return }
                self.workspaces.select(id)
                self.showSettings()
            }
            model.showQuickSwitcher = { [weak self, weak model] in
                guard let self, let model else { return }
                self.quickSwitcher.show(model: model)
            }
        }
        workspaces.selectionChanged = { [weak self] model in
            guard let self else { return }
            self.windowDrag.stop()
            self.rightDrag.stop()
            self.windowDrag.start(model: model)
            self.rightDrag.start(model: model)
            self.settingsHost.useModel(model)
        }
        windowDrag.modelAtPoint = { [weak self] point in
            self?.workspaces.models.first { $0.workspaceDesktopAvailable && $0.screen?.frame.contains(point) == true }
        }
        rightDrag.modelAtPoint = windowDrag.modelAtPoint
        workspaces.registryChanged = { [weak self] in
            guard let self, self.desktopMenuReady else { return }
            self.desktopMenuBridge.refresh()
        }
        workspaces.start()
        refreshDesktopMenuCompatibility()
        screenTopology = currentScreenTopology()
        windowDrag.start(model: model)
        rightDrag.start(model: model)
        discoveryModel.catalogMonitor.changed = { [weak self] in self?.discoveryModel.refreshApplications() }
        item = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        item?.button?.image = NSImage(systemSymbolName: "rectangle.split.2x1", accessibilityDescription: "SpaceTabs")
        item?.button?.toolTip = "SpaceTabs"
        installStatusMenu()
        installMainMenu()
        observeLanguage()
        shortcuts.handler = { [weak self] action in
            guard let self else { return }
            if action == .showTabs {
                self.workspaces.revealVisibleTabs()
                return
            }
            Task { @MainActor in
                let focused = await self.discoveryModel.windowManager.focusedManagedID()
                let target =
                    self.workspaces.models.first { model in
                        model.workspaceDesktopAvailable && focused.flatMap { model.tabs.zone(of: $0) } != nil
                    } ?? self.workspaces.modelAtPointer()
                guard let target, let id = target.workspaceID else { return }
                self.workspaces.select(id)
                target.handleShortcut(action)
            }
        }
        registerShortcuts()
        axObserver = NotificationCenter.default.addObserver(forName: .spaceTabsAXChanged, object: nil, queue: .main) {
            [weak self] event in
            guard let pid = event.userInfo?["pid"] as? Int32, let name = event.userInfo?["notification"] as? String
            else { return }
            Task { @MainActor in self?.discoveryModel.accessibilityChanged(pid: pid, notification: name) }
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
                    self.discoveryModel.applicationChanged(pid: pid, activated: activated)
                    for model in self.workspaces.models where model !== self.discoveryModel {
                        if !activated { model.scheduleAssignedLaunchDiscovery(pid: pid) }
                    }
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
                    for model in self.workspaces.models { model.physicalDisplaysChanged(applyLinkedProfile: false) }
                    self.workspaces.updateContexts()
                }
            }
            workspaceObservers.append(token)
        }
        spaceObserver = NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.activeSpaceDidChangeNotification, object: nil, queue: .main
        ) { [weak self] _ in
            Task { @MainActor in
                self?.workspaces.desktopChanged()
                self?.desktopMenuBridge.invalidateContext()
            }
        }
        screenObserver = NotificationCenter.default.addObserver(
            forName: NSApplication.didChangeScreenParametersNotification, object: nil, queue: .main
        ) { [weak self] _ in
            Task { @MainActor in
                guard let self else { return }
                let topology = self.currentScreenTopology()
                guard topology != self.screenTopology else { return }
                self.screenTopology = topology
                for model in self.workspaces.models { model.physicalDisplaysChanged(applyLinkedProfile: false) }
                self.workspaces.updateContexts()
                self.desktopMenuBridge.invalidateContext()
            }
        }
        environmentTask = Task { [weak self] in
            while !Task.isCancelled {
                if let self {
                    self.responsiveness.update(self.model.diagnosticContext)
                    self.discoveryModel.checkEnvironment()
                    for model in self.workspaces.models where model !== self.discoveryModel { model.checkEnvironment() }
                    self.workspaces.updateContexts()
                }
                do { try await Task.sleep(for: .seconds(5)) } catch { break }
            }
        }
        model.layoutChanged()
        if CommandLine.arguments.contains("--demo") {
            model.startDemo()
            showSettings()
        } else {
            discoveryModel.startInitialDiscovery()
            // Existing sessions restore before any unrelated app is inspected.
            // Settings open from the menu and + buttons in their own app.
            if !model.trusted
                || (!model.loginEnabled && model.pendingTabs.isEmpty && model.applicationAssignments.isEmpty)
            {
                showSettings()
            }
        }
        activationPolicy.ready = true
        desktopMenuBridge.start()
        desktopMenuReady = true
        let urls = pendingDesktopURLs
        pendingDesktopURLs.removeAll()
        for url in urls { receiveDesktopURL(url) }
    }

    private func installStatusMenu() {
        let menu = StatusDashboardMenu()
        menu.delegate = self
        menu.autoenablesItems = false
        let dashboard = NSMenuItem()
        dashboard.tag = 100
        menu.addItem(dashboard)
        menu.addItem(.separator())
        menu.addItem(makeWorkspacesMenu())
        menu.addItem(makeProfilesMenu())
        let advancedItem = NSMenuItem(title: L10n.tr("More Actions"), action: nil, keyEquivalent: "")
        let advanced = NSMenu()
        advanced.autoenablesItems = false
        advanced.delegate = self
        advancedItem.submenu = advanced
        menu.addItem(advancedItem)
        let settings = advanced.addItem(
            withTitle: L10n.tr("Windows and Settings…"), action: #selector(showSettings), keyEquivalent: ",")
        settings.target = self
        let showTabs = advanced.addItem(
            withTitle: L10n.tr("Show Tabs · ⌃⌥T"), action: #selector(revealTabs), keyEquivalent: "")
        showTabs.target = self
        let desktopMenu = advanced.addItem(
            withTitle: L10n.tr("Manage Desktop Menu…"), action: #selector(enableDesktopMenu), keyEquivalent: "")
        desktopMenu.target = self
        pauseItem = advanced.addItem(
            withTitle: L10n.tr("Pause and Restore Windows"), action: #selector(togglePause), keyEquivalent: "")
        pauseItem?.target = self
        let reapply = advanced.addItem(
            withTitle: L10n.tr("Reapply Layout"), action: #selector(reapplyLayout), keyEquivalent: "")
        reapply.target = self
        releaseItem = advanced.addItem(
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
        application.addItem(makeWorkspacesMenu())
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
        // Restore the workspace first; an already-open Settings window follows.
        return false
    }

    private func currentScreenTopology() -> [String: CGRect] {
        Dictionary(uniqueKeysWithValues: NSScreen.screens.map { (AppModel.screenID($0), $0.frame) })
    }

    private func registerShortcuts() {
        let warnings = shortcuts.start(bindings: model.preferences.shortcuts)
        let registered = Set(shortcuts.registeredActions.map(\.rawValue))
        discoveryModel.shortcutWarnings = warnings
        discoveryModel.registeredShortcuts = registered
        for model in workspaces.models {
            model.shortcutWarnings = warnings
            model.registeredShortcuts = registered
        }
    }

    @objc private func revealTabs() { workspaces.revealVisibleTabs() }

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
        workspaces.openProfile(id, screen: workspaces.modelAtPointer()?.screen ?? model.screen)
    }

    @objc private func selectWorkspaceSettings(_ sender: NSMenuItem) {
        guard let id = sender.representedObject as? UUID else { return }
        workspaces.select(id)
        showSettings()
    }

    private func refreshDesktopMenuCompatibility() {
        guard desktopMenuCompatibilityTask == nil else { return }
        desktopMenuCompatibilityTask = Task { [weak self] in
            let cloudManaged = await Task.detached(priority: .utility) { () -> Bool? in
                guard let desktop = DesktopMenuStorage.desktop else { return nil }
                return try? desktop.resourceValues(forKeys: [.isUbiquitousItemKey]).isUbiquitousItem
            }.value
            guard let self, !Task.isCancelled else { return }
            discoveryModel.desktopMenuCloudManaged = cloudManaged
            for model in workspaces.models { model.desktopMenuCloudManaged = cloudManaged }
            desktopMenuCompatibilityTask = nil
        }
    }

    @objc private func enableDesktopMenu() { FIFinderSyncController.showExtensionManagementInterface() }

    func application(_ application: NSApplication, open urls: [URL]) {
        for url in urls.prefix(8) where url.absoluteString.utf8.count <= 8192 {
            if desktopMenuReady {
                receiveDesktopURL(url)
            } else if pendingDesktopURLs.count < 8 {
                pendingDesktopURLs.append(url)
            }
        }
    }
    private func receiveDesktopURL(_ url: URL) {
        if url.absoluteString == "\(SpaceTabsIdentity.desktopMenuScheme)://settings" {
            showSettings()
            return
        }
        _ = desktopMenuBridge.receive(url)
    }
    private func performDesktopMenu(_ request: DesktopMenuRequest) {
        activationTask?.cancel()
        guard !terminationPending,
            let screen = NSScreen.screens.first(where: {
                AppModel.stableDisplayID($0) == request.displayID
            })
        else { return }
        workspaces.updateContexts()
        switch request.action {
        case .newWorkspace: workspaces.newWorkspace(on: screen)
        case .openWorkspace(let id): workspaces.open(id, on: screen)
        case .openProfile(let id): workspaces.openProfile(id, screen: screen)
        case .show, .restore, .showTabs:
            guard let id = workspaces.workspaceHere(on: screen), let runtime = workspaces.runtimes[id],
                runtime.model.workspaceDesktopAvailable
            else { return }
            switch request.action {
            case .show: workspaces.handle(.showWorkspace(id))
            case .restore: workspaces.restore(id)
            case .showTabs: runtime.model.showTabBars()
            default: break
            }
        }
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
            model.presentSelectedWindows(source: source) { [weak self] in self?.settingsHost.presentIfOpen() }
        }
    }

    private func makeWorkspacesMenu() -> NSMenuItem {
        let item = NSMenuItem(title: L10n.tr("Workspaces"), action: nil, keyEquivalent: "")
        let menu = WorkspacesMenu(title: item.title)
        menu.autoenablesItems = false
        menu.delegate = self
        item.submenu = menu
        return item
    }

    @objc private func workspaceAction(_ sender: NSMenuItem) {
        guard let action = sender.representedObject as? SettingsCommand else { return }
        workspaces.handle(action)
    }
    @objc private func showWorkspace(_ sender: NSMenuItem) {
        guard let id = sender.representedObject as? UUID else { return }
        workspaces.select(id)
        guard model.workspaceDesktopAvailable else { return }
        model.showTabBars()
        model.presentSelectedWindows(source: L10n.tr("Workspace menu"))
    }
    @objc private func restoreWorkspace(_ sender: NSMenuItem) {
        guard let id = sender.representedObject as? UUID else { return }
        workspaces.restore(id)
    }

    private func updateDashboard(_ menu: NSMenu) {
        workspaces.updateContexts()
        let cards = model.workspaceSummaries.compactMap { summary -> WorkspaceMenuCard? in
            guard let runtime = workspaces.runtimes[summary.id] else { return nil }
            let model = runtime.model
            return WorkspaceMenuCard(
                summary: summary, template: model.layoutTemplate, ratio: model.ratio, rowRatio: model.rowRatio,
                canRestore: summary.isHere && model.trusted && !model.managementSuspended
                    && !model.busy && !model.scanning && !model.terminating)
        }
        let finish: (@escaping @MainActor @Sendable () -> Void) -> Void = { [weak menu] action in
            menu?.cancelTracking()
            // Leave AppKit's tracking stack before showing Settings or changing windows.
            DispatchQueue.main.async(execute: action)
        }
        let dashboard = StatusDashboardView(
            cards: cards,
            shortcut: (model.preferences.shortcuts[ShortcutManager.Action.showTabs.rawValue]
                ?? ShortcutManager.Action.showTabs.defaultBinding).display,
            settings: { [weak self] in finish { self?.showSettings() } },
            howTo: { [weak self] in
                finish {
                    guard let self else { return }
                    self.model.howToRequest += 1
                    self.showSettings()
                }
            },
            showTabs: { [weak self] in finish { self?.revealTabs() } },
            show: { [weak self] id in finish { self?.workspaces.handle(.showWorkspace(id)) } },
            restore: { [weak self] id in finish { self?.workspaces.restore(id) } },
            configure: { [weak self] id in
                finish {
                    self?.workspaces.select(id)
                    self?.showSettings()
                }
            })
        let host = NSHostingView(rootView: dashboard)
        host.frame = NSRect(origin: .zero, size: host.fittingSize)
        menu.item(withTag: 100)?.view = host
    }

    func menuNeedsUpdate(_ menu: NSMenu) {
        if menu is StatusDashboardMenu { updateDashboard(menu) }
        if menu is WorkspacesMenu {
            workspaces.updateContexts()
            menu.removeAllItems()
            for screen in NSScreen.screens {
                let item = menu.addItem(
                    withTitle: L10n.tr("New workspace on \(screen.localizedName)…"),
                    action: #selector(workspaceAction(_:)), keyEquivalent: "")
                item.target = self
                item.representedObject = SettingsCommand.newWorkspace(AppModel.screenID(screen))
            }
            menu.addItem(.separator())
            for summary in model.workspaceSummaries {
                let state =
                    summary.isHere
                    ? L10n.tr("Current desktop") : summary.isOpen ? L10n.tr("Other desktop") : L10n.tr("Closed")
                let item = NSMenuItem(
                    title: "\(summary.name) · \(summary.displayName) · \(state)", action: nil, keyEquivalent: "")
                let actions = NSMenu()
                actions.autoenablesItems = false
                item.submenu = actions
                menu.addItem(item)
                let settings = actions.addItem(
                    withTitle: L10n.tr("Windows and Settings…"), action: #selector(selectWorkspaceSettings(_:)),
                    keyEquivalent: "")
                settings.target = self
                settings.representedObject = summary.id
                for (title, action) in [
                    (L10n.tr("Show"), #selector(showWorkspace(_:))),
                    (L10n.tr("Restore"), #selector(restoreWorkspace(_:))),
                ] {
                    let entry = actions.addItem(withTitle: title, action: action, keyEquivalent: "")
                    entry.target = self
                    entry.representedObject = summary.id
                    entry.isEnabled = summary.isHere
                }
                if !summary.isOpen {
                    for screen in NSScreen.screens {
                        let entry = actions.addItem(
                            withTitle: L10n.tr("Open here on \(screen.localizedName)"),
                            action: #selector(workspaceAction(_:)), keyEquivalent: "")
                        entry.target = self
                        entry.representedObject = SettingsCommand.openWorkspaceHere(
                            summary.id, AppModel.screenID(screen))
                    }
                } else {
                    let entry = actions.addItem(
                        withTitle: L10n.tr("Close workspace"), action: #selector(workspaceAction(_:)), keyEquivalent: ""
                    )
                    entry.target = self
                    entry.representedObject = SettingsCommand.closeWorkspace(summary.id)
                    entry.isEnabled = summary.isHere
                }
            }
            return
        }
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
                item.isEnabled = !model.busy && !model.terminating && !model.configurationBlocked
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
        for model in workspaces.models {
            model.workspaceDesktopAvailable = false
            model.layoutChanged()
        }
        Task {
            var errors: [String] = []
            for model in workspaces.models { errors.append(contentsOf: await model.prepareForTermination()) }
            if !errors.isEmpty {
                let alert = NSAlert()
                alert.messageText = L10n.tr("SpaceTabs could not finish quitting")
                alert.informativeText = errors.joined(separator: "\n")
                alert.addButton(withTitle: L10n.tr("Cancel Quit"))
                alert.addButton(withTitle: L10n.tr("Quit Anyway"))
                NSApp.activate()
                if alert.runModal() == .alertFirstButtonReturn {
                    for model in workspaces.models {
                        model.terminating = false
                        model.paused = true
                    }
                    workspaces.updateContexts()
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
        desktopMenuBridge.stop()
        desktopMenuCompatibilityTask?.cancel()
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
        workspaces.stop()
        windowDrag.stop()
        rightDrag.stop()
        discoveryModel.catalogMonitor.stop()
        shortcuts.stop()
        if let axObserver { NotificationCenter.default.removeObserver(axObserver) }
        if let screenObserver { NotificationCenter.default.removeObserver(screenObserver) }
        if let spaceObserver { NSWorkspace.shared.notificationCenter.removeObserver(spaceObserver) }
        for token in workspaceObservers { NSWorkspace.shared.notificationCenter.removeObserver(token) }
    }

    @objc private func showSettings() {
        refreshDesktopMenuCompatibility()
        activationTask?.cancel()
        model.noteUserInteraction()
        settingsHost.show()
        model.refreshApplications()
        if !discoveryModel.hasCompletedDiscovery { discoveryModel.startInitialDiscovery() }
    }
}
