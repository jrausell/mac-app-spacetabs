import CoreGraphics
import Foundation

public struct SavedTab: Codable, Equatable, Sendable, Identifiable {
    public let id: UUID
    public let identity: WindowIdentity
    public let zone: Zone
    public let selected: Bool
    public let original: OriginalWindowState?
    public let processID: Int32?
    public let launchDate: Date?
    public let windowNumber: UInt32?

    public init(
        id: UUID, identity: WindowIdentity, zone: Zone, selected: Bool,
        original: OriginalWindowState? = nil, processID: Int32? = nil, launchDate: Date? = nil,
        windowNumber: UInt32? = nil
    ) {
        self.id = id
        self.identity = identity
        self.zone = zone
        self.selected = selected
        self.original = original
        self.processID = processID
        self.launchDate = launchDate
        self.windowNumber = windowNumber
    }
}

public struct PersistedLayout: Codable, Equatable, Sendable {
    public var version = 1
    public var template: LayoutTemplate
    public var rowRatio: Double
    public var ratio: Double
    public var screenID: String
    public var tabs: [SavedTab]
    public var tabAppearance: TabAppearance
    public var applicationAssignments: [ApplicationAssignment]
    public var revealTabsAtTopEdge: Bool
    public var autoHideTabBars: Bool
    public init(
        ratio: Double = 0.25, screenID: String = "", tabs: [SavedTab] = [], autoHideTabBars: Bool = true,
        revealTabsAtTopEdge: Bool = false, applicationAssignments: [ApplicationAssignment] = [],
        tabAppearance: TabAppearance = TabAppearance(), template: LayoutTemplate = .twoColumns, rowRatio: Double = 0.5
    ) {
        self.revealTabsAtTopEdge = revealTabsAtTopEdge
        self.template = template
        self.rowRatio = rowRatio
        self.ratio = ratio
        self.screenID = screenID
        self.tabs = tabs
        self.autoHideTabBars = autoHideTabBars
        self.applicationAssignments = applicationAssignments
        self.tabAppearance = tabAppearance
    }

    private enum CodingKeys: String, CodingKey {
        case version, template, rowRatio, ratio, screenID, tabs, autoHideTabBars, revealTabsAtTopEdge,
            applicationAssignments, tabAppearance
    }
    public init(from decoder: any Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        version = try values.decode(Int.self, forKey: .version)
        template = try values.decodeIfPresent(LayoutTemplate.self, forKey: .template) ?? .twoColumns
        rowRatio = try values.decodeIfPresent(Double.self, forKey: .rowRatio) ?? 0.5
        ratio = try values.decode(Double.self, forKey: .ratio)
        // Migrate the formerly supported 15–85% range to the new 20–80% limits.
        if ratio.isFinite, (0.15...0.85).contains(ratio) { ratio = min(0.8, max(0.2, ratio)) }
        screenID = try values.decode(String.self, forKey: .screenID)
        tabs = try values.decode([SavedTab].self, forKey: .tabs)
        tabAppearance = try values.decodeIfPresent(TabAppearance.self, forKey: .tabAppearance) ?? TabAppearance()
        applicationAssignments =
            try values.decodeIfPresent([ApplicationAssignment].self, forKey: .applicationAssignments) ?? []
        revealTabsAtTopEdge = try values.decodeIfPresent(Bool.self, forKey: .revealTabsAtTopEdge) ?? false
        // Keep existing auto-hide behavior when reading older sessions.
        autoHideTabBars = try values.decodeIfPresent(Bool.self, forKey: .autoHideTabBars) ?? true
    }
}

extension PersistedLayout {
    public mutating func adapt(to destination: LayoutTemplate) {
        template = destination
        guard destination == .twoColumns else { return }
        var selectedZones = Set<Zone>()
        // Give an existing A selection priority over C's former selection.
        let preferredA = tabs.first { $0.zone == .a && $0.selected }?.id
        tabs = tabs.map { tab in
            let zone: Zone = tab.zone == .c ? .a : tab.zone
            let selected =
                tab.selected && (zone != .a || preferredA == nil || tab.id == preferredA)
                && selectedZones.insert(zone).inserted
            return SavedTab(
                id: tab.id, identity: tab.identity, zone: zone, selected: selected,
                original: tab.original, processID: tab.processID, launchDate: tab.launchDate,
                windowNumber: tab.windowNumber)
        }
        applicationAssignments = applicationAssignments.map { rule in
            var rule = rule
            if rule.zone == .c { rule.zone = .a }
            return rule
        }
    }
}
