import Foundation

public struct WorkspaceProfile: Codable, Equatable, Sendable, Identifiable {
    public var id: UUID
    public var name: String
    public var layout: PersistedLayout
    public var zoneNames: [Zone: String]
    public var openAssignedApps = false
    public init(
        id: UUID = UUID(), name: String, layout: PersistedLayout, zoneNames: [Zone: String],
        openAssignedApps: Bool = false
    ) {
        self.id = id
        self.name = name
        self.layout = layout
        self.zoneNames = zoneNames
        self.openAssignedApps = openAssignedApps
    }
    private enum CodingKeys: String, CodingKey { case id, name, layout, zoneNames, openAssignedApps }
    public init(from decoder: any Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        id = try values.decode(UUID.self, forKey: .id)
        name = try values.decode(String.self, forKey: .name)
        layout = try values.decode(PersistedLayout.self, forKey: .layout)
        zoneNames = try values.decode([Zone: String].self, forKey: .zoneNames)
        openAssignedApps = try values.decodeIfPresent(Bool.self, forKey: .openAssignedApps) ?? false
    }
    public func closedAssignedApps(runningPaths: Set<String>, automatically: Bool = false) -> [ApplicationAssignment] {
        guard openAssignedApps, !automatically else { return [] }
        var seen = Set<String>()
        return layout.applicationAssignments.filter {
            !runningPaths.contains($0.id) && seen.insert($0.id).inserted
        }
    }
}

public struct ProfileResolution: Equatable, Sendable {
    public var tabs: TabManager
    public var matches: [UUID: UUID]
    public var pending: [SavedTab]
}

extension WorkspaceProfile {
    /// Match documents/windows uniquely; never launch apps or infer a window
    /// from only an app name. Unlisted windows keep their existing membership.
    public func resolve(tabs current: TabManager, windows: [WindowSnapshot], applicationURLs: [Int32: URL])
        -> ProfileResolution
    {
        var next = current
        next.adapt(to: layout.template)
        for window in windows where current.zone(of: window.id) != nil {
            if let rule = ApplicationAssignmentResolver.assignment(
                for: window, applicationURL: applicationURLs[window.pid], assignments: layout.applicationAssignments),
                next.zone(of: window.id) != rule.zone
            {
                next.assign(window.id, to: rule.zone, selecting: false)
            }
        }
        let matches = WindowReconciler.matches(saved: layout.tabs, windows: windows.filter(\.compatible))
        for saved in layout.tabs {
            if let id = matches[saved.id], next.zone(of: id) != saved.zone {
                next.assign(id, to: saved.zone, selecting: false)
            }
        }
        for saved in layout.tabs where saved.selected {
            if let id = matches[saved.id] { next.select(id, in: saved.zone) }
        }
        return ProfileResolution(tabs: next, matches: matches, pending: layout.tabs.filter { matches[$0.id] == nil })
    }
}
