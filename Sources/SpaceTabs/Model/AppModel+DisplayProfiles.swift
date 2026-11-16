import AppKit
import SpaceTabsCore

extension AppModel {
    static func stableDisplayID(_ screen: NSScreen) -> String {
        guard let number = screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber,
            let uuid = CGDisplayCreateUUIDFromDisplayID(number.uint32Value)?.takeRetainedValue()
        else { return screenID(screen) }
        return CFUUIDCreateString(kCFAllocatorDefault, uuid) as String
    }
    var displayConfigurationKey: String {
        NSScreen.screens.map {
            "\(Self.stableDisplayID($0)):\(Int($0.frame.width))x\(Int($0.frame.height))@\(Int($0.frame.minX)),\(Int($0.frame.minY))"
        }.sorted().joined(separator: "|")
    }
    var linkedProfile: WorkspaceProfile? {
        guard workspaceID == nil, let id = preferences.displayProfiles[displayConfigurationKey] else { return nil }
        return preferences.profiles.first { $0.id == id }
    }
    func bindProfile(_ id: UUID, enabled: Bool) {
        if sendToManager(.bindProfile(id, enabled)) { return }
        guard preferences.profiles.contains(where: { $0.id == id }) else { return }
        var value = preferences
        if enabled {
            value.displayProfiles[displayConfigurationKey] = id
        } else if value.displayProfiles[displayConfigurationKey] == id {
            value.displayProfiles[displayConfigurationKey] = nil
        }
        if commitPreferences(value) {
            message =
                enabled
                ? L10n.tr("Profile linked to these displays. It will apply at startup or when they reconnect.")
                : L10n.tr("Automatic profile link removed.")
        }
    }
    func updateDisplayAvailability(displays supplied: [DisplayIdentity]? = nil) {
        let displays =
            supplied
            ?? NSScreen.screens.map {
                DisplayIdentity(runtimeID: Self.screenID($0), stableID: Self.stableDisplayID($0))
            }
        let wasUnavailable = displayUnavailable
        if let id = displaySelection.resolve(selectedScreenID, displays: displays) {
            if appliedScreenID == selectedScreenID { appliedScreenID = id }
            selectedScreenID = id
            displayUnavailable = false
        } else {
            displayUnavailable = true
        }
        guard wasUnavailable != displayUnavailable else { return }
        DiagnosticLog.shared.record(
            "desktop.displayAvailability",
            details: ["available": String(!displayUnavailable), "paused": String(paused)])
        if displayUnavailable {
            noteUserInteraction()
            cancelPendingReopens()
            reflowTask?.cancel()
            message = L10n.tr(
                "The selected display is unavailable. Waiting for it to reconnect, or choose another display.")
        } else {
            if message
                == L10n.tr(
                    "The selected display is unavailable. Waiting for it to reconnect, or choose another display.")
            {
                message = nil
            }
            restartShortcuts()
        }
        layoutChanged()
    }

    func physicalDisplaysChanged(applyLinkedProfile: Bool = true, displays: [DisplayIdentity]? = nil) {
        guard !demo, !terminating else { return }
        let useProfile = applyLinkedProfile || (displayProfileTask != nil && displayTransitionUsesProfile)
        displayTransitionUsesProfile = useProfile
        pendingAutomaticProfile = nil
        cancelPendingReopens()
        displayProfileTask?.cancel()
        // The display debounce now owns the transition. A cancelled Space task
        // must not retain its handle and keep the manager suspended forever.
        spaceChangeTask?.cancel()
        spaceChangeTask = nil
        noteUserInteraction()
        reflowTask?.cancel()
        desktopRevision += 1
        spaceTransitioning = true
        DiagnosticLog.shared.record(
            "desktop.displayTransitionStarted",
            details: ["source": applyLinkedProfile ? "display" : "wake/session", "paused": String(paused)])
        layoutChanged()
        displayProfileTask = Task { [weak self] in
            do { try await Task.sleep(for: .milliseconds(900)) } catch { return }
            guard let self, !Task.isCancelled, !terminating else { return }
            displayProfileTask = nil
            spaceTransitioning = spaceChangeTask != nil
            displayTransitionUsesProfile = false
            updateDisplayAvailability(displays: displays)
            if displays == nil { checkEnvironment() }
            DiagnosticLog.shared.record("desktop.displayTransitionFinished", details: diagnosticContext)
            if useProfile, !paused, trusted { pendingAutomaticProfile = linkedProfile?.id }
            restartShortcuts()
            layoutChanged()
            applyAutomaticProfileIfReady()
        }
    }
    @discardableResult func applyAutomaticProfileIfReady() -> Bool {
        guard let id = pendingAutomaticProfile else { return false }
        guard !paused, !spaceTransitioning, !busy, !scanning, !refreshInFlight, !tabSelectionRunner.isPending,
            trusted, !terminating, !configurationBlocked, !preferencesBlocked
        else { return true }
        pendingAutomaticProfile = nil
        applyProfile(id, automatically: true)
        return busy
    }
}
