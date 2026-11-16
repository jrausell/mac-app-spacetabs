import Foundation

/// Missing windows are saved intent, not evidence that an assignment was removed.
/// Keep unavailable tabs in their old positions while accepting live reordering.
public enum SavedTabManifest {
    public static func merge(live: [SavedTab], pending: [SavedTab], order: [UUID]) -> [SavedTab] {
        var seen = Set<UUID>()
        let live = live.filter { seen.insert($0.id).inserted }
        let selectedZones = Set(live.filter(\.selected).map(\.zone))
        var pendingSelections = Set<Zone>()
        let pending = pending.filter { seen.insert($0.id).inserted }.map { saved in
            SavedTab(
                id: saved.id, identity: saved.identity, zone: saved.zone,
                selected: saved.selected && !selectedZones.contains(saved.zone)
                    && pendingSelections.insert(saved.zone).inserted,
                original: saved.original, processID: saved.processID, launchDate: saved.launchDate,
                windowNumber: saved.windowNumber)
        }
        return Zone.allCases.flatMap { zone in
            let current = live.filter { $0.zone == zone }
            let unavailable = pending.filter { $0.zone == zone }
            let available = Dictionary(uniqueKeysWithValues: (current + unavailable).map { ($0.id, $0) })
            return orderedIDs(live: current.map(\.id), pending: unavailable.map(\.id), order: order)
                .compactMap { available[$0] }
        }
    }

    public static func orderedIDs(live: [UUID], pending: [UUID], order: [UUID]) -> [UUID] {
        var seen = Set<UUID>()
        let live = live.filter { seen.insert($0).inserted }
        let pending = pending.filter { seen.insert($0).inserted }
        let currentIDs = Set(live)
        let available = Set(live + pending)
        var remaining = live.makeIterator()
        var emitted = Set<UUID>()
        var result: [UUID] = []
        for id in order where available.contains(id) && emitted.insert(id).inserted {
            if currentIDs.contains(id) {
                if let next = remaining.next() { result.append(next) }
            } else {
                result.append(id)
            }
        }
        result.append(contentsOf: remaining)
        result.append(contentsOf: pending.filter { !emitted.contains($0) })
        return result
    }

    /// Named profiles never store process-local identities or release frames.
    public static func profileTabs(_ tabs: [SavedTab]) -> [SavedTab] {
        tabs.map {
            SavedTab(id: $0.id, identity: $0.identity, zone: $0.zone, selected: $0.selected)
        }
    }
}
