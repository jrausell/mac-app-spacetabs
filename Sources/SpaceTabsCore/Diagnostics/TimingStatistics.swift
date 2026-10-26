import Foundation

public struct TimingStatistics: Codable, Equatable, Sendable {
    public private(set) var count = 0
    public private(set) var milliseconds: [Double] = []
    public init() {}
    public mutating func record(_ duration: Duration) {
        let value = Double(duration.components.seconds) * 1000 + Double(duration.components.attoseconds) / 1e15
        guard value.isFinite, value >= 0 else { return }
        count += 1
        milliseconds.append(value)
        if milliseconds.count > 128 { milliseconds.removeFirst(milliseconds.count - 128) }
    }
    public var summary: String {
        guard !milliseconds.isEmpty else { return L10n.tr("No samples") }
        let sorted = milliseconds.sorted()
        return
            L10n.tr(
                "\(count) samples · median \(Int(sorted[(sorted.count - 1) / 2])) ms · p95 \(Int(sorted[min(sorted.count - 1, Int(ceil(Double(sorted.count) * 0.95)) - 1)])) ms"
            )
    }
}
