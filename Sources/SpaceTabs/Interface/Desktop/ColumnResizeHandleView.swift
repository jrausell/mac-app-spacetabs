import AppKit
import SpaceTabsCore

/// The input window stays stationary during a drag. Only the separate preview
/// guide moves; there is no SwiftUI gesture or moving coordinate space involved.
@MainActor
final class ColumnResizeHandleView: NSView {
    private weak var model: AppModel?
    private let rows: Bool
    private struct Drag {
        let initialRatio: Double
        let initialMouseX: CGFloat
        let visibleWidth: CGFloat
        var preview: Double
    }
    private var drag: Drag?
    private var hovered = false
    private var tracking: NSTrackingArea?

    init(model: AppModel, rows: Bool = false) {
        self.rows = rows
        self.model = model
        super.init(frame: .zero)
        autoresizingMask = [.width, .height]
        refreshLocalization()
    }
    func refreshLocalization() {
        toolTip =
            rows
            ? L10n.tr("DRAG to resize rows A/C · Double-click: 50/50")
            : L10n.tr("DRAG to resize columns · Double-click: template default")
        setAccessibilityElement(true)
        setAccessibilityLabel(rows ? L10n.tr("Resize rows A and C") : L10n.tr("Resize columns"))
    }
    required init?(coder: NSCoder) { nil }
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
    override var acceptsFirstResponder: Bool { true }
    override var mouseDownCanMoveWindow: Bool { false }
    override func resetCursorRects() { addCursorRect(bounds, cursor: rows ? .resizeUpDown : .resizeLeftRight) }
    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        if let tracking { removeTrackingArea(tracking) }
        let area = NSTrackingArea(
            rect: .zero, options: [.mouseEnteredAndExited, .activeAlways, .inVisibleRect], owner: self)
        addTrackingArea(area)
        tracking = area
    }
    override func mouseEntered(with event: NSEvent) {
        hovered = true
        needsDisplay = true
    }
    override func mouseExited(with event: NSEvent) {
        hovered = false
        needsDisplay = true
    }
    override func viewDidChangeEffectiveAppearance() {
        super.viewDidChangeEffectiveAppearance()
        needsDisplay = true
    }

    override func draw(_ dirtyRect: NSRect) {
        guard let model else { return }
        let dark = effectiveAppearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
        let palette = model.tabAppearance.palette(systemIsDark: dark)
        func color(_ value: TabColor) -> NSColor {
            NSColor(srgbRed: value.red, green: value.green, blue: value.blue, alpha: 1)
        }
        let shape = NSBezierPath(roundedRect: bounds.insetBy(dx: 2, dy: 1), xRadius: 9, yRadius: 9)
        color(palette.background).setFill()
        shape.fill()
        color(model.tabAppearance.accent(for: .a, systemIsDark: dark)).setStroke()
        shape.lineWidth = hovered || drag != nil ? 3 : 2
        shape.stroke()
        let arrow = NSAttributedString(
            string: rows ? "↕" : "↔",
            attributes: [
                .font: NSFont.systemFont(ofSize: 24, weight: .heavy), .foregroundColor: color(palette.foreground),
            ])
        arrow.draw(at: NSPoint(x: (bounds.width - arrow.size().width) / 2, y: 13))
        let label =
            drag.map { "\(Int($0.preview * 100)) / \(100 - Int($0.preview * 100))" }
            ?? (rows ? L10n.tr("HEIGHT") : L10n.tr("WIDTH"))
        let text = NSAttributedString(
            string: label,
            attributes: [
                .font: NSFont.systemFont(ofSize: 9, weight: .bold), .foregroundColor: color(palette.foreground),
            ])
        text.draw(at: NSPoint(x: (bounds.width - text.size().width) / 2, y: 4))
    }

    override func mouseDown(with event: NSEvent) {
        guard let model, !model.busy, !model.scanning, !model.terminating, let screen = model.screen, let window else {
            return
        }
        if event.clickCount == 2 {
            if rows { model.rowRatio = 0.5 } else { model.ratio = model.layoutTemplate.defaultRatio }
            model.layoutPreferenceChanged()
            return
        }
        let mouse = window.convertPoint(toScreen: event.locationInWindow)
        let frame = model.layoutVisibleFrame(on: screen)
        let initial = rows ? model.rowRatio : model.ratio
        drag = Drag(
            initialRatio: initial, initialMouseX: rows ? mouse.y : mouse.x,
            visibleWidth: rows ? frame.height : frame.width, preview: initial)
        model.beginColumnResize(rows: rows)
        needsDisplay = true
    }
    override func mouseDragged(with event: NSEvent) {
        guard var drag, let window, let model else { return }
        let mouse = window.convertPoint(toScreen: event.locationInWindow)
        let x = rows ? mouse.y : mouse.x
        drag.preview = LayoutEngine().ratioByDragging(
            initial: drag.initialRatio,
            translation: (x - drag.initialMouseX) * (rows ? -1 : 1), visibleWidth: drag.visibleWidth)
        if rows { drag.preview = min(0.75, max(0.25, drag.preview)) }
        self.drag = drag
        model.previewColumnResize(drag.preview)
        needsDisplay = true
    }
    override func mouseUp(with event: NSEvent) {
        guard drag != nil else { return }
        mouseDragged(with: event)
        drag = nil
        model?.finishColumnResize(commit: true)
        needsDisplay = true
    }
    override func cancelOperation(_ sender: Any?) { cancelDrag() }
    func cancelDrag(refresh: Bool = true) {
        guard drag != nil else { return }
        drag = nil
        model?.finishColumnResize(commit: false, refresh: refresh)
        needsDisplay = true
    }
    override func viewWillMove(toWindow newWindow: NSWindow?) {
        if newWindow == nil { cancelDrag(refresh: false) }
        super.viewWillMove(toWindow: newWindow)
    }
}
