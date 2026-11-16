import AppKit
import SpaceTabsCore

@MainActor protocol WorkspaceDesktopAnchor: AnyObject {
    var isOnActiveSpace: Bool { get }
    func close()
}
extension NSPanel: WorkspaceDesktopAnchor {}

struct WorkspaceSummary: Codable, Equatable, Sendable, Identifiable {
    let id: UUID
    let name: String
    let displayName: String
    let isOpen: Bool
    let isHere: Bool
}

/// Owns all workspace models; only the discovery owner enumerates external windows.
/// Retained ordinary panels identify native desktop membership for this process lifetime.
@MainActor final class WorkspaceCoordinator {
    @MainActor final class Runtime {
        let model: AppModel
        let panels = PanelController()
        var anchor: (any WorkspaceDesktopAnchor)?
        var reserved = Set<UUID>()
        var restorationTask: Task<Void, Never>?
        init(_ model: AppModel) { self.model = model }
    }
    let discovery: AppModel
    let store: WorkspaceStore
    private(set) var document = WorkspaceDocument()
    private(set) var runtimes: [UUID: Runtime] = [:]
    private(set) var selectedID: UUID?
    private var visibleWindows: [WindowServerWindow] = []
    private var blocked = false
    private var changing = false
    private var transitionTask: Task<Void, Never>?
    private var discoveryRevision = 0
    private var contextRevision = 0
    var registryChanged: () -> Void = {}
    var presentationChanged: (AppModel) -> Void = { _ in }
    var selectionChanged: (AppModel) -> Void = { _ in }
    var configureModel: (AppModel) -> Void = { _ in }
    var selected: AppModel { selectedID.flatMap { runtimes[$0]?.model } ?? discovery }
    var models: [AppModel] { runtimes.values.map(\.model) }

    init(discovery: AppModel, store: WorkspaceStore = .standard) {
        self.discovery = discovery
        self.store = store
    }

    func start() {
        do {
            if let saved = try store.load() {
                document = saved
                discovery.workspaceDesktopAvailable = false
                discovery.pendingTabs = []
                discovery.applicationAssignments = []
                discovery.pendingAutomaticProfile = nil
                discovery.saveWorkspaceLayout = { _, _ in }
                // Rebinding is explicit after restart; never guess a native desktop.
                for record in saved.records { _ = makeRuntime(record) }
                if let first = saved.records.first { select(first.id) }
            } else {
                let record = WorkspaceRecord(
                    name: L10n.tr("Main workspace"),
                    displayID: discovery.screen.map(AppModel.stableDisplayID) ?? "",
                    layout: discovery.sessionManifest(tabs: discovery.tabs, originals: discovery.originals),
                    zoneNames: discovery.preferences.zoneNames)
                try commit(WorkspaceDocument(records: [record]))
                let runtime = makeRuntime(record, using: discovery)
                if let screen = discovery.screen { attach(runtime, to: screen) }
                select(record.id)
            }
        } catch {
            blocked = true
            discovery.configurationBlocked = true
            discovery.workspaceDesktopAvailable = false
            discovery.message = L10n.tr("Could not open workspaces: \(error.localizedDescription)")
        }
        discovery.discoveryBundles = { [weak self] in
            Set(
                self?.models.flatMap {
                    $0.pendingTabs.map { $0.identity.bundleID } + $0.applicationAssignments.map(\.bundleID)
                } ?? [])
        }
        discovery.discoveryPublished = { [weak self] result, full in self?.publish(result, full: full) }
        discovery.focusPublished = { [weak self] id in
            guard let self else { return }
            for model in models where model !== discovery { model.adoptFocus(id) }
        }
        discovery.catalogPublished = { [weak self] apps in
            guard let self else { return }
            for model in models where model !== discovery { model.installedApplications = apps }
        }
        updateContexts()
    }

    private func commit(_ next: WorkspaceDocument) throws {
        guard !blocked else { throw ConfigurationError(L10n.tr("Workspace storage is unavailable.")) }
        try store.save(next)
        document = next
    }

    private func makeRuntime(_ record: WorkspaceRecord, using existing: AppModel? = nil) -> Runtime {
        let model =
            existing
            ?? AppModel(
                preferencesStore: discovery.preferencesStore,
                persistence: PersistenceStore(url: store.url), windowManager: discovery.windowManager,
                applicationCatalog: discovery.applicationCatalog)
        let runtime = Runtime(model)
        runtimes[record.id] = runtime
        model.workspaceID = record.id
        model.workspaceName = record.name
        model.desktopMenuCloudManaged = discovery.desktopMenuCloudManaged
        model.workspaceDesktopAvailable = false
        model.preferencesBlocked = discovery.preferencesBlocked
        model.loginEnabled = discovery.loginEnabled
        model.loginNeedsApproval = discovery.loginNeedsApproval
        model.preferences = discovery.preferences
        model.preferences.zoneNames = record.zoneNames
        model.loadWorkspaceLayout = { [weak self] in self?.document.records.first { $0.id == record.id }?.layout }
        model.saveWorkspaceLayout = { [weak self, weak runtime, weak model] layout, live in
            guard let self, let runtime, let model,
                let index = document.records.firstIndex(where: { $0.id == record.id })
            else {
                throw ConfigurationError(L10n.tr("Workspace is no longer available."))
            }
            for id in live {
                if let window = model.windows.first(where: { $0.id == id }), !ownershipAllows(window, for: record.id) {
                    throw ConfigurationError(L10n.tr("This window already belongs to another workspace."))
                }
            }
            var next = document
            next.records[index].layout = layout
            next.records[index].zoneNames = model.preferences.zoneNames
            try commit(next)
            runtime.reserved = live
        }
        model.preferencesCommitted = { [weak self, weak model] value in
            guard let self, let model else { return }
            for other in models where other !== model {
                let names = other.preferences.zoneNames
                other.preferences = value
                other.preferences.zoneNames = names
            }
            if discovery !== model, !models.contains(where: { $0 === discovery }) { discovery.preferences = value }
            model.saveLayout()
        }
        model.profileOpening = { [weak self, weak model] id in self?.openProfile(id, screen: model?.screen) }
        model.profileSaved = { [weak self] id in self?.bindSavedProfile(id, workspace: record.id) }
        model.workspaceCommand = { [weak self] command in self?.handle(command) }
        model.windowIsEligible = { [weak self] window in self?.eligible(window, for: record.id) ?? false }
        if model !== discovery {
            model.discoveryOwner = discovery
            model.windows = discovery.windows
            model.installedApplications = discovery.installedApplications
            model.hasCompletedDiscovery = discovery.hasCompletedDiscovery
            model.hasCompletedFullDiscovery = discovery.hasCompletedFullDiscovery
        }
        model.loadConfiguration()
        model.pendingAutomaticProfile = nil
        model.tabDragVisibility = { [weak runtime] in runtime?.panels.setTabDragging($0) }
        model.showTabBars = { [weak runtime] in
            guard let runtime, runtime.model.workspaceDesktopAvailable else { return }
            runtime.panels.reveal()
        }
        model.layoutChanged = { [weak self, weak runtime] in
            guard let self, let runtime else { return }
            render(runtime)
        }
        configureModel(model)
        return runtime
    }

    private func bindSavedProfile(_ id: UUID, workspace: UUID) {
        guard let index = document.records.firstIndex(where: { $0.id == workspace }),
            let profile = selected.preferences.profiles.first(where: { $0.id == id })
        else { return }
        do {
            var next = document
            // Saving a copy does not steal a profile's already-open instance.
            if next.records.contains(where: { $0.profileID == id && $0.id != workspace }) { return }
            next.records[index].profileID = id
            next.records[index].name = profile.name
            try commit(next)
            runtimes[workspace]?.model.workspaceName = profile.name
            updateSummaries()
        } catch { selected.message = error.localizedDescription }
    }

    func rename(_ id: UUID, name: String) {
        guard !blocked, let index = document.records.firstIndex(where: { $0.id == id }),
            let model = runtimes[id]?.model, !model.terminating
        else { return }
        let name = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty, name.count <= PreferenceLimits.profileNameCharacters else {
            selected.message = L10n.tr("Use a name between 1 and \(PreferenceLimits.profileNameCharacters) characters.")
            return
        }
        do {
            var next = document
            next.records[index].name = name
            // Publish the name only after its durable metadata write succeeds.
            try commit(next)
            model.workspaceName = name
            updateSummaries()
        } catch {
            DiagnosticLog.shared.failure(error, operation: #function)
            selected.message = L10n.tr("Could not rename workspace: \(error.localizedDescription)")
        }
    }

    func select(_ id: UUID) {
        guard let runtime = runtimes[id] else { return }
        if selectedID == id {
            updateSummaries()
            return
        }
        if selectedID != nil {
            selected.cancelWorkspacePresentation()
            selected.noteUserInteraction()
        }
        selectedID = id
        selectionChanged(runtime.model)
        updateSummaries()
    }

    func newWorkspace(on screen: NSScreen) {
        guard !blocked, !changing else { return }
        do {
            let name = L10n.tr("Workspace \(document.records.count + 1)")
            let record = WorkspaceRecord(name: name, displayID: AppModel.stableDisplayID(screen))
            var next = document
            next.records.append(record)
            try commit(next)
            _ = makeRuntime(record)
            open(record.id, on: screen)
        } catch { selected.message = error.localizedDescription }
    }

    func openProfile(_ id: UUID, screen: NSScreen?) {
        guard let profile = selected.preferences.profiles.first(where: { $0.id == id }),
            let screen = screen ?? NSScreen.screens.first, !blocked, !changing
        else { return }
        if let record = document.records.first(where: { $0.profileID == id }) {
            open(record.id, on: screen)
            return
        }
        do {
            var layout = profile.layout
            // Profile slots are intentions, never a claim on another instance's runtime UUIDs.
            layout.tabs = SavedTabManifest.profileTabs(layout.tabs)
            let record = WorkspaceRecord(
                name: profile.name, profileID: id,
                displayID: AppModel.stableDisplayID(screen), layout: layout, zoneNames: profile.zoneNames)
            var next = document
            next.records.append(record)
            try commit(next)
            _ = makeRuntime(record)
            open(record.id, on: screen)
        } catch { selected.message = error.localizedDescription }
    }

    func open(_ id: UUID, on screen: NSScreen) {
        guard !changing, !blocked, let runtime = runtimes[id] else { return }
        if runtime.anchor != nil {
            select(id)
            if runtime.model.workspaceDesktopAvailable {
                runtime.panels.reveal()
            } else {
                runtime.model.message = L10n.tr(
                    "This workspace is open on another desktop. Switch to that desktop to use it.")
            }
            return
        }
        changing = true
        let context = contextRevision
        Task { [weak self] in
            guard let self else { return }
            defer { changing = false }
            if let occupied = occupant(on: screen), occupied != id {
                guard await closeRuntime(occupied) else { return }
            }
            guard !runtime.model.spaceTransitioning, contextRevision == context else { return }
            do {
                var next = document
                guard let index = next.records.firstIndex(where: { $0.id == id }) else { return }
                next.records[index].displayID = AppModel.stableDisplayID(screen)
                next.records[index].layout.screenID = AppModel.screenID(screen)
                try commit(next)
                runtime.model.loadConfiguration()
                attach(runtime, to: screen)
                select(id)
                render(runtime)
                runtime.panels.reveal()
                visibleWindows = await WindowServerCatalog().visibleWindows()
                runtime.model.restoreSavedSession(automatically: true)
                runtime.model.applyApplicationAssignments()
                if let profileID = next.records[index].profileID,
                    let profile = runtime.model.preferences.profiles.first(where: { $0.id == profileID })
                {
                    runtime.model.openAssignedApps(for: profile)
                }
                await runtime.model.operationTask?.value
                if contextRevision == context { restore(id) }
            } catch { selected.message = error.localizedDescription }
        }
    }

    private func attach(_ runtime: Runtime, to screen: NSScreen) {
        runtime.reserved = []
        runtime.panels.start()
        let anchor = NSPanel(
            contentRect: NSRect(
                x: screen.visibleFrame.minX + 4,
                y: screen.visibleFrame.minY + 4, width: 2, height: 2),
            styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        anchor.collectionBehavior = [.managed, .fullScreenNone]
        anchor.hidesOnDeactivate = false
        anchor.isReleasedWhenClosed = false
        anchor.ignoresMouseEvents = true
        anchor.level = .floating
        anchor.isMovable = false
        anchor.isOpaque = true
        anchor.backgroundColor = .gray
        anchor.animationBehavior = .none
        anchor.orderFrontRegardless()
        anchor.orderOut(nil)
        runtime.anchor = anchor
        runtime.model.selectedScreenID = AppModel.screenID(screen)
        runtime.model.appliedScreenID = AppModel.screenID(screen)
        runtime.model.displaySelection = DisplaySelectionTracker()
        runtime.model.updateDisplayAvailability()
        runtime.model.workspaceDesktopAvailable = true
    }

    private func occupant(on screen: NSScreen) -> UUID? {
        let display = AppModel.stableDisplayID(screen)
        return document.records.first { record in
            record.displayID == display && runtimes[record.id]?.anchor?.isOnActiveSpace == true
        }?.id
    }

    func close(_ id: UUID) {
        guard !changing else { return }
        changing = true
        Task { [weak self] in
            guard let self else { return }
            defer { changing = false }
            _ = await closeRuntime(id)
        }
    }

    private func closeRuntime(_ id: UUID) async -> Bool {
        guard let runtime = runtimes[id], runtime.anchor != nil else { return true }
        let model = runtime.model
        guard model.workspaceDesktopAvailable else {
            selected.message = L10n.tr("Switch to this workspace’s desktop before arranging its windows.")
            return false
        }
        guard !model.busy, !model.scanning else {
            selected.message = L10n.tr("Wait for the current operation to finish.")
            return false
        }
        runtime.restorationTask?.cancel()
        runtime.restorationTask = nil
        let errors = await model.prepareForTermination()
        model.terminating = false
        if model === discovery { model.scheduleRefresh() }
        guard errors.isEmpty else {
            model.paused = true
            model.message = errors.joined(separator: "\n")
            return false
        }
        runtime.panels.stop()
        runtime.anchor?.close()
        runtime.anchor = nil
        runtime.reserved = []
        model.tabs = TabManager()
        model.originals = [:]
        model.workspaceDesktopAvailable = false
        model.loadConfiguration()
        if model === discovery { model.scheduleRefresh() }
        updateSummaries()
        return true
    }

    func desktopChanged() {
        contextRevision += 1
        transitionTask?.cancel()
        visibleWindows = []
        for model in models {
            model.workspaceDesktopAvailable = false
            model.activeSpaceChanged()
        }
        transitionTask = Task { [weak self] in
            do { try await Task.sleep(for: .milliseconds(650)) } catch { return }
            guard let self else { return }
            visibleWindows = await WindowServerCatalog().visibleWindows()
            updateContexts(selectVisible: true)
            // A desktop event discovers only processes with actual on-screen
            // windows. This is one bounded event-driven batch, never an idle scan.
            for pid in Set(visibleWindows.map(\.pid)).sorted().prefix(64) {
                discovery.refreshRequests.requestDiscovery(pid: pid)
            }
            discovery.scheduleRefresh()
        }
    }

    func updateContexts(connectedDisplays supplied: Set<String>? = nil, selectVisible: Bool = false) {
        let connectedDisplays = supplied ?? Set(NSScreen.screens.map(AppModel.stableDisplayID))
        for (id, runtime) in runtimes {
            let connected =
                document.records.first { $0.id == id }.map { record in
                    connectedDisplays.contains(record.displayID)
                } ?? false
            let available = connected && runtime.anchor?.isOnActiveSpace == true
            if runtime.model.workspaceDesktopAvailable != available {
                runtime.model.workspaceDesktopAvailable = available
                render(runtime)
            }
        }
        if selectVisible, !selected.workspaceDesktopAvailable,
            let id = runtimes.first(where: { $0.value.model.workspaceDesktopAvailable })?.key
        {
            select(id)
        }
        updateSummaries()
    }

    private func render(_ runtime: Runtime) {
        let model = runtime.model
        defer { presentationChanged(model) }
        guard !model.managementSuspended, !model.terminating, let screen = model.screen else {
            runtime.panels.hide()
            return
        }
        runtime.panels.update(model: model, screen: screen)
    }

    private func updateSummaries() {
        let summaries = document.records.map { record in
            WorkspaceSummary(
                id: record.id, name: record.name,
                displayName: NSScreen.screens.first { AppModel.stableDisplayID($0) == record.displayID }?.localizedName
                    ?? L10n.tr("Disconnected"),
                isOpen: runtimes[record.id]?.anchor != nil,
                isHere: runtimes[record.id]?.model.workspaceDesktopAvailable == true)
        }
        var changed = false
        for model in models where model.workspaceSummaries != summaries {
            model.workspaceSummaries = summaries
            changed = true
        }
        if changed { registryChanged() }
    }

    private func ownershipAllows(_ window: WindowSnapshot, for id: UUID) -> Bool {
        !runtimes.contains { otherID, runtime in
            guard otherID != id, runtime.anchor != nil else { return false }
            let claimed = Set(runtime.model.originals.keys).union(runtime.reserved)
            return claimed.contains(window.id)
                || runtime.model.windows.contains {
                    claimed.contains($0.id) && $0.pid == window.pid && $0.windowNumber != nil
                        && $0.windowNumber == window.windowNumber
                }
        }
    }

    private func eligible(_ window: WindowSnapshot, for id: UUID) -> Bool {
        guard let runtime = runtimes[id], runtime.model.workspaceDesktopAvailable,
            ownershipAllows(window, for: id)
        else { return false }
        if runtime.model.tabs.zone(of: window.id) != nil { return true }
        guard let number = window.windowNumber else { return false }
        return visibleWindows.contains { $0.pid == window.pid && $0.number == number }
    }

    private func publish(_ result: ScanResult, full: Bool) {
        visibleWindows = result.visibleWindows
        discoveryRevision += 1
        let revision = discoveryRevision
        for model in models where model !== discovery {
            Task { [weak self, weak model] in
                guard let self, let model else { return }
                while model.busy && !model.terminating {
                    do { try await Task.sleep(for: .milliseconds(20)) } catch { return }
                }
                guard revision == discoveryRevision, !model.terminating else { return }
                model.applyDiscovery(result)
                if full { model.hasCompletedFullDiscovery = model.trusted }
                model.restoreSavedSession(automatically: true)
                model.applyApplicationAssignments()
            }
        }
    }

    func restore(_ id: UUID) {
        guard let model = runtimes[id]?.model, model.workspaceDesktopAvailable,
            !model.busy, !model.terminating
        else { return }
        select(id)
        let runtime = runtimes[id]
        runtime?.restorationTask?.cancel()
        let desktop = model.desktopRevision
        let input = PlacementInputSnapshot.capture()
        runtime?.restorationTask = Task { [weak model, weak self] in
            guard let model else { return }
            model.reapplyLayout()
            await model.operationTask?.value
            guard !Task.isCancelled, !model.managementSuspended, model.desktopRevision == desktop else { return }
            model.restoreSavedSession()
            await model.operationTask?.value
            var bundles = Set<String>()
            for saved in model.pendingTabs where bundles.insert(saved.identity.bundleID).inserted {
                guard !Task.isCancelled, !model.managementSuspended, !model.terminating,
                    model.desktopRevision == desktop
                else { return }
                model.reopenPendingTab(saved.id)
                await model.pendingReopenTasks[saved.id]?.value
                await model.operationTask?.value
            }
            if !Task.isCancelled, model.desktopRevision == desktop, self?.selectedID == id,
                PlacementInputSnapshot.capture() == input
            {
                model.presentSelectedWindows(source: L10n.tr("Restore"))
            }
        }
    }

    func revealVisibleTabs() {
        for runtime in runtimes.values where runtime.model.workspaceDesktopAvailable { runtime.panels.reveal() }
    }

    func workspaceHere(on screen: NSScreen) -> UUID? { occupant(on: screen) }

    func modelAtPointer() -> AppModel? {
        let point = NSEvent.mouseLocation
        return models.first { $0.workspaceDesktopAvailable && $0.screen?.frame.contains(point) == true }
    }

    func handle(_ command: SettingsCommand) {
        switch command {
        case .selectWorkspace(let id): select(id)
        case .renameWorkspace(let id, let name): rename(id, name: name)
        case .newWorkspace(let screenID):
            if let screen = NSScreen.screens.first(where: { AppModel.screenID($0) == screenID }) {
                newWorkspace(on: screen)
            }
        case .openWorkspaceHere(let id, let screenID):
            if let screen = NSScreen.screens.first(where: { AppModel.screenID($0) == screenID }) {
                open(id, on: screen)
            }
        case .closeWorkspace(let id): close(id)
        case .restoreWorkspace(let id): restore(id)
        case .showWorkspace(let id):
            select(id)
            if selected.workspaceDesktopAvailable {
                selected.showTabBars()
                selected.presentSelectedWindows(source: L10n.tr("Workspace menu"))
            }
        default: break
        }
    }

    func stop() {
        transitionTask?.cancel()
        for runtime in runtimes.values {
            runtime.restorationTask?.cancel()
            runtime.panels.stop()
            runtime.anchor?.close()
        }
    }
}
