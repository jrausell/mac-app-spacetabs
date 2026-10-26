import Foundation

public enum WindowDiscoveryPlan {
    /// nil means a full search; an empty set means all saved apps are closed.
    public static func initialProcesses(savedBundleIDs: Set<String>, running: [Int32: String]) -> Set<Int32>? {
        guard !savedBundleIDs.isEmpty else { return nil }
        return Set(running.compactMap { savedBundleIDs.contains($0.value) ? $0.key : nil })
    }
}
