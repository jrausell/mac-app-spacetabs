import CoreGraphics

public enum NavigationDirection: String, Sendable { case left, right, up, down }
public enum LayoutNavigation {
    /// Prefer zones sharing an edge with the source, then the closest center.
    public static func neighbor(from source: Zone, direction: NavigationDirection, zones: [Zone: CGRect]) -> Zone? {
        guard let origin = zones[source] else { return nil }
        let horizontal = direction == .left || direction == .right
        let positive = direction == .right || direction == .up
        return zones.filter { zone, rect in
            guard zone != source else { return false }
            let delta = horizontal ? rect.midX - origin.midX : rect.midY - origin.midY
            return positive ? delta > 1 : delta < -1
        }.min { lhs, rhs in
            func score(_ rect: CGRect) -> CGFloat {
                let primary = abs(horizontal ? rect.midX - origin.midX : rect.midY - origin.midY)
                let secondary = abs(horizontal ? rect.midY - origin.midY : rect.midX - origin.midX)
                let overlap =
                    horizontal
                    ? min(rect.maxY, origin.maxY) - max(rect.minY, origin.minY)
                    : min(rect.maxX, origin.maxX) - max(rect.minX, origin.minX)
                return primary + secondary + (overlap > 0 ? 0 : 100_000)
            }
            let a = score(lhs.value)
            let b = score(rhs.value)
            return a == b ? lhs.key.rawValue < rhs.key.rawValue : a < b
        }?.key
    }
}
