import CoreGraphics
import Foundation

/// Place every tab in its zone, with selected windows last. Inactive tabs stay
/// open underneath; a caller raises the selections after successful placement.
public enum WindowPlacementPlan {
    public static func commands(frames: [UUID: CGRect], selected: [UUID]) -> [WindowCommand] {
        let selection = Set(selected)
        let background = frames.keys.filter { !selection.contains($0) }.sorted { $0.uuidString < $1.uuidString }
        var seen = Set<UUID>()
        return (background + selected).compactMap { id in
            guard let frame = frames[id], seen.insert(id).inserted else { return nil }
            return .place(id, frame)
        }
    }
}
