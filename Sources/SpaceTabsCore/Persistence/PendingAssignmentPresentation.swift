import Foundation

/// Saved page/document identities remain recovery data, not individual app tabs.
public enum PendingAssignmentPresentation {
    public static func representatives(pending: [SavedTab], live: [WindowSnapshot], zone: Zone) -> [SavedTab] {
        let represented = Set(live.map { $0.identity.bundleID })
        var seen = Set<String>()
        return pending.filter {
            $0.zone == zone && !represented.contains($0.identity.bundleID)
                && seen.insert($0.identity.bundleID).inserted
        }
    }
}
