import Foundation

public struct PersistenceStore: Sendable {
    public let url: URL
    public init(url: URL) { self.url = url }
    public static var standard: PersistenceStore {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        return PersistenceStore(url: base.appendingPathComponent("SpaceTabs/layout.json"))
    }

    public func load() throws -> PersistedLayout? {
        guard let data = try LocalConfigurationFile.read(at: url) else { return nil }
        let layout = try JSONDecoder().decode(PersistedLayout.self, from: data)
        try validate(layout)
        return layout
    }

    public func save(_ layout: PersistedLayout) throws {
        try validate(layout)
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        let data = try encoder.encode(layout)
        try LocalConfigurationFile.write(data, to: url)
    }

    /// Validate without reading or writing the store's file.
    public func validate(_ layout: PersistedLayout) throws { try layout.validate() }
}
