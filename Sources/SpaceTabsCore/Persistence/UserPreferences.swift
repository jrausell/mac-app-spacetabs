import Foundation

public struct UserPreferences: Codable, Equatable, Sendable {
    public var language: AppLanguage = .automatic
    public var controlRightDrag = true
    public var displayProfiles: [String: UUID] = [:]
    public var shortcuts: [UInt32: ShortcutBinding] = [:]
    public var zoneNames: [Zone: String] = [:]
    public var profiles: [WorkspaceProfile] = []
    public init() {}
    private enum CodingKeys: String, CodingKey {
        case language, controlRightDrag, displayProfiles, shortcuts, zoneNames, profiles
    }
    public init(from decoder: any Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        language = try values.decodeIfPresent(AppLanguage.self, forKey: .language) ?? .automatic
        displayProfiles = try values.decodeIfPresent([String: UUID].self, forKey: .displayProfiles) ?? [:]
        controlRightDrag = try values.decodeIfPresent(Bool.self, forKey: .controlRightDrag) ?? true
        shortcuts = try values.decodeIfPresent([UInt32: ShortcutBinding].self, forKey: .shortcuts) ?? [:]
        zoneNames = try values.decodeIfPresent([Zone: String].self, forKey: .zoneNames) ?? [:]
        profiles = try values.decodeIfPresent([WorkspaceProfile].self, forKey: .profiles) ?? []
    }
    public func validate() throws {
        guard shortcuts.count <= PreferenceLimits.shortcutActions,
            shortcuts.keys.allSatisfy({ (1...UInt32(PreferenceLimits.shortcutActions)).contains($0) }),
            shortcuts.values.allSatisfy(\.isValid),
            Set(shortcuts.values.filter(\.enabled)).count == shortcuts.values.filter(\.enabled).count,
            profiles.count <= PreferenceLimits.profiles, Set(profiles.map(\.id)).count == profiles.count,
            Self.validNames(zoneNames), displayProfiles.count <= PreferenceLimits.displayLinks,
            displayProfiles.keys.allSatisfy({ !$0.isEmpty && $0.utf8.count <= 4096 }),
            displayProfiles.values.allSatisfy({ id in profiles.contains(where: { $0.id == id }) })
        else { throw ConfigurationError(L10n.tr("Invalid preferences.")) }
        for profile in profiles {
            guard !profile.name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
                profile.name.count <= PreferenceLimits.profileNameCharacters, Self.validNames(profile.zoneNames),
                profile.layout.tabs.allSatisfy({
                    $0.original == nil && $0.processID == nil && $0.launchDate == nil
                        && profile.layout.template.zones.contains($0.zone)
                }),
                profile.layout.applicationAssignments.allSatisfy({ profile.layout.template.zones.contains($0.zone) })
            else {
                throw ConfigurationError(L10n.tr("Invalid profile."))
            }
            try profile.layout.validate()
        }
    }
    private static func validNames(_ names: [Zone: String]) -> Bool {
        names.count <= 3
            && names.values.allSatisfy {
                $0.count <= PreferenceLimits.zoneNameCharacters
                    && !$0.unicodeScalars.contains(where: { CharacterSet.controlCharacters.contains($0) })
            }
    }
}
