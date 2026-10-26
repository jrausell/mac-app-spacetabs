import Foundation

/// Failed automatic placements are not retried on every discovery/focus event.
/// A manual restore can retry; a new live window gets its own attempt.
public struct SessionRestorationQueue: Sendable {
    private struct Attempt: Hashable, Sendable {
        let saved: UUID
        let live: UUID
    }
    private var attempted = Set<Attempt>()
    public init() {}

    public mutating func takeMatches(saved: [SavedTab], windows: [WindowSnapshot], launchDates: [Int32: Date]) -> [UUID:
        UUID]
    {
        let savedIDs = Set(saved.map(\.id))
        attempted = attempted.filter { savedIDs.contains($0.saved) }
        let matches = WindowReconciler.matches(
            saved: saved, windows: windows.filter(\.compatible), launchDates: launchDates)
        return matches.filter { attempted.insert(Attempt(saved: $0.key, live: $0.value)).inserted }
    }
}
