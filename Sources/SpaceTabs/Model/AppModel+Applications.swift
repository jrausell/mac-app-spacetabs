import AppKit
import SpaceTabsCore
import UniformTypeIdentifiers

extension AppModel {
    func refreshApplications() {
        if sendToManager(.refreshApps) { return }
        guard !terminating else { return }
        guard !catalogUpdating else {
            catalogRefreshPending = true
            return
        }
        catalogUpdating = true
        Task {
            defer {
                catalogUpdating = false
                if catalogRefreshPending {
                    catalogRefreshPending = false
                    refreshApplications()
                }
            }
            do { applyCatalog(try await applicationCatalog.scan()) } catch {
                catalogMessage = L10n.tr("Could not read the catalog: \(error.localizedDescription)")
            }
        }
    }

    private func applyCatalog(_ snapshot: ApplicationCatalogSnapshot) {
        guard !terminating else { return }
        // Repeated filesystem events with the same result do not publish a list.
        if installedApplications != snapshot.applications { installedApplications = snapshot.applications }
        catalogMonitor.update(snapshot.directories)
        catalogMessage = nil
    }

    func addApplications() {
        let picker = NSOpenPanel()
        picker.title = L10n.tr("Add Apps to Catalog")
        picker.prompt = L10n.tr("Add")
        picker.allowedContentTypes = [.applicationBundle]
        picker.allowsMultipleSelection = true
        picker.canChooseFiles = true
        picker.canChooseDirectories = false
        picker.treatsFilePackagesAsDirectories = false
        picker.begin { [weak self] response in
            guard response == .OK else { return }
            let urls = picker.urls
            Task { @MainActor in
                guard let self else { return }
                if self.sendToManager(.addApps(urls)) { return }
                do { self.applyCatalog(try await self.applicationCatalog.add(urls)) } catch {
                    self.catalogMessage = L10n.tr("Could not add the app: \(error.localizedDescription)")
                }
            }
        }
    }

    func launchApplication(
        _ application: InstalledApplication, activates: Bool = true, completion: (@MainActor () -> Void)? = nil
    ) {
        if sendToManager(.launch(application.id)) {
            completion?()
            return
        }
        // Launches require an explicit Open action or an opted-in manual profile switch.
        guard application.url.isFileURL, application.url.pathExtension.lowercased() == "app",
            let bundle = Bundle(url: application.url), bundle.bundleIdentifier == application.bundleID,
            bundle.object(forInfoDictionaryKey: "CFBundlePackageType") as? String == "APPL",
            application.bundleID != SpaceTabsIdentity.appBundleID,
            application.bundleID != SpaceTabsIdentity.settingsBundleID
        else {
            catalogMessage = L10n.tr("The saved app no longer matches its path. Select it again in Apps.")
            completion?()
            return
        }
        guard !launchingApplications.contains(application.id) else {
            completion?()
            return
        }
        launchingApplications.insert(application.id)
        let configuration = NSWorkspace.OpenConfiguration()
        configuration.activates = activates
        NSWorkspace.shared.openApplication(at: application.url, configuration: configuration) {
            [weak self] app, error in
            let pid = app?.processIdentifier
            let detail = error?.localizedDescription
            Task { @MainActor in
                defer { completion?() }
                guard let self else { return }
                self.launchingApplications.remove(application.id)
                if let detail {
                    self.catalogMessage = L10n.tr("Could not open \(application.name): \(detail)")
                } else if let pid {
                    self.catalogMessage =
                        self.applicationAssignment(for: application) != nil
                        ? L10n.tr("\(application.name) opened. Waiting for its assigned windows.")
                        : L10n.tr("\(application.name) opened. Assign its windows to a zone in Open Windows.")
                    self.applicationChanged(pid: pid)
                }
            }
        }
    }

    func openAssignedApps(for profile: WorkspaceProfile, automatically: Bool = false) {
        guard profile.openAssignedApps, !automatically else { return }
        let running = Set(
            NSWorkspace.shared.runningApplications.compactMap {
                $0.bundleURL?.resolvingSymlinksInPath().standardizedFileURL.path
            })
        let applications = profile.closedAssignedApps(runningPaths: running, automatically: automatically)
        guard !applications.isEmpty else { return }
        profileLaunchTask = Task { [weak self] in
            guard let self else { return }
            for rule in applications {
                guard !Task.isCancelled, !terminating, !managementSuspended, trusted, !demo, !configurationBlocked,
                    preferences.profiles.first(where: { $0.id == profile.id })?.openAssignedApps == true
                else { return }
                guard applicationAssignments.contains(rule) else { continue }
                let stillRunning = NSWorkspace.shared.runningApplications.contains {
                    $0.bundleURL?.resolvingSymlinksInPath().standardizedFileURL.path == rule.id
                }
                if stillRunning { continue }
                // One launch at a time; AX assignment uses existing bounded launch events.
                await withCheckedContinuation { continuation in
                    launchApplication(
                        InstalledApplication(url: rule.url, name: rule.name, bundleID: rule.bundleID), activates: false
                    ) { continuation.resume() }
                }
            }
        }
    }
}

extension AppModel {
    func applicationAssignment(for application: InstalledApplication) -> ApplicationAssignment? {
        applicationAssignments.first { $0.id == application.id }
    }

    func assignApplication(_ application: InstalledApplication, to zone: Zone) {
        if sendToManager(.assignApp(application.id, zone)) { return }
        guard activeZones.contains(zone), !configurationBlocked, !terminating, !demo, !busy, !scanning else { return }
        let previous = applicationAssignments
        applicationAssignments.removeAll { $0.id == application.id }
        applicationAssignments.append(
            ApplicationAssignment(
                url: application.url, name: application.name, bundleID: application.bundleID, zone: zone))
        do { try checkpoint(tabs: tabs, originals: originals) } catch {
            applicationAssignments = previous
            catalogMessage = L10n.tr("Could not save the assignment: \(error.localizedDescription)")
            return
        }
        applicationAssignmentAttempts = applicationAssignmentAttempts.filter { $0.value != application.id }
        catalogMessage =
            L10n.tr("\(application.name) assigned to \(zone.title). Its windows will be placed there when available.")
        layoutChanged()
        showTabBarsAfterInteraction()
        applyApplicationAssignments()
        // One scoped discovery for an explicit assignment, never an idle poll.
        for app in NSWorkspace.shared.runningApplications
        where app.bundleURL?.resolvingSymlinksInPath().standardizedFileURL.path == application.id {
            applicationChanged(pid: app.processIdentifier)
        }
    }

    func assignment(for window: WindowSnapshot) -> ApplicationAssignment? {
        ApplicationAssignmentResolver.assignment(
            for: window,
            applicationURL: NSRunningApplication(processIdentifier: window.pid)?.bundleURL,
            assignments: applicationAssignments)
    }

    func pendingApplicationAssignments(in zone: Zone) -> [ApplicationAssignment] {
        guard !demo else { return [] }
        return applicationAssignments.filter { rule in
            rule.zone == zone
                && !windows.contains { window in
                    tabs.zone(of: window.id) == rule.zone && assignment(for: window)?.id == rule.id
                }
        }
    }

    /// A just-launched app may not expose AX until after its launch notification.
    /// Only saved apps get three bounded startup checks; there is no idle poll.
    func scheduleAssignedLaunchDiscovery(pid: Int32) {
        guard assignedLaunchTasks[pid] == nil,
            let path = NSRunningApplication(processIdentifier: pid)?.bundleURL?.resolvingSymlinksInPath()
                .standardizedFileURL.path,
            applicationAssignments.contains(where: { $0.id == path })
        else { return }
        assignedLaunchTasks[pid] = Task { [weak self] in
            guard let self else { return }
            defer { assignedLaunchTasks[pid] = nil }
            for delay: Duration in [.milliseconds(350), .seconds(1), .seconds(2)] {
                do { try await Task.sleep(for: delay) } catch { return }
                guard !terminating, !demo, !paused, trusted,
                    NSRunningApplication(processIdentifier: pid)?.isTerminated == false,
                    applicationAssignments.contains(where: { $0.id == path })
                        || pendingTabs.contains(where: {
                            $0.identity.bundleID == NSRunningApplication(processIdentifier: pid)?.bundleIdentifier
                        }),
                    !windows.contains(where: { $0.pid == pid })
                else { return }
                refreshRequests.requestDiscovery(pid: pid)
                scheduleRefresh()
            }
        }
    }

    func suppressAutomaticAssignment(for id: UUID) {
        guard let window = windows.first(where: { $0.id == id }), let rule = assignment(for: window) else { return }
        applicationAssignmentAttempts[id] = rule.id
    }

    func applyApplicationAssignments() {
        guard trusted, !tabSelectionRunner.isPending, !busy, !scanning, !refreshInFlight, !managementSuspended, !demo,
            !terminating, !configurationBlocked
        else { return }
        let applicationURLs = Dictionary(
            uniqueKeysWithValues: Set(windows.map(\.pid)).compactMap { pid in
                NSRunningApplication(processIdentifier: pid)?.bundleURL.map { (pid, $0) }
            })
        let assignedZones = Dictionary(
            uniqueKeysWithValues: Zone.allCases.flatMap { zone in
                tabs.windows[zone, default: []].map { ($0, zone) }
            })
        let eligible = ApplicationAssignmentResolver.candidates(
            windows: windows, applicationURLs: applicationURLs,
            assignments: applicationAssignments, assignedZones: assignedZones, attempts: applicationAssignmentAttempts)
        // Saved per-window zones take priority over a broad application rule.
        let reservedForSession = Set(pendingSessionMatches.values)
        let candidates = windows.compactMap { window in
            reservedForSession.contains(window.id) ? nil : eligible[window.id].map { (window, $0) }
        }
        guard !candidates.isEmpty else { return }
        for (window, rule) in candidates { applicationAssignmentAttempts[window.id] = rule.id }
        let revision = presentationRevision
        perform {
            var next = self.tabs
            var originalStates = self.originals
            for (window, rule) in candidates {
                if originalStates[window.id] == nil {
                    originalStates[window.id] = try await self.windowManager.state(of: window.id)
                }
                next.assign(window.id, to: rule.zone, selecting: self.tabs.selected[rule.zone] == nil)
            }
            let candidateIDs = Set(candidates.map { $0.0.id })
            let matchingPending = Set(
                WindowReconciler.matches(saved: self.pendingTabs, windows: self.windows)
                    .filter { candidateIDs.contains($0.value) }.keys)
            try self.checkpoint(tabs: next, originals: originalStates, excludingPending: matchingPending)
            do {
                let frames = try Dictionary(
                    uniqueKeysWithValues: candidates.map { window, rule in
                        (window.id, try self.targetFrame(rule.zone))
                    })
                let selected = self.activeZones.compactMap { next.selected[$0] }
                try await self.windowManager.applyLayout(frames: frames, selected: selected)
                if revision == 0 { try await self.raiseSelections(selected, revision: revision) }
            } catch {
                if let failure = error as? WindowError, !failure.recoveryStates.isEmpty {
                    self.tabs = next
                    self.originals = originalStates
                    self.pendingTabs.removeAll { matchingPending.contains($0.id) }
                }
                throw error
            }
            self.tabs = next
            self.originals = originalStates
            self.pendingTabs.removeAll { matchingPending.contains($0.id) }
            // Confirm each actual placement, including rules whose windows appear later.
            self.layoutChanged()
            self.showTabBarsAfterInteraction()
            // Do not activate an app or steal keyboard focus for an automatic rule.
        }
    }

    func removeApplicationAssignment(_ rule: ApplicationAssignment) {
        if sendToManager(.removeApp(rule.id)) { return }
        guard !busy, !scanning, !terminating else { return }
        let ids = windows.filter { assignment(for: $0)?.id == rule.id && originals[$0.id] != nil }.map(\.id)
        if ids.isEmpty {
            applicationAssignments.removeAll { $0.id == rule.id }
            saveLayout()
            layoutChanged()
            return
        }
        perform(allowPaused: true) {
            self.applicationAssignments.removeAll { $0.id == rule.id }
            var errors: [String] = []
            for id in ids {
                guard let state = self.originals[id] else { continue }
                do {
                    try await self.windowManager.restore(id, state: self.safeRestoration(state))
                    self.originals[id] = nil
                    self.tabs.remove(id)
                } catch { errors.append(error.localizedDescription) }
            }
            if !errors.isEmpty {
                self.paused = true
                throw WindowError(message: errors.joined(separator: "\n"))
            }
        }
    }
}
