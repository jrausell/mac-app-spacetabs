import Foundation

public enum WindowReconciler {
    /// Only one-to-one matches are safe. Two saved windows with the same title
    /// must not both bind to one live window, even if it is the sole candidate.
    public static func matches(saved: [SavedTab], windows: [WindowSnapshot], launchDates: [Int32: Date] = [:]) -> [UUID:
        UUID]
    {
        var result: [UUID: UUID] = [:]
        for tab in saved {
            let candidates = windows.filter { matches(tab.identity, $0.identity) }
            guard candidates.count == 1, let candidate = candidates.first,
                saved.filter({ matches($0.identity, candidate.identity) }).count == 1
            else { continue }
            result[tab.id] = candidate.id
        }
        // Browser/terminal titles may change while SpaceTabs is being updated.
        // Only fall back when exactly one saved and one live window belong to
        // the very same running process. A known document must still match.
        for tab in saved where result[tab.id] == nil && (tab.identity.document ?? "").isEmpty {
            guard let pid = tab.processID, let date = tab.launchDate, launchDates[pid] == date,
                saved.filter({ $0.identity.bundleID == tab.identity.bundleID }).count == 1
            else { continue }
            let candidates = windows.filter {
                $0.compatible && $0.pid == pid && $0.identity.bundleID == tab.identity.bundleID
            }
            guard candidates.count == 1, let window = candidates.first, !result.values.contains(window.id) else {
                continue
            }
            result[tab.id] = window.id
        }
        return result
    }

    private static func matches(_ saved: WindowIdentity, _ live: WindowIdentity) -> Bool {
        guard !saved.bundleID.isEmpty, saved.bundleID == live.bundleID else { return false }
        if let document = saved.document, !document.isEmpty { return document == live.document }
        return !saved.title.isEmpty && saved.title == live.title
    }
}
