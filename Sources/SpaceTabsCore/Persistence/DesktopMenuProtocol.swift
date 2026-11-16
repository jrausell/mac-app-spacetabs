import Darwin
import Foundation

public enum DesktopMenuAction: Codable, Equatable, Sendable {
    case newWorkspace, show, restore, showTabs
    case openWorkspace(UUID)
    case openProfile(UUID)
}

public struct DesktopMenuWorkspace: Codable, Equatable, Sendable, Identifiable {
    public let id: UUID
    public let name: String
    public let profileID: UUID?
    public let displayID: String
    public let isOpen: Bool
    public let isHere: Bool
    public let canRestore: Bool
    public init(
        id: UUID, name: String, profileID: UUID?, displayID: String, isOpen: Bool, isHere: Bool, canRestore: Bool
    ) {
        self.id = id
        self.name = name
        self.profileID = profileID
        self.displayID = displayID
        self.isOpen = isOpen
        self.isHere = isHere
        self.canRestore = canRestore
    }
}

public struct DesktopMenuProfile: Codable, Equatable, Sendable, Identifiable {
    public let id: UUID
    public let name: String
    public init(id: UUID, name: String) {
        self.id = id
        self.name = name
    }
}

/// Minimal read-only menu data. No app paths, document titles, or commands on disk.
public struct DesktopMenuSnapshot: Codable, Equatable, Sendable {
    public var version = 1
    public var token: UUID
    public var context: UUID
    public var managerPID: Int32
    public var launchDate: Date?
    public var language: AppLanguage
    public var ready: Bool
    public var workspaces: [DesktopMenuWorkspace]
    public var profiles: [DesktopMenuProfile]
    public init(
        token: UUID, context: UUID, managerPID: Int32, launchDate: Date?, language: AppLanguage,
        ready: Bool, workspaces: [DesktopMenuWorkspace], profiles: [DesktopMenuProfile]
    ) {
        self.token = token
        self.context = context
        self.managerPID = managerPID
        self.launchDate = launchDate
        self.language = language
        self.ready = ready
        self.workspaces = workspaces
        self.profiles = profiles
    }
    public var isValid: Bool {
        version == 1 && managerPID >= 0 && workspaces.count <= 16 && profiles.count <= PreferenceLimits.profiles
            && Set(workspaces.map(\.id)).count == workspaces.count && Set(profiles.map(\.id)).count == profiles.count
            && workspaces.allSatisfy {
                !$0.name.isEmpty && $0.name.count <= PreferenceLimits.profileNameCharacters && $0.displayID.count <= 256
            }
            && profiles.allSatisfy { !$0.name.isEmpty && $0.name.count <= PreferenceLimits.profileNameCharacters }
    }
    public func workspace(on displayID: String) -> DesktopMenuWorkspace? {
        let matches = workspaces.filter { $0.displayID == displayID && $0.isHere && $0.isOpen }
        return matches.count == 1 ? matches.first : nil
    }
}

public struct DesktopMenuRequest: Codable, Equatable, Sendable {
    public var version = 1
    public var token: UUID
    public var context: UUID
    public var nonce: UUID
    public var created: Date
    public var displayID: String
    public var action: DesktopMenuAction
    public init(
        token: UUID, context: UUID, nonce: UUID = UUID(), created: Date = .now,
        displayID: String, action: DesktopMenuAction
    ) {
        self.token = token
        self.context = context
        self.nonce = nonce
        self.created = created
        self.displayID = displayID
        self.action = action
    }
    public func url() -> URL? {
        guard let data = try? JSONEncoder().encode(self), data.count <= 4096 else { return nil }
        var parts = URLComponents()
        parts.scheme = SpaceTabsIdentity.desktopMenuScheme
        parts.host = "desktop-menu"
        parts.path = "/v1"
        parts.queryItems = [URLQueryItem(name: "request", value: data.base64EncodedString())]
        return parts.url
    }
    public static func decode(_ url: URL) -> Self? {
        guard url.absoluteString.utf8.count <= 8192,
            let parts = URLComponents(url: url, resolvingAgainstBaseURL: false),
            parts.scheme == SpaceTabsIdentity.desktopMenuScheme, parts.host == "desktop-menu", parts.path == "/v1",
            parts.user == nil, parts.password == nil, parts.port == nil, parts.fragment == nil,
            let items = parts.queryItems, items.count == 1, items[0].name == "request",
            let value = items[0].value, let data = Data(base64Encoded: value), data.count <= 4096,
            let request = try? JSONDecoder().decode(Self.self, from: data), request.version == 1,
            !request.displayID.isEmpty, request.displayID.utf8.count <= 256,
            request.created.timeIntervalSince1970.isFinite
        else { return nil }
        return request
    }
}

/// A private per-run capability protects this narrow URL surface from arbitrary
/// web links. Context rotation rejects a menu opened before a desktop change.
/// It is not a code-signature-authenticated channel like Settings IPC.
public struct DesktopMenuAuthorization: Sendable {
    public private(set) var token = UUID()
    public private(set) var context = UUID()
    private var used: [(UUID, Date)] = []
    public init() {}
    public mutating func invalidateContext() {
        context = UUID()
        used.removeAll()
    }
    public mutating func accept(_ request: DesktopMenuRequest, now: Date = .now) -> Bool {
        let age = now.timeIntervalSince(request.created)
        used.removeAll { now.timeIntervalSince($0.1) > 30 }
        guard used.count < 128, request.version == 1, request.token == token, request.context == context,
            age.isFinite, (-2...30).contains(age), !used.contains(where: { $0.0 == request.nonce }),
            !request.displayID.isEmpty, request.displayID.utf8.count <= 256
        else { return false }
        used.append((request.nonce, request.created))
        return true
    }
}

public enum DesktopMenuStorage {
    public static let maximumBytes = 64 * 1024
    /// getpwuid_r returns the actual user's home, including in a sandboxed extension.
    /// The extension receives read-only access to only the dedicated menu directory.
    public static var userHome: URL? {
        var record = passwd()
        var result: UnsafeMutablePointer<passwd>?
        var buffer = [CChar](repeating: 0, count: 16_384)
        return buffer.withUnsafeMutableBufferPointer { bytes in
            guard getpwuid_r(getuid(), &record, bytes.baseAddress!, bytes.count, &result) == 0,
                result != nil, let path = record.pw_dir
            else { return nil }
            return URL(fileURLWithPath: String(cString: path), isDirectory: true)
        }
    }
    public static var directory: URL? {
        userHome?.appendingPathComponent("Library/Application Support/SpaceTabs/Finder", isDirectory: true)
    }
    public static var url: URL? { directory?.appendingPathComponent("menu.json") }
    public static var desktop: URL? { userHome?.appendingPathComponent("Desktop", isDirectory: true) }
    public static func load(at url: URL) throws -> DesktopMenuSnapshot? {
        guard let data = try LocalConfigurationFile.read(at: url) else { return nil }
        guard data.count <= maximumBytes else { return nil }
        let snapshot = try JSONDecoder().decode(DesktopMenuSnapshot.self, from: data)
        return snapshot.isValid ? snapshot : nil
    }
    public static func save(_ snapshot: DesktopMenuSnapshot, at url: URL) throws {
        guard snapshot.isValid else { throw ConfigurationError(L10n.tr("Invalid desktop menu data.")) }
        let data = try JSONEncoder().encode(snapshot)
        guard data.count <= maximumBytes else { throw ConfigurationError(L10n.tr("Invalid desktop menu data.")) }
        try LocalConfigurationFile.write(data, to: url)
    }
}
