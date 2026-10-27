import CoreGraphics
import Foundation

/// Public Window Server metadata, without Accessibility handles or page titles.
public struct WindowServerWindow: Sendable {
    public let pid: Int32
    public let number: UInt32
    public let frame: CGRect
    public init(pid: Int32, number: UInt32, frame: CGRect) {
        self.pid = pid
        self.number = number
        self.frame = frame
    }

    public static func number(for frame: CGRect, pid: Int32, in windows: [Self]) -> UInt32? {
        let candidates = windows.filter {
            $0.pid == pid && $0.number != 0
                && abs($0.frame.minX - frame.minX) <= 2 && abs($0.frame.minY - frame.minY) <= 2
                && abs($0.frame.width - frame.width) <= 2 && abs($0.frame.height - frame.height) <= 2
        }
        // Never infer an identity from overlapping, indistinguishable windows.
        return candidates.count == 1 ? candidates.first?.number : nil
    }
}
