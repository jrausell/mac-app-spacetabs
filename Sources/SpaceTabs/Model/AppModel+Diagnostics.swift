import AppKit
import SpaceTabsCore

extension AppModel {
    var applicationBundleURL: URL {
        if remoteSettings != nil {
            return Bundle.main.bundleURL.deletingLastPathComponent().deletingLastPathComponent()
                .deletingLastPathComponent()
        }
        return Bundle.main.bundleURL
    }

    var appVersion: String {
        Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? L10n.tr("development")
    }

    var discoveryStatus: WindowDiscoveryStatus {
        WindowDiscoveryStatus(trusted: trusted, searching: scanning, completed: hasCompletedDiscovery)
    }

    var savedSessionSummary: String {
        switch discoveryStatus {
        case .permissionRequired:
            L10n.tr("Saved session · \(pendingTabs.count) tabs · waiting for Accessibility access")
        case .waiting: L10n.tr("Saved session · waiting to check windows")
        case .searching: L10n.tr("Saved session · checking windows…")
        case .ready: L10n.tr("Saved session · \(restorableCount) of \(pendingTabs.count) windows found")
        }
    }

    /// Collect diagnostics only on request. Never poll AX for a debug view.
    func copyDiagnostics() {
        if sendToManager(.diagnostics) { return }
        let status = diagnosticSummary
        Task {
            let counters = await windowManager.discoveryDiagnostics()
            let catalogScans = await applicationCatalog.scanCount
            let geometry = await diagnosticGeometry()
            let report = [
                status,
                counters,
                L10n.tr("Catalog scans: \(catalogScans)"),
                L10n.tr("Installed apps: \(installedApplications.count)"),
                geometry,
            ].joined(separator: "\n")
            NSPasteboard.general.clearContents()
            NSPasteboard.general.setString(report, forType: .string)
        }
    }

    private var diagnosticSummary: String {
        L10n.tr(
            """
            SpaceTabs \(appVersion)
            macOS: \(ProcessInfo.processInfo.operatingSystemVersionString)
            PID: \(ProcessInfo.processInfo.processIdentifier)
            Bundle: \(Bundle.main.bundleURL.path)
            Executable: \(Bundle.main.executableURL?.path ?? L10n.tr("unknown"))
            Signing: \(Bundle.main.infoDictionary?["SpaceTabsSigningMode"] as? String ?? L10n.tr("not recorded"))
            Accessibility: \(PermissionService.trusted)
            Discovery completed: \(hasCompletedDiscovery)
            Full index completed: \(hasCompletedFullDiscovery)
            Paused: \(paused)
            Desktop transition in progress: \(spaceTransitioning)
            Desktop changes: \(spaceChangeCount)
            Last desktop change: \(lastSpaceChange)
            AX notification support: \(accessibilityNotices.joined(separator: "; "))
            Managed windows: \(originals.count)
            Shortcuts registered: \(registeredShortcuts.count)/\(ShortcutManager.Action.allCases.count)
            Shortcut actions: \(shortcutEventCount)
            Global key presses: \(globalShortcutEventCount)
            Last shortcut: \(lastShortcutEvent)
            Shortcut errors: \(shortcutWarnings.joined(separator: "; "))
            Tab clicks received: \(tabClickCount)
            SpaceTabs activation: \(workspaceActivationEvent)
            Workspace restore requests: \(workspacePresentationRequests)
            Last workspace restore: \(workspacePresentationStatus)
            Last tab click: \(lastTabClick)
            Tab switch in progress: \(switchingTabs)
            Selection pending: \(tabSelectionRunner.isPending)
            Selection latency: \(selectionTimings.summary)
            Right-drag gesture: \(rightDragStatus)
            \(rightDragDetails)
            Last message: \(message ?? L10n.tr("none"))
            """)
    }

    private func diagnosticGeometry() async -> String {
        guard let screen else { return L10n.tr("Selected display: unavailable") }
        var lines = [
            L10n.tr("Display: \(NSStringFromRect(screen.frame))"),
            L10n.tr("Visible macOS frame: \(NSStringFromRect(screen.visibleFrame))"),
            L10n.tr("Safe top inset: \(screen.safeAreaInsets.top)"),
            L10n.tr("Template: \(layoutTemplate.rawValue) · left \(Int(ratio * 100))% · row A \(Int(rowRatio * 100))%"),
            L10n.tr("Auto-hide tab bars: \(autoHideTabBars)"),
        ]
        for zone in activeZones {
            guard let id = tabs.selected[zone] else { continue }
            let actual = await windowManager.cachedFrame(id)
            let target = try? targetFrame(zone)
            lines.append(
                L10n.tr(
                    "Zone \(zone.title) AX target: \(target.map(NSStringFromRect) ?? L10n.tr("unavailable")) · last confirmed frame: \(actual.map(NSStringFromRect) ?? L10n.tr("unavailable"))"
                )
            )
        }
        return lines.joined(separator: "\n")
    }
}
