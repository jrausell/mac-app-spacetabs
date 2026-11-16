import AppKit
import ApplicationServices
import SpaceTabsCore

extension AppModel {
    /// Cheap environment check only. It never enumerates windows unless the
    /// permission actually changes from denied to granted.
    func checkEnvironment() {
        updateDisplayAvailability()
        if let screen {
            let frame = layoutVisibleFrame(on: screen)
            if let previous = lastVisibleFrame, previous != frame, !managementSuspended, !terminating {
                layoutPreferenceChanged()
            }
            if !managementSuspended || lastVisibleFrame == nil { lastVisibleFrame = frame }
        }
        let wasTrusted = trusted
        trusted = PermissionService.trusted
        if !trusted {
            hasCompletedDiscovery = false
            hasCompletedFullDiscovery = false
        }
        if !trusted && !demo && !originals.isEmpty && !paused {
            suspendForDesktopChange(
                L10n.tr("Accessibility access was revoked. Grant access to resume or release windows."))
        }
        if trusted != wasTrusted { layoutChanged() }
        if trusted && !wasTrusted {
            queueInitialDiscovery()
            scheduleRefresh()
        }
    }

    private func queueInitialDiscovery() {
        let autoLayout = linkedProfile?.layout
        var savedBundles = Set(pendingTabs.map { $0.identity.bundleID })
        savedBundles.formUnion(applicationAssignments.map(\.bundleID))
        savedBundles.formUnion(autoLayout?.tabs.map { $0.identity.bundleID } ?? [])
        savedBundles.formUnion(autoLayout?.applicationAssignments.map(\.bundleID) ?? [])
        savedBundles.formUnion(discoveryBundles?() ?? [])
        let running = Dictionary(
            uniqueKeysWithValues: NSWorkspace.shared.runningApplications
                .filter { !$0.isTerminated && $0.processIdentifier != ProcessInfo.processInfo.processIdentifier }
                .map { ($0.processIdentifier, $0.bundleIdentifier ?? "") })
        if let processes = WindowDiscoveryPlan.initialProcesses(savedBundleIDs: savedBundles, running: running) {
            for pid in processes { refreshRequests.requestDiscovery(pid: pid) }
            if processes.isEmpty { hasCompletedDiscovery = true }
        } else {
            refreshRequests.requestDiscovery()
        }
    }

    func startInitialDiscovery() {
        if let discoveryOwner {
            discoveryOwner.refresh()
            return
        }
        checkEnvironment()
        guard trusted, !demo, !terminating, !refreshInFlight, !hasCompletedDiscovery else { return }
        queueInitialDiscovery()
        refreshTask?.cancel()
        refreshTask = nil
        flushRefreshRequests()
    }

    /// Explicit refresh of all running applications.
    func refresh() {
        if sendToManager(.refreshWindows) { return }
        checkEnvironment()
        guard trusted, !demo, !terminating else { return }
        Task {
            await windowManager.resetAccessibilityRetries()
            refreshRequests.requestDiscovery()
            scheduleRefresh()
        }
    }

    func applicationChanged(pid: Int32, activated: Bool = false) {
        guard pid != ProcessInfo.processInfo.processIdentifier, !demo, !terminating else { return }
        if !activated {
            scheduleAssignedLaunchDiscovery(pid: pid)
            refreshRequests.requestDiscovery(pid: pid)
        }
        if activated && !busy && !tabSelectionRunner.isPending {
            noteUserInteraction()
            refreshRequests.requestFocus(pid: pid)
        }
        scheduleRefresh()
    }

    func accessibilityChanged(pid: Int32, notification: String) {
        guard pid != ProcessInfo.processInfo.processIdentifier, !demo, !terminating else { return }
        switch notification {
        case kAXTitleChangedNotification:
            refreshRequests.request(.titleChanged, pid: pid)
        case kAXFocusedWindowChangedNotification, kAXWindowMiniaturizedNotification,
            kAXWindowDeminiaturizedNotification:
            // Our own minimize/focus commands must not start a discovery loop.
            guard !busy else { return }
            refreshRequests.requestFocus(pid: pid)
        case kAXWindowCreatedNotification:
            refreshRequests.request(.created, pid: pid)
        case kAXUIElementDestroyedNotification:
            refreshRequests.request(.destroyed, pid: pid)
        default: return
        }
        scheduleRefresh()
    }

    func scheduleRefresh() {
        if let discoveryOwner {
            if let batch = refreshRequests.take() {
                if batch.fullDiscovery {
                    discoveryOwner.refreshRequests.requestDiscovery()
                } else {
                    for pid in batch.processIDs { discoveryOwner.refreshRequests.requestDiscovery(pid: pid) }
                }
                if let pid = batch.focusPID { discoveryOwner.refreshRequests.requestFocus(pid: pid) }
                discoveryOwner.scheduleRefresh()
            }
            return
        }
        guard !refreshRequests.isEmpty, refreshTask == nil, !busy, !refreshInFlight, !demo, !terminating, trusted else {
            return
        }
        let elapsed = lastDiscovery.map { $0.duration(to: .now) } ?? .seconds(1)
        let delay = max(.milliseconds(200), .seconds(1) - elapsed)
        refreshTask = Task { [weak self] in
            do { try await Task.sleep(for: delay) } catch { return }
            guard let self else { return }
            refreshTask = nil
            flushRefreshRequests()
        }
    }

    private func flushRefreshRequests() {
        guard !busy, !refreshInFlight, !demo, !terminating, trusted, let batch = refreshRequests.take() else { return }
        refreshInFlight = true
        let needsDiscovery = batch.needsDiscovery
        scanning = needsDiscovery
        let savedBundles = Set(pendingTabs.map { $0.identity.bundleID } + applicationAssignments.map(\.bundleID)).union(
            discoveryBundles?() ?? [])
        let apps =
            needsDiscovery
            ? NSWorkspace.shared.runningApplications.filter { app in
                app.processIdentifier != ProcessInfo.processInfo.processIdentifier
                    && app.bundleIdentifier != SettingsHost.helperID && !app.isTerminated
                    && (app.activationPolicy == .regular || batch.processIDs.contains(app.processIdentifier)
                        || savedBundles.contains(app.bundleIdentifier ?? "")
                        || windows.contains(where: { $0.pid == app.processIdentifier }))
            }.map {
                ApplicationDescriptor(
                    pid: $0.processIdentifier, name: $0.localizedName ?? L10n.tr("App"),
                    bundleID: $0.bundleIdentifier ?? "")
            } : []
        scanTask = Task {
            if needsDiscovery {
                lastDiscovery = .now
                var result = await windowManager.scan(apps: apps, only: batch.fullDiscovery ? nil : batch.processIDs)
                result.visibleWindows = await WindowServerCatalog().visibleWindows()
                discoveryPublished?(result, batch.fullDiscovery)
                // A discovery can finish while the user is switching a known tab.
                // Commit structural changes after that transaction, not during it.
                while busy && !terminating {
                    do { try await Task.sleep(for: .milliseconds(20)) } catch { break }
                }
                if !terminating { applyDiscovery(result) }
                if batch.fullDiscovery && trusted { hasCompletedFullDiscovery = true }
            } else {
                let focused = batch.focusPID != nil ? await windowManager.focusedManagedID() : nil
                scanning = false
                if !terminating {
                    adoptFocus(focused)
                    focusPublished?(focused)
                }
            }
            scanning = false
            refreshInFlight = false
            scheduleRefresh()
            if !applyAutomaticProfileIfReady() {
                restoreSavedSession(automatically: true)
                applyApplicationAssignments()
            }
            if needsDiscovery {
                for app in apps where batch.fullDiscovery || batch.processIDs.contains(app.pid) {
                    scheduleAssignedLaunchDiscovery(pid: app.pid)
                }
            }
        }
    }

    func applyDiscovery(_ result: ScanResult) {
        // Do not label an interrupted/unauthorized search as zero matches.
        trusted = PermissionService.trusted
        hasCompletedDiscovery = trusted
        retainUnavailableAssignments(Set(result.removed))
        // A user can adopt a dragged window while a slow, unrelated discovery
        // is still running. An older snapshot must not discard that adoption.
        let scannedIDs = Set(result.windows.map(\.id))
        let retained = windows.filter {
            !scannedIDs.contains($0.id) && !result.removed.contains($0.id) && tabs.zone(of: $0.id) != nil
        }
        let nextWindows = result.windows + retained
        if windows != nextWindows { windows = nextWindows }
        if warnings != result.warnings { warnings = result.warnings }
        if accessibilityNotices != result.notices { accessibilityNotices = result.notices }
        for window in windows where titles[window.id] != window.label { titles[window.id] = window.label }
        var replacementZones = Set<Zone>()
        var removedManaged = false
        for id in result.removed {
            applicationAssignmentAttempts[id] = nil
            for zone in Zone.allCases where tabs.selected[zone] == id { replacementZones.insert(zone) }
            if originals[id] != nil { removedManaged = true }
            tabs.remove(id)
            titles[id] = nil
            originals[id] = nil
        }
        scanning = false
        guard !terminating else { return }
        if !replacementZones.isEmpty && !managementSuspended {
            perform {
                var frames: [UUID: CGRect] = [:]
                for zone in replacementZones {
                    if let id = self.tabs.selected[zone] { frames[id] = try self.targetFrame(zone) }
                }
                try await self.windowManager.applyLayout(
                    frames: frames,
                    selected: Zone.allCases.filter { replacementZones.contains($0) }.compactMap {
                        self.tabs.selected[$0]
                    })
            }
        } else {
            adoptFocus(result.focused)
        }
        if removedManaged { saveLayout() }
    }

    func adoptFocus(_ id: UUID?) {
        guard !busy, !tabSelectionRunner.isPending, !managementSuspended, let id, let zone = tabs.zone(of: id),
            let window = windows.first(where: { $0.id == id }),
            NSWorkspace.shared.frontmostApplication?.processIdentifier == window.pid
        else { return }
        activeZone = zone
        // Cmd-Tab and clicks already chose the window. Reflect that choice
        // without moving, resizing, raising or activating any window again.
        if tabs.selected[zone] != id {
            userChoseWindow(in: zone)
            tabs.select(id, in: zone)
            saveLayout()
        }
    }
}
