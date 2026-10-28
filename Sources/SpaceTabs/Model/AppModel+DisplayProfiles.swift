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
        guard let id = preferences.displayProfiles[displayConfigurationKey] else { return nil }
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
    func physicalDisplaysChanged() {
        displayProfileTask?.cancel()
        guard linkedProfile != nil, trusted, !paused, !demo, !terminating else {
            suspendForDesktopChange(L10n.tr("The display setup changed. Check the selected display and select Resume."))
            return
        }
        noteUserInteraction()
        reflowTask?.cancel()
        desktopRevision += 1
        spaceTransitioning = true
        layoutChanged()
        displayProfileTask = Task { [weak self] in
            do { try await Task.sleep(for: .milliseconds(900)) } catch { return }
            guard let self, !terminating else { return }
            displayProfileTask = nil
            spaceTransitioning = spaceChangeTask != nil
            pendingAutomaticProfile = linkedProfile?.id
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
