import CoreGraphics
import Foundation

public struct ZoneGeometry: Equatable, Sendable {
    public let bar: CGRect
    public let content: CGRect
}

public struct ColumnHeaders: Equatable, Sendable {
    public let bars: [Zone: CGRect]
    public let handle: CGRect
    public let rowHandle: CGRect?
}

public struct LayoutEngine: Sendable {
    public var barHeight: CGFloat = 42
    public var margin: CGFloat = 0
    public var gap: CGFloat = 0
    public init() {}

    public func ratioByDragging(initial: Double, translation: CGFloat, visibleWidth: CGFloat) -> Double {
        let width = visibleWidth - 2 * margin - gap
        guard width.isFinite, width > 0, initial.isFinite, translation.isFinite else { return 0.25 }
        return min(0.8, max(0.2, initial + Double(translation / width)))
    }

    /// Keep Dock bounds and camera clearance. Menu clearance is optional for
    /// window content, because visibleFrame already reflects menu auto-hiding.
    public static func usableFrame(
        visibleFrame: CGRect, screenFrame: CGRect,
        menuBarHeight: CGFloat, safeTopInset: CGFloat = 0, reserveMenuArea: Bool = true
    ) -> CGRect {
        guard
            [
                visibleFrame.minX, visibleFrame.minY, visibleFrame.width, visibleFrame.height,
                screenFrame.minX, screenFrame.minY, screenFrame.width, screenFrame.height,
                menuBarHeight, safeTopInset,
            ].allSatisfy(\.isFinite)
        else { return .zero }
        var frame = visibleFrame.intersection(screenFrame)
        guard !frame.isNull else { return .zero }
        let top = min(frame.maxY, screenFrame.maxY - max(0, reserveMenuArea ? menuBarHeight : 0, safeTopInset))
        frame.size.height = max(0, top - frame.minY)
        return frame
    }

    /// Floating tabs need menu clearance without taking that height away from
    /// external windows. Fixed tabs follow the actual visible desktop bounds.
    public func desktopGeometry(
        visibleFrame: CGRect, screenFrame: CGRect, menuBarHeight: CGFloat,
        safeTopInset: CGFloat = 0, ratio: Double, reserveHeader: Bool, template: LayoutTemplate = .twoColumns,
        rowRatio: Double = 0.5
    ) -> [Zone: ZoneGeometry] {
        let contentFrame = Self.usableFrame(
            visibleFrame: visibleFrame, screenFrame: screenFrame,
            menuBarHeight: menuBarHeight, safeTopInset: safeTopInset, reserveMenuArea: false)
        let windows = geometry(
            visibleFrame: contentFrame, ratio: ratio, reserveHeader: reserveHeader, template: template,
            rowRatio: rowRatio)
        guard !reserveHeader else { return windows }
        let menuFrame = Self.usableFrame(
            visibleFrame: visibleFrame, screenFrame: screenFrame,
            menuBarHeight: menuBarHeight, safeTopInset: safeTopInset)
        return windows.mapValues { window in
            var bar = window.bar
            bar.origin.y = min(bar.maxY, menuFrame.maxY) - bar.height
            return ZoneGeometry(bar: bar, content: window.content)
        }
    }

    public func geometry(
        visibleFrame: CGRect, ratio: Double, reserveHeader: Bool = true, template: LayoutTemplate = .twoColumns,
        rowRatio: Double = 0.5
    ) -> [Zone: ZoneGeometry] {
        guard [visibleFrame.minX, visibleFrame.minY, visibleFrame.width, visibleFrame.height].allSatisfy(\.isFinite),
            visibleFrame.width > margin * 2 + gap,
            visibleFrame.height > margin * 2 + barHeight + 4
        else { return [:] }
        let frame = visibleFrame.insetBy(dx: margin, dy: margin)
        let fraction = ratio.isFinite ? min(0.8, max(0.2, ratio)) : 0.25
        let rows = rowRatio.isFinite ? min(0.75, max(0.25, rowRatio)) : 0.5
        let secondary = ZoneLayoutTree.split(.vertical, fraction: rows, gap: 0, .group(.a), .group(.c))
        let tree: ZoneLayoutTree =
            switch template {
            case .twoColumns: .split(.horizontal, fraction: fraction, gap: gap, .group(.a), .group(.b))
            case .splitLeft: .split(.horizontal, fraction: fraction, gap: gap, secondary, .group(.b))
            case .splitRight: .split(.horizontal, fraction: fraction, gap: gap, .group(.b), secondary)
            }
        let zones = tree.frames(in: frame).mapValues { rect in
            split(rect, barHeight: min(barHeight, rect.height), reserveHeader: reserveHeader)
        }
        return zones
    }

    /// The handle belongs to the chrome, not the external window layout.
    /// Shorten the headers around it so it never covers their + buttons.
    public func columnHeaders(for zones: [Zone: ZoneGeometry], handleWidth: CGFloat = 32) -> ColumnHeaders? {
        guard let a = zones[.a]?.bar, let b = zones[.b]?.bar else { return nil }
        let reversed = b.minX < a.minX
        let leftBar = reversed ? b : a
        let rightBar = reversed ? a : b
        let center = (leftBar.maxX + rightBar.minX) / 2
        let handle = CGRect(x: center - handleWidth / 2, y: a.minY, width: handleWidth, height: a.height)
        let left = CGRect(
            x: leftBar.minX, y: leftBar.minY, width: max(0, handle.minX - 4 - leftBar.minX), height: leftBar.height)
        let rightX = handle.maxX + 4
        let right = CGRect(x: rightX, y: rightBar.minY, width: max(0, rightBar.maxX - rightX), height: rightBar.height)
        guard left.width >= 40, right.width >= 40 else { return nil }
        var bars: [Zone: CGRect] = [.a: reversed ? right : left, .b: reversed ? left : right]
        var rowHandle: CGRect?
        if let c = zones[.c]?.bar {
            rowHandle = CGRect(x: c.minX, y: c.minY, width: handleWidth, height: c.height)
            bars[.c] = CGRect(
                x: c.minX + handleWidth + 4, y: c.minY,
                width: max(0, c.width - handleWidth - 4), height: c.height)
        }
        return ColumnHeaders(bars: bars, handle: handle, rowHandle: rowHandle)
    }

    private func split(_ rect: CGRect, barHeight: CGFloat, reserveHeader: Bool) -> ZoneGeometry {
        ZoneGeometry(
            bar: CGRect(x: rect.minX, y: rect.maxY - barHeight, width: rect.width, height: barHeight),
            content: CGRect(
                x: rect.minX, y: rect.minY, width: rect.width,
                height: max(0, rect.height - (reserveHeader ? barHeight + 4 : 0)))
        )
    }

    /// AX is top-left based relative to the primary display, not the chosen display.
    public static func accessibilityFrame(from rect: CGRect, primaryDisplayTop: CGFloat) -> CGRect {
        CGRect(x: rect.minX, y: primaryDisplayTop - rect.maxY, width: rect.width, height: rect.height)
    }
    public static func appKitFrame(from rect: CGRect, primaryDisplayTop: CGFloat) -> CGRect {
        accessibilityFrame(from: rect, primaryDisplayTop: primaryDisplayTop)
    }

    public static func clamped(_ rect: CGRect, to visible: CGRect) -> CGRect {
        let width = min(max(1, rect.width), visible.width)
        let height = min(max(1, rect.height), visible.height)
        return CGRect(
            x: min(max(rect.minX, visible.minX), visible.maxX - width),
            y: min(max(rect.minY, visible.minY), visible.maxY - height), width: width, height: height)
    }

    /// Terminal-like apps resize in character cells; allow a small inner gap,
    /// but never accept a minimum size that spills over into the other zone.
    public static func accepts(actual: CGRect, target: CGRect) -> Bool {
        abs(actual.minX - target.minX) <= 3 && abs(actual.minY - target.minY) <= 3 && actual.width <= target.width + 2
            && actual.height <= target.height + 2 && target.width - actual.width <= 32
            && target.height - actual.height <= 32
    }
}
