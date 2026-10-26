import AppKit
import SpaceTabsCore
import SwiftUI

private final class ClickThroughTabButton: NSButton, NSDraggingSource {
    var windowID: UUID?
    var dragVisibility: @MainActor (Bool) -> Void = { _ in }
    func draggingSession(_ session: NSDraggingSession, endedAt screenPoint: NSPoint, operation: NSDragOperation) {
        dragVisibility(false)
    }
    func draggingSession(_ session: NSDraggingSession, sourceOperationMaskFor context: NSDraggingContext)
        -> NSDragOperation
    { .move }
    private(set) var mouseClickCount = 1
    override func mouseDown(with event: NSEvent) {
        mouseClickCount = event.clickCount
        defer { mouseClickCount = 1 }
        guard isEnabled, let window, let windowID else { return }
        let initial = event.locationInWindow
        while let next = window.nextEvent(
            matching: [.leftMouseDragged, .leftMouseUp], until: .distantFuture, inMode: .eventTracking, dequeue: true)
        {
            if next.type == .leftMouseUp {
                if bounds.contains(convert(next.locationInWindow, from: nil)) { sendAction(action, to: target) }
                return
            }
            if hypot(next.locationInWindow.x - initial.x, next.locationInWindow.y - initial.y) >= 5 {
                let item = NSPasteboardItem()
                item.setString(windowID.uuidString, forType: spaceTabsPasteboard)
                let dragging = NSDraggingItem(pasteboardWriter: item)
                let image = NSImage(size: bounds.size)
                if let bitmap = bitmapImageRepForCachingDisplay(in: bounds) {
                    cacheDisplay(in: bounds, to: bitmap)
                    image.addRepresentation(bitmap)
                }
                dragging.setDraggingFrame(bounds, contents: image)
                dragVisibility(true)
                beginDraggingSession(with: [dragging], event: next, source: self)
                return
            }
        }
    }
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
    override var acceptsFirstResponder: Bool { false }
}

/// An AppKit button receives the first click even inside the native scroll view
/// of an inactive, nonactivating panel. It never asks to become a key window.
struct WindowTabButton: NSViewRepresentable {
    let windowID: UUID
    let title: String
    let icon: NSImage?
    let foreground: NSColor
    let dragVisibility: @MainActor (Bool) -> Void
    let action: @MainActor (Int) -> Void
    @Environment(\.isEnabled) private var isEnabled

    @MainActor final class Coordinator: NSObject {
        var action: @MainActor (Int) -> Void
        init(action: @escaping @MainActor (Int) -> Void) { self.action = action }
        @objc func clicked(_ sender: NSButton) { action((sender as? ClickThroughTabButton)?.mouseClickCount ?? 1) }
    }
    func makeCoordinator() -> Coordinator { Coordinator(action: action) }
    func makeNSView(context: Context) -> NSButton {
        let button = ClickThroughTabButton(
            title: title, target: context.coordinator, action: #selector(Coordinator.clicked(_:)))
        button.isBordered = false
        button.setButtonType(.momentaryPushIn)
        button.imagePosition = .imageLeading
        button.imageScaling = .scaleProportionallyDown
        button.cell?.lineBreakMode = .byTruncatingTail
        return button
    }
    func updateNSView(_ button: NSButton, context: Context) {
        context.coordinator.action = action
        (button as? ClickThroughTabButton)?.windowID = windowID
        (button as? ClickThroughTabButton)?.dragVisibility = dragVisibility
        button.attributedTitle = NSAttributedString(
            string: title,
            attributes: [
                .font: NSFont.systemFont(ofSize: 11, weight: .medium), .foregroundColor: foreground,
            ])
        let smallIcon = icon?.copy() as? NSImage
        smallIcon?.size = NSSize(width: 14, height: 14)
        button.image = smallIcon
        button.isEnabled = isEnabled
        button.toolTip = L10n.tr("\(title) · Double-click to fill its zone")
        button.setAccessibilityLabel(title)
    }
    func sizeThatFits(_ proposal: ProposedViewSize, nsView: NSButton, context: Context) -> CGSize? {
        let textWidth = (title as NSString).size(withAttributes: [.font: NSFont.systemFont(ofSize: 11, weight: .medium)]
        ).width
        return CGSize(width: min(230, max(60, textWidth + (icon == nil ? 20 : 40))), height: 26)
    }
}
