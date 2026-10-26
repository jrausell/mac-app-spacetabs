import Foundation
import SpaceTabsCore

extension AppModel {
    func setLanguage(_ language: AppLanguage) {
        if sendToManager(.language(language)) { return }
        var value = preferences
        value.language = language
        if commitPreferences(value) { layoutChanged() }
    }

    func setRightDrag(_ enabled: Bool) {
        if sendToManager(.rightDrag(enabled)) { return }
        var value = preferences
        value.controlRightDrag = enabled
        if commitPreferences(value) { layoutChanged() }
    }
    func zoneLabel(_ zone: Zone) -> String {
        let name = preferences.zoneNames[zone, default: ""].trimmingCharacters(in: .whitespacesAndNewlines)
        return name.isEmpty ? zone.title : "\(zone.title) · \(name)"
    }
    func loadUserPreferences() {
        do {
            var loaded = try preferencesStore.load()
            loaded.shortcuts = ShortcutManager.migratedBindings(loaded.shortcuts)
            try ShortcutManager.validateBindings(loaded.shortcuts)
            preferences = loaded
            L10n.configure(loaded.language)
        } catch {
            preferencesBlocked = true
            message = L10n.tr("Could not load preferences: \(error.localizedDescription)")
        }
    }
    @discardableResult func commitPreferences(_ value: UserPreferences) -> Bool {
        do {
            guard !preferencesBlocked else {
                throw ConfigurationError(L10n.tr("Repair preferences in Diagnostics before changing them."))
            }
            try ShortcutManager.validateBindings(value.shortcuts)
            try preferencesStore.save(value)
            preferences = value
            return true
        } catch {
            message = L10n.tr("Could not save preferences: \(error.localizedDescription)")
            return false
        }
    }
    func resetUserPreferences() {
        if sendToManager(.resetPreferences) { return }
        guard preferencesBlocked, !busy else { return }
        do {
            let backup = preferencesStore.url.deletingLastPathComponent().appendingPathComponent(
                "preferences.backup-\(UUID()).json")
            if FileManager.default.fileExists(atPath: preferencesStore.url.path) {
                try FileManager.default.copyItem(at: preferencesStore.url, to: backup)
            }
            try preferencesStore.save(UserPreferences())
            preferencesBlocked = false
            preferences = UserPreferences()
            restartShortcuts()
            layoutChanged()
            message = L10n.tr("Preferences reset. A copy of the previous file was kept.")
        } catch { message = error.localizedDescription }
    }
    func setZoneName(_ zone: Zone, name: String) {
        if sendToManager(.zoneName(zone, name)) { return }
        var value = preferences
        value.zoneNames[zone] = name.trimmingCharacters(in: .whitespacesAndNewlines)
        if commitPreferences(value) { layoutChanged() }
    }
    func setShortcut(_ id: UInt32, binding: ShortcutBinding) {
        if sendToManager(.binding(id, binding)) { return }
        guard ShortcutManager.Action(rawValue: id) != nil, binding.isValid else { return }
        guard
            !binding.enabled
                || !ShortcutManager.Action.allCases.contains(where: {
                    $0.rawValue != id && (preferences.shortcuts[$0.rawValue] ?? $0.defaultBinding) == binding
                })
        else {
            message = L10n.tr("This shortcut is already assigned to another SpaceTabs action.")
            return
        }
        var value = preferences
        value.shortcuts[id] = binding
        if commitPreferences(value) { restartShortcuts() }
    }
    func resetShortcutBindings() {
        if sendToManager(.resetBindings) { return }
        var value = preferences
        value.shortcuts = [:]
        if commitPreferences(value) { restartShortcuts() }
    }
}
