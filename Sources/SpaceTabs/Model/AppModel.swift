import AppKit
import Observation
import SpaceTabsCore

@MainActor @Observable
/// Main-actor coordinator. Window actions live in focused extensions; AX
/// references and synchronous IPC belong to WindowManagement, never this type.
final class AppModel {
    // MARK: - Settings bridge and preferences
    @ObservationIgnored var remoteSettings: RemoteSettingsModel?
    var remoteSettingsConnected = false
    var settingsShowsApplications = true
    var howToRequest = 0
    var preferences = UserPreferences() {
        didSet {
            if oldValue.language != preferences.language { L10n.configure(preferences.language) }
        }
    }
    var preferencesBlocked = false
    var loginEnabled = false
    var loginNeedsApproval = false
    var loginMessage: String? {
        didSet {
            if let loginMessage, loginMessage != oldValue {
                DiagnosticLog.shared.record("notice.loginMessage", details: ["message": loginMessage])
            }
        }
    }
    @ObservationIgnored let preferencesStore: UserPreferencesStore
    // MARK: - App catalog and assignments

    var assignmentZone: Zone?
    var assignmentRequest = 0
    var applicationAssignments: [ApplicationAssignment] = []
    @ObservationIgnored var assignedLaunchTasks: [Int32: Task<Void, Never>] = [:]
    @ObservationIgnored var profileLaunchTask: Task<Void, Never>?
    @ObservationIgnored var applicationAssignmentAttempts: [UUID: String] = [:]
    var installedApplications: [InstalledApplication] = []
    var catalogMessage: String? {
        didSet {
            if let catalogMessage, catalogMessage != oldValue {
                DiagnosticLog.shared.record("notice.catalogMessage", details: ["message": catalogMessage])
            }
        }
    }
    var launchingApplications = Set<String>()
    @ObservationIgnored var catalogUpdating = false
    @ObservationIgnored var catalogRefreshPending = false
    @ObservationIgnored let applicationCatalog: ApplicationCatalog
    @ObservationIgnored let catalogMonitor = ApplicationDirectoryMonitor()
    // MARK: - Layout and desktop state

    var workspaceID: UUID?
    var workspaceName = ""
    var desktopMenuCloudManaged: Bool?
    var workspaceDesktopAvailable = true
    var workspaceSummaries: [WorkspaceSummary] = []
    @ObservationIgnored var loadWorkspaceLayout: (() throws -> PersistedLayout?)?
    @ObservationIgnored var saveWorkspaceLayout: ((PersistedLayout, Set<UUID>) throws -> Void)?
    @ObservationIgnored var preferencesCommitted: ((UserPreferences) -> Void)?
    @ObservationIgnored var profileOpening: ((UUID) -> Void)?
    @ObservationIgnored var profileSaved: ((UUID) -> Void)?
    @ObservationIgnored var workspaceCommand: ((SettingsCommand) -> Void)?
    @ObservationIgnored var windowIsEligible: ((WindowSnapshot) -> Bool)?
    @ObservationIgnored weak var discoveryOwner: AppModel?
    @ObservationIgnored var discoveryBundles: (() -> Set<String>)?
    @ObservationIgnored var discoveryPublished: ((ScanResult, Bool) -> Void)?
    @ObservationIgnored var focusPublished: ((UUID?) -> Void)?
    @ObservationIgnored var catalogPublished: (([InstalledApplication]) -> Void)?
    var showTabBars: () -> Void = {}
    var tabAppearance = TabAppearance()
    @ObservationIgnored var appearanceSaveTask: Task<Void, Never>?
    @ObservationIgnored var resizingColumns = false
    @ObservationIgnored var columnResizePreview: Double?
    @ObservationIgnored var resizingRows = false
    var layoutTemplate: LayoutTemplate = .twoColumns
    var rowRatio = 0.5
    var appliedRowRatio = 0.5
    var activeZones: [Zone] { layoutTemplate.zones }
    var revealTabsAtTopEdge = false
    var autoHideTabBars = true
    var ratio = 0.25
    var tabs = TabManager()
    var demo = false
    var paused = false
    var displayUnavailable = false
    @ObservationIgnored var displaySelection = DisplaySelectionTracker()
    var spaceTransitioning = false
    var spaceChangeCount = 0
    var lastSpaceChange = L10n.tr("No desktop changes")
    @ObservationIgnored var spaceChangeTask: Task<Void, Never>?
    var managementSuspended: Bool {
        paused || !workspaceDesktopAvailable || displayUnavailable || spaceTransitioning || displayProfileTask != nil
    }
    var message: String? {
        didSet {
            if let message, message != oldValue {
                DiagnosticLog.shared.record("notice.message", details: ["message": message])
            }
        }
    }
    var titles: [UUID: String] = [:]
    var windows: [WindowSnapshot] = []
    var trusted = PermissionService.trusted
    var scanning = false
    var hasCompletedDiscovery = false
    var hasCompletedFullDiscovery = false
    var busy = false
    var switchingTabs = false
    // MARK: - Interaction and diagnostics

    var selectionTimings = TimingStatistics()
    var rightDragStatus = L10n.tr("Not started")
    var rightDragDetails = L10n.tr("No gesture events")
    var showQuickSwitcher: () -> Void = {}
    var tabDragVisibility: @MainActor (Bool) -> Void = { _ in }
    var zoomedWindow: ZoomedWindow?
    @ObservationIgnored var zoomRequestTask: Task<Void, Never>?
    var pendingAutomaticProfile: UUID?
    @ObservationIgnored var displayProfileTask: Task<Void, Never>?
    @ObservationIgnored var displayTransitionUsesProfile = false
    var workspaceActivationEvent = L10n.tr("No activations")
    var workspacePresentationRequests = 0
    var workspacePresentationStatus = L10n.tr("No requests")
    @ObservationIgnored var workspaceActivationPIDs: Set<Int32> = []
    @ObservationIgnored var workspacePresentationRevision: Int?
    @ObservationIgnored let tabSelectionRunner = TabSelectionRunner()
    var warnings: [String] = [] {
        didSet {
            for notice in warnings where !oldValue.contains(notice) {
                DiagnosticLog.shared.record("warning.warnings", level: "warning", details: ["message": notice])
            }
        }
    }
    var accessibilityNotices: [String] = [] {
        didSet {
            for notice in accessibilityNotices where !oldValue.contains(notice) {
                DiagnosticLog.shared.record(
                    "warning.accessibilityNotices", level: "warning", details: ["message": notice])
            }
        }
    }
    var shortcutWarnings: [String] = [] {
        didSet {
            for notice in shortcutWarnings where !oldValue.contains(notice) {
                DiagnosticLog.shared.record("warning.shortcutWarnings", level: "warning", details: ["message": notice])
            }
        }
    }
    var registeredShortcuts: Set<UInt32> = []
    var globalShortcutEventCount = 0
    var shortcutEventCount = 0
    var lastShortcutEvent = L10n.tr("No key presses received")
    var restartShortcuts: () -> Void = {}
    // MARK: - Managed windows and saved session

    var selectedScreenID = ""
    var activeZone: Zone = .a
    var originals: [UUID: OriginalWindowState] = [:]
    var pendingTabs: [SavedTab] = []
    var savedTabOrder: [UUID] = []
    var reopeningPendingTabs = Set<UUID>()
    var pendingWindowChoices: [UUID: [UUID]] = [:]
    var pendingWindowMessages: [UUID: String] = [:]
    @ObservationIgnored var pendingReopens: [UUID: PendingWindowReopen] = [:]
    @ObservationIgnored var pendingReopenTasks: [UUID: Task<Void, Never>] = [:]
    @ObservationIgnored var pendingReopenTokens: [UUID: UUID] = [:]
    var restoringTabZones = Set<Zone>()
    @ObservationIgnored var sessionRestoration = SessionRestorationQueue()
    var configurationBlocked = false
    var terminating = false
    var appliedAutoHideTabBars = true
    var appliedRatio = 0.25
    var appliedScreenID = ""
    var desktopRevision = 0
    // MARK: - Runtime services and task ownership

    @ObservationIgnored let windowManager: WindowManager
    @ObservationIgnored let persistence: PersistenceStore
    @ObservationIgnored var operationTask: Task<Void, Never>?
    @ObservationIgnored var reflowTask: Task<Void, Never>?
    @ObservationIgnored var scanTask: Task<Void, Never>?
    @ObservationIgnored var lastVisibleFrame: CGRect?
    @ObservationIgnored var refreshRequests = WindowRefreshQueue()
    @ObservationIgnored var refreshTask: Task<Void, Never>?
    @ObservationIgnored var refreshInFlight = false
    @ObservationIgnored var lastDiscovery: ContinuousClock.Instant?
    var openSettings: () -> Void = {}
    var layoutChanged: () -> Void = {}
    @ObservationIgnored var tabClickCount = 0
    @ObservationIgnored var lastTabClick = L10n.tr("none")
    @ObservationIgnored var presentationRevision = 0
    @ObservationIgnored var explicitSelectionRevision: [Zone: Int] = [:]

    init(
        preferencesStore: UserPreferencesStore = .standard, persistence: PersistenceStore = .standard,
        windowManager: WindowManager = WindowManager(), applicationCatalog: ApplicationCatalog? = nil
    ) {
        self.applicationCatalog =
            applicationCatalog
            ?? ApplicationCatalog(
                roots: [
                    URL(fileURLWithPath: "/Applications"), URL(fileURLWithPath: "/System/Applications"),
                    FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Applications"),
                ],
                configurationURL: PersistenceStore.standard.url.deletingLastPathComponent().appendingPathComponent(
                    "applications.json"))
        self.windowManager = windowManager
        self.preferencesStore = preferencesStore
        self.persistence = persistence
    }
}
