import Foundation

public struct UserPreferencesStore: Sendable {
    public static let maximumBytes = 512 * 1024
    public static var standard: UserPreferencesStore {
        UserPreferencesStore(
            url: PersistenceStore.standard.url.deletingLastPathComponent().appendingPathComponent("preferences.json"))
    }
    public let url: URL
    public init(url: URL) { self.url = url }
    public func load() throws -> UserPreferences {
        guard let data = try LocalConfigurationFile.read(at: url) else { return UserPreferences() }
        guard data.count <= Self.maximumBytes else {
            throw ConfigurationError(L10n.tr("Preferences exceed the size limit."))
        }
        let value = try JSONDecoder().decode(UserPreferences.self, from: data)
        try value.validate()
        return value
    }
    public func save(_ value: UserPreferences) throws {
        try value.validate()
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        let data = try encoder.encode(value)
        guard data.count <= Self.maximumBytes else {
            throw ConfigurationError(L10n.tr("Preferences exceed the size limit."))
        }
        try LocalConfigurationFile.write(data, to: url)
    }
}
