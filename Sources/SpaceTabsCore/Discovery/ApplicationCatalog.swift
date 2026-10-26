import Foundation

public struct InstalledApplication: Codable, Identifiable, Equatable, Sendable {
    public let url: URL
    public let name: String
    public let bundleID: String
    public var id: String { url.path }
    public init(url: URL, name: String, bundleID: String) {
        self.url = url.resolvingSymlinksInPath().standardizedFileURL
        self.name = name
        self.bundleID = bundleID
    }
}

public struct ApplicationCatalogSnapshot: Equatable, Sendable {
    public let applications: [InstalledApplication]
    public let directories: Set<URL>
}

/// Cataloguing never launches apps or queries Accessibility. Application bundles
/// are leaves, so embedded helpers are not offered as installed applications.
public actor ApplicationCatalog {
    private let roots: [URL]
    private let configurationURL: URL
    private let excludedBundleID: String
    private var customURLs: [URL]?
    public private(set) var scanCount = 0

    public init(roots: [URL], configurationURL: URL, excludedBundleID: String = SpaceTabsIdentity.appBundleID) {
        self.roots = roots.map { $0.resolvingSymlinksInPath().standardizedFileURL }
        self.configurationURL = configurationURL
        self.excludedBundleID = excludedBundleID
    }

    public func scan() throws -> ApplicationCatalogSnapshot {
        try loadCustomURLs()
        scanCount += 1
        let manager = FileManager.default
        var applications: [String: InstalledApplication] = [:]
        var directories = Set<URL>()
        for root in roots {
            var directory: ObjCBool = false
            guard manager.fileExists(atPath: root.path, isDirectory: &directory), directory.boolValue else { continue }
            directories.insert(root)
            guard
                let enumerator = manager.enumerator(
                    at: root, includingPropertiesForKeys: [.isDirectoryKey],
                    options: [.skipsHiddenFiles, .skipsPackageDescendants])
            else { continue }
            for case let url as URL in enumerator {
                if url.pathExtension.lowercased() == "app" {
                    enumerator.skipDescendants()
                    if let app = application(at: url) { applications[app.id] = app }
                } else if (try? url.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) == true {
                    directories.insert(url.resolvingSymlinksInPath().standardizedFileURL)
                }
            }
        }
        for url in customURLs ?? [] {
            // Keep missing external paths in configuration for removable volumes.
            if let app = application(at: url) { applications[app.id] = app }
            if manager.fileExists(atPath: url.deletingLastPathComponent().path) {
                directories.insert(url.deletingLastPathComponent())
            }
        }
        let sorted = applications.values.sorted {
            if $0.name != $1.name { return $0.name.localizedStandardCompare($1.name) == .orderedAscending }
            return $0.id < $1.id
        }
        return ApplicationCatalogSnapshot(applications: sorted, directories: directories)
    }

    public func add(_ urls: [URL]) throws -> ApplicationCatalogSnapshot {
        try loadCustomURLs()
        let canonical = urls.map { $0.resolvingSymlinksInPath().standardizedFileURL }
        guard canonical.allSatisfy({ application(at: $0) != nil }) else {
            throw ConfigurationError(L10n.tr("Select valid .app bundles other than SpaceTabs."))
        }
        let paths = Set((customURLs ?? []) + canonical).sorted { $0.path < $1.path }
        let data = try JSONEncoder().encode(paths)
        try LocalConfigurationFile.write(data, to: configurationURL)
        customURLs = paths
        return try scan()
    }

    private func loadCustomURLs() throws {
        guard customURLs == nil else { return }
        if let data = try LocalConfigurationFile.read(at: configurationURL) {
            let urls = try JSONDecoder().decode([URL].self, from: data)
            guard urls.count <= 1000,
                urls.allSatisfy({
                    $0.isFileURL && ($0.host == nil || $0.host == "" || $0.host == "localhost")
                        && $0.pathExtension.lowercased() == "app" && $0.path.utf8.count <= 4096
                })
            else { throw ConfigurationError(L10n.tr("The app catalog contains invalid paths.")) }
            customURLs = urls
        } else {
            customURLs = []
        }
    }

    private func application(at url: URL) -> InstalledApplication? {
        let url = url.resolvingSymlinksInPath().standardizedFileURL
        guard url.isFileURL, url.pathExtension.lowercased() == "app",
            let bundle = Bundle(url: url), let info = bundle.infoDictionary,
            info["CFBundlePackageType"] as? String == "APPL",
            let id = info["CFBundleIdentifier"] as? String, !id.isEmpty, id != excludedBundleID,
            id != excludedBundleID + ".settings"
        else { return nil }
        let name =
            bundle.object(forInfoDictionaryKey: "CFBundleDisplayName") as? String ?? bundle.object(
                forInfoDictionaryKey: "CFBundleName") as? String ?? url.deletingPathExtension().lastPathComponent
        return InstalledApplication(url: url, name: name, bundleID: id)
    }
}
