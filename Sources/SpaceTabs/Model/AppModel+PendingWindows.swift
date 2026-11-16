import AppKit
import SpaceTabsCore

extension AppModel {
    private func reportPendingWindow(_ id: UUID, _ text: String) {
        message = text
        pendingWindowMessages[id] = text
    }

    func displayedTabIDs(in zone: Zone) -> [UUID] {
        SavedTabManifest.orderedIDs(
            live: tabs.windows[zone, default: []],
            pending: isLoadingTabs(in: zone) ? [] : visiblePendingTabs(in: zone).map(\.id), order: savedTabOrder)
    }

    func visiblePendingTabs(in zone: Zone) -> [SavedTab] {
        let live = Set(tabs.windows.values.flatMap { $0 })
        let pending = Dictionary(
            uniqueKeysWithValues: pendingTabs.filter { $0.zone == zone && !live.contains($0.id) }.map { ($0.id, $0) })
        let order = savedTabOrder + pendingTabs.map(\.id)
        var seen = Set<UUID>()
        let ordered = order.compactMap { id in seen.insert(id).inserted ? pending[id] : nil }
        let managed = Set(tabs.windows[zone, default: []])
        return PendingAssignmentPresentation.representatives(
            pending: ordered, live: windows.filter { managed.contains($0.id) }, zone: zone)
    }

    func pendingAppName(_ saved: SavedTab) -> String {
        installedApplications.first(where: { $0.bundleID == saved.identity.bundleID })?.name
            ?? windows.first(where: { $0.identity.bundleID == saved.identity.bundleID })?.appName
            ?? NSWorkspace.shared.runningApplications.first(where: { $0.bundleIdentifier == saved.identity.bundleID })?
            .localizedName
            ?? saved.identity.bundleID
    }

    func forgetPendingApp(_ bundleID: String, in zone: Zone) {
        if sendToManager(.forgetPendingApp(bundleID, zone)) { return }
        guard !busy, !terminating, !configurationBlocked else { return }
        let old = pendingTabs
        let ids = Set(old.filter { $0.zone == zone && $0.identity.bundleID == bundleID }.map(\.id))
        guard !ids.isEmpty else { return }
        pendingTabs.removeAll { ids.contains($0.id) }
        do {
            try checkpoint(tabs: tabs, originals: originals)
            for id in ids {
                pendingWindowChoices[id] = nil
                pendingWindowMessages[id] = nil
                pendingReopenTasks.removeValue(forKey: id)?.cancel()
                pendingReopens[id] = nil
                pendingReopenTokens[id] = nil
                reopeningPendingTabs.remove(id)
            }
            layoutChanged()
        } catch {
            pendingTabs = old
            DiagnosticLog.shared.failure(error, operation: #function)
            message = error.localizedDescription
        }
    }

    func cancelPendingReopens() {
        for task in pendingReopenTasks.values { task.cancel() }
        pendingReopenTasks.removeAll()
        pendingReopens.removeAll()
        pendingWindowChoices.removeAll()
        pendingWindowMessages.removeAll()
        pendingReopenTokens.removeAll()
        reopeningPendingTabs.removeAll()
    }

    func forgetPendingTab(_ id: UUID) {
        if sendToManager(.forgetPendingTab(id)) { return }
        guard !busy, !terminating, !configurationBlocked, pendingTabs.contains(where: { $0.id == id }) else { return }
        let old = pendingTabs
        pendingTabs.removeAll { $0.id == id }
        do {
            try checkpoint(tabs: tabs, originals: originals)
            pendingReopenTasks.removeValue(forKey: id)?.cancel()
            pendingReopens[id] = nil
            pendingWindowChoices[id] = nil
            pendingWindowMessages[id] = nil
            pendingReopenTokens[id] = nil
            reopeningPendingTabs.remove(id)
            layoutChanged()
        } catch {
            pendingTabs = old
            DiagnosticLog.shared.failure(error, operation: #function)
            message = error.localizedDescription
        }
    }

    func reopenPendingTab(_ id: UUID) {
        if sendToManager(.reopenPendingTab(id)) { return }
        guard canApplyProfile, !displayUnavailable, let saved = pendingTabs.first(where: { $0.id == id }),
            !reopeningPendingTabs.contains(id),
            !pendingTabs.contains(where: {
                $0.identity.bundleID == saved.identity.bundleID && reopeningPendingTabs.contains($0.id)
            })
        else { return }
        pendingWindowChoices[id] = nil
        pendingWindowMessages[id] = nil
        let running = NSWorkspace.shared.runningApplications.filter {
            $0.bundleIdentifier == saved.identity.bundleID && !$0.isTerminated
        }
        let apps = installedApplications.filter { $0.bundleID == saved.identity.bundleID }
        let resolvedURL =
            running.compactMap(\.bundleURL).first
            ?? (apps.count == 1 ? apps.first?.url : nil)
            ?? NSWorkspace.shared.urlForApplication(withBundleIdentifier: saved.identity.bundleID)
        let app = resolvedURL.map {
            InstalledApplication(url: $0, name: pendingAppName(saved), bundleID: saved.identity.bundleID)
        }
        guard !running.isEmpty || app != nil else {
            reportPendingWindow(id, L10n.tr("Select the saved app in Settings → Apps before reopening this tab."))
            return
        }
        let revision = desktopRevision
        let token = UUID()
        pendingReopenTokens[id] = token
        reopeningPendingTabs.insert(id)
        pendingReopenTasks[id] = Task { [weak self] in
            guard let self else { return }
            defer {
                if pendingReopenTokens[id] == token {
                    pendingReopenTasks[id] = nil
                    pendingReopens[id] = nil
                    pendingReopenTokens[id] = nil
                    reopeningPendingTabs.remove(id)
                }
            }
            // Request fresh AX state only for this running app. Await the
            // existing discovery pipeline instead of starting a second scan.
            guard canApplyProfile, !displayUnavailable, !refreshInFlight else {
                reportPendingWindow(id, L10n.tr("Wait for the current operation to finish."))
                return
            }
            await windowManager.resetAccessibilityRetries(for: Set(running.map(\.processIdentifier)))
            guard !Task.isCancelled, desktopRevision == revision else { return }
            for application in running { refreshRequests.requestDiscovery(pid: application.processIdentifier) }
            if !running.isEmpty {
                scheduleRefresh()
                await (discoveryOwner ?? self).refreshTask?.value
                await (discoveryOwner ?? self).scanTask?.value
                if let discoveryOwner {
                    windows = discoveryOwner.windows
                    hasCompletedDiscovery = discoveryOwner.hasCompletedDiscovery
                }
                await operationTask?.value
            }
            guard !Task.isCancelled, desktopRevision == revision, !managementSuspended, !terminating,
                pendingTabs.contains(where: { $0.id == id })
            else { return }
            let visible = await WindowServerCatalog().visibleWindows()
            guard !Task.isCancelled, desktopRevision == revision, !managementSuspended else { return }
            let candidates = PendingAppSynchronization.candidates(
                bundleID: saved.identity.bundleID, windows: windows.filter(eligibleWindow),
                assigned: Set(tabs.windows.values.flatMap { $0 }), visible: visible)
            if candidates.count == 1, let candidate = candidates.first {
                synchronizePendingWindow(id, with: candidate.id)
                return
            }
            if candidates.count > 1 {
                pendingWindowChoices[id] = candidates.map(\.id)
                return
            }
            // Do not open duplicate windows when an app already has windows on
            // another desktop or windows whose visibility cannot be verified.
            if windows.contains(where: { $0.identity.bundleID == saved.identity.bundleID }) {
                reportPendingWindow(
                    id,
                    L10n.tr(
                        "No unassigned window is available on this desktop. Switch to the app's desktop or release its assigned window first."
                    ))
                return
            }
            guard let app else {
                reportPendingWindow(id, L10n.tr("Select the saved app in Settings → Apps before reopening this tab."))
                return
            }
            // Capture all desktop windows on the existing dedicated executor.
            let numbers = Set(await WindowServerCatalog().windows().map(\.number))
            guard !Task.isCancelled, desktopRevision == revision, !managementSuspended, !terminating,
                pendingTabs.contains(where: { $0.id == id })
            else { return }
            guard !numbers.isEmpty else {
                reportPendingWindow(
                    id, L10n.tr("Could not identify existing windows. Try reopening the saved tab again."))
                return
            }
            pendingReopens[id] = PendingWindowReopen(existingWindowNumbers: numbers)
            launchApplication(app, activates: false)
            do { try await Task.sleep(for: .seconds(15)) } catch { return }
            guard pendingTabs.contains(where: { $0.id == id }), !managementSuspended else { return }
            reportPendingWindow(
                id,
                L10n.tr(
                    "The app did not provide a unique matching window. Open the saved document or assign its window manually."
                ))
        }
    }

    func dismissPendingWindowChoice(_ id: UUID) {
        if sendToManager(.dismissPendingWindowChoice(id)) { return }
        pendingWindowChoices[id] = nil
        pendingWindowMessages[id] = nil
    }

    func synchronizePendingWindow(_ savedID: UUID, with windowID: UUID) {
        if sendToManager(.synchronizePendingWindow(savedID, windowID)) { return }
        guard let saved = pendingTabs.first(where: { $0.id == savedID }) else { return }
        guard canApplyProfile, !displayUnavailable else {
            reportPendingWindow(savedID, L10n.tr("Wait for the current operation to finish."))
            return
        }
        let token = UUID()
        let revision = desktopRevision
        pendingReopenTasks.removeValue(forKey: savedID)?.cancel()
        pendingReopenTokens[savedID] = token
        reopeningPendingTabs.insert(savedID)
        pendingReopenTasks[savedID] = Task { [weak self] in
            guard let self else { return }
            defer {
                if pendingReopenTokens[savedID] == token {
                    pendingReopenTokens[savedID] = nil
                    pendingReopenTasks[savedID] = nil
                    pendingReopens[savedID] = nil
                    reopeningPendingTabs.remove(savedID)
                }
            }
            let visible = await WindowServerCatalog().visibleWindows()
            guard !Task.isCancelled, desktopRevision == revision, canApplyProfile, !displayUnavailable,
                pendingTabs.contains(where: { $0.id == savedID })
            else { return }
            let candidates = PendingAppSynchronization.candidates(
                bundleID: saved.identity.bundleID, windows: windows.filter(eligibleWindow),
                assigned: Set(tabs.windows.values.flatMap { $0 }), visible: visible)
            guard candidates.contains(where: { $0.id == windowID }) else {
                pendingWindowChoices[savedID] = nil
                reportPendingWindow(
                    savedID, L10n.tr("That window is no longer available here. Synchronize the saved app again."))
                return
            }
            pendingWindowChoices[savedID] = nil
            pendingWindowMessages[savedID] = nil
            assign(windowID, to: saved.zone, requestFocus: false, replacingPending: savedID)
            await operationTask?.value
            if !Task.isCancelled, desktopRevision == revision, pendingTabs.contains(where: { $0.id == savedID }) {
                reportPendingWindow(
                    savedID,
                    message
                        ?? L10n.tr(
                            "The window could not be synchronized. Try again after the current operation finishes."))
            }
        }
    }

    func explicitPendingMatches() -> [UUID: UUID] {
        guard !managementSuspended, !terminating else { return [:] }
        let assigned = Set(tabs.windows.values.flatMap { $0 })
        var result: [UUID: UUID] = [:]
        for saved in pendingTabs {
            if let request = pendingReopens[saved.id],
                let id = request.candidate(for: saved, windows: windows.filter(eligibleWindow), assigned: assigned)
            {
                result[saved.id] = id
            }
        }
        let counts = result.values.reduce(into: [UUID: Int]()) { $0[$1, default: 0] += 1 }
        return result.filter { counts[$0.value] == 1 }
    }
}
