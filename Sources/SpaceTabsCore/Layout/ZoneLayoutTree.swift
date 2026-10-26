import CoreGraphics

/// Templates are compositions of splits and independent tab groups. This is
/// internal layout data, never executable configuration or a window container.
indirect enum ZoneLayoutTree: Sendable {
    enum Axis: Sendable { case horizontal, vertical }
    case group(Zone)
    case split(Axis, fraction: Double, gap: CGFloat, ZoneLayoutTree, ZoneLayoutTree)

    func frames(in frame: CGRect) -> [Zone: CGRect] {
        switch self {
        case .group(let zone): return [zone: frame]
        case .split(let axis, let fraction, let gap, let first, let second):
            let fraction = fraction.isFinite ? min(1, max(0, fraction)) : 0.5
            let dimension = axis == .horizontal ? frame.width : frame.height
            let gap = min(dimension, max(0, gap))
            let firstSize = ((dimension - gap) * fraction).rounded(.down)
            let secondSize = dimension - gap - firstSize
            let a: CGRect
            let b: CGRect
            if axis == .horizontal {
                a = CGRect(x: frame.minX, y: frame.minY, width: firstSize, height: frame.height)
                b = CGRect(x: a.maxX + gap, y: frame.minY, width: secondSize, height: frame.height)
            } else {
                b = CGRect(x: frame.minX, y: frame.minY, width: frame.width, height: secondSize)
                a = CGRect(x: frame.minX, y: b.maxY + gap, width: frame.width, height: firstSize)
            }
            return first.frames(in: a).merging(second.frames(in: b)) { _, value in value }
        }
    }
}
