import Foundation

/// A workspace owns its saved slots independently of reusable profile templates.
/// Native desktop membership is deliberately session-only: macOS exposes no stable public Space ID.
public struct WorkspaceRecord: Codable, Equatable, Sendable, Identifiable {
    public var id: UUID
    public var name: String
    public var profileID: UUID?
    public var displayID: String
    public var layout: PersistedLayout
    public var zoneNames: [Zone: String]

    public init(
        id: UUID = UUID(), name: String, profileID: UUID? = nil, displayID: String,
        layout: PersistedLayout = PersistedLayout(), zoneNames: [Zone: String] = [:]
    ) {
        self.id = id
        self.name = name
        self.profileID = profileID
        self.displayID = displayID
        self.layout = layout
        self.zoneNames = zoneNames
    }
}

public struct WorkspaceDocument: Codable, Equatable, Sendable {
    public var version = 1
    public var records: [WorkspaceRecord]
    public init(records: [WorkspaceRecord] = []) { self.records = records }

    public func validate() throws {
        guard version == 1, records.count <= 16, Set(records.map(\.id)).count == records.count,
            Set(records.compactMap(\.profileID)).count == records.compactMap(\.profileID).count
        else {
            throw ConfigurationError(L10n.tr("Invalid workspace registry."))
        }
        for record in records {
            guard !record.name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
                record.name.count <= PreferenceLimits.profileNameCharacters, record.displayID.count <= 256,
                record.zoneNames.values.allSatisfy({ $0.count <= PreferenceLimits.zoneNameCharacters })
            else {
                throw ConfigurationError(L10n.tr("Invalid workspace metadata."))
            }
            try record.layout.validate()
        }
    }
}

public struct WorkspaceStore: Sendable {
    public let url: URL
    public init(url: URL) { self.url = url }
    public static var standard: Self {
        Self(url: PersistenceStore.standard.url.deletingLastPathComponent().appendingPathComponent("workspaces.json"))
    }
    public func load() throws -> WorkspaceDocument? {
        guard let data = try LocalConfigurationFile.read(at: url) else { return nil }
        let document = try JSONDecoder().decode(WorkspaceDocument.self, from: data)
        try document.validate()
        return document
    }
    public func save(_ document: WorkspaceDocument) throws {
        try document.validate()
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        try LocalConfigurationFile.write(encoder.encode(document), to: url)
    }
}
