import Foundation

/// A saved application destination exists independently of running processes.
public struct ApplicationAssignment: Codable, Equatable, Identifiable, Sendable {
    public let url: URL
    public let name: String
    public let bundleID: String
    public var zone: Zone
    public var id: String { url.path }
    public init(url: URL, name: String, bundleID: String, zone: Zone) {
        self.url = url.resolvingSymlinksInPath().standardizedFileURL
        self.name = name
        self.bundleID = bundleID
        self.zone = zone
    }
}

public enum ApplicationAssignmentResolver {
    public static func candidates(
        windows: [WindowSnapshot], applicationURLs: [Int32: URL],
        assignments: [ApplicationAssignment], assignedZones: [UUID: Zone],
        attempts: [UUID: String]
    ) -> [UUID: ApplicationAssignment] {
        Dictionary(
            uniqueKeysWithValues: windows.compactMap { window in
                guard window.compatible,
                    let rule = assignment(
                        for: window, applicationURL: applicationURLs[window.pid], assignments: assignments),
                    attempts[window.id] != rule.id, assignedZones[window.id] != rule.zone
                else { return nil }
                return (window.id, rule)
            })
    }

    public static func assignment(
        for window: WindowSnapshot, applicationURL: URL?,
        assignments: [ApplicationAssignment]
    ) -> ApplicationAssignment? {
        let candidates = assignments.filter { $0.bundleID == window.identity.bundleID }
        if let applicationURL {
            let path = applicationURL.resolvingSymlinksInPath().standardizedFileURL.path
            return candidates.first { $0.id == path }
        }
        return candidates.count == 1 ? candidates.first : nil
    }
}
