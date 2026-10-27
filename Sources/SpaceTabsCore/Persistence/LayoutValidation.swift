import Foundation

extension PersistedLayout {
    /// Validate a session or profile before it reaches window management.
    public func validate() throws {
        guard version == 1 else {
            throw ConfigurationError(L10n.tr("Unsupported configuration version: \(version)."))
        }
        guard tabAppearance.isValid, ratio.isFinite, (0.2...0.8).contains(ratio),
            rowRatio.isFinite, (0.25...0.75).contains(rowRatio), tabs.count <= 128,
            Set(tabs.map(\.id)).count == tabs.count
        else {
            throw ConfigurationError(L10n.tr("The configuration contains an invalid layout."))
        }
        guard screenID.utf8.count <= 512 else {
            throw ConfigurationError(L10n.tr("The display identifier is too long."))
        }
        guard applicationAssignments.count <= 1000,
            Set(applicationAssignments.map(\.id)).count == applicationAssignments.count,
            applicationAssignments.allSatisfy({
                $0.url.isFileURL && $0.url.pathExtension.lowercased() == "app"
                    && ($0.url.host == nil || $0.url.host == "" || $0.url.host == "localhost")
                    && $0.url.path.utf8.count <= 4096 && $0.name.utf8.count <= 4096 && !$0.bundleID.isEmpty
                    && $0.bundleID.utf8.count <= 512 && $0.bundleID != SpaceTabsIdentity.appBundleID
            })
        else {
            throw ConfigurationError(L10n.tr("App assignments contain duplicate or invalid paths."))
        }
        for zone in Zone.allCases where tabs.filter({ $0.zone == zone && $0.selected }).count > 1 {
            throw ConfigurationError(L10n.tr("The configuration has more than one selected tab in zone \(zone.title)."))
        }
        for tab in tabs {
            guard !tab.identity.bundleID.isEmpty, tab.identity.bundleID != SpaceTabsIdentity.appBundleID,
                tab.identity.bundleID.utf8.count <= 512, tab.identity.title.utf8.count <= 16_384,
                (tab.identity.document?.utf8.count ?? 0) <= 65_536,
                tab.processID.map({ $0 > 0 }) ?? true,
                tab.windowNumber.map({ $0 > 0 }) ?? true
            else { throw ConfigurationError(L10n.tr("Invalid window identity.")) }
            if let frame = tab.original?.frame {
                guard [frame.minX, frame.minY, frame.width, frame.height].allSatisfy(\.isFinite), frame.width > 0,
                    frame.height > 0,
                    abs(frame.minX) <= 10_000_000, abs(frame.minY) <= 10_000_000,
                    frame.width <= 100_000, frame.height <= 100_000
                else {
                    throw ConfigurationError(L10n.tr("The configuration contains an invalid window frame."))
                }
            }
        }
    }
}
