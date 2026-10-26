import AppKit
import QuartzCore
import SpaceTabsCore
import SwiftUI

/// Floating, nonactivating panels must accept clicks while another app owns
/// the keyboard focus. In particular, plain SwiftUI buttons need first-mouse
/// acceptance instead of relying on the panel becoming the key window.
final class TabBarHostingView<Content: View>: NSHostingView<Content> {
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
}

@MainActor
final class PanelController {
    private var bars: [Zone: NSPanel] = [:]
    private var demos: [Zone: NSPanel] = [:]
    private var rowDivider: NSPanel?
    private var rowResizeHandle: ColumnResizeHandleView?
    private var visibleZones: [Zone] = [.a, .b]
    private var divider: NSPanel?
    private var resizeHandle: ColumnResizeHandleView?
    private var resizeGuide: NSPanel?

    private var visibility = TabBarVisibility()
    private var screen: NSScreen?
    private var enabled = false
    private var menuTracking = false
    private var tabDragging = false
    private var edgeLatched = false
    private var revealAtTopEdge = false
    private var globalMouseMonitor: Any?
    private var localMouseMonitor: Any?
    private var menuObservers: [NSObjectProtocol] = []
    private var expiryTask: Task<Void, Never>?
    private var visibilityTargets: [ObjectIdentifier: Bool] = [:]
    private var transitionRevisions: [ObjectIdentifier: UInt64] = [:]
    private var now: TimeInterval { ProcessInfo.processInfo.systemUptime }

    func start() {
        guard globalMouseMonitor == nil else { return }
        let mask: NSEvent.EventTypeMask = [
            .mouseMoved, .leftMouseDragged, .leftMouseUp,
            .leftMouseDown, .rightMouseDown, .otherMouseDown,
        ]
        globalMouseMonitor = NSEvent.addGlobalMonitorForEvents(matching: mask) { [weak self] event in
            MainActor.assumeIsolated { self?.handleMouseEvent(event) }
        }
        localMouseMonitor = NSEvent.addLocalMonitorForEvents(matching: mask) { [weak self] event in
            MainActor.assumeIsolated { self?.handleMouseEvent(event) }
            return event
        }
        for name in [NSMenu.didBeginTrackingNotification, NSMenu.didEndTrackingNotification] {
            let token = NotificationCenter.default.addObserver(forName: name, object: nil, queue: .main) {
                [weak self] event in
                let tracking = event.name == NSMenu.didBeginTrackingNotification
                MainActor.assumeIsolated {
                    guard let self else { return }
                    self.menuTracking = tracking
                    self.visibility.setMenuTracking(tracking || self.tabDragging, at: self.now)
                    self.scheduleExpiry()
                }
            }
            menuObservers.append(token)
        }
    }

    func setTabDragging(_ dragging: Bool) {
        tabDragging = dragging
        if dragging { visibility.reveal(at: now) }
        visibility.setMenuTracking(menuTracking || tabDragging, at: now)
        updateBarVisibility()
        scheduleExpiry()
    }

    func reveal() {
        guard enabled else { return }
        visibility.reveal(at: now)
        updateBarVisibility()
        mouseMoved()
        scheduleExpiry()
    }

    private var tabPanels: [NSPanel] {
        visibleZones.compactMap { bars[$0] }
            + [divider, visibleZones.contains(.c) ? rowDivider : nil].compactMap { $0 }
    }

    private func handleMouseEvent(_ event: NSEvent) {
        guard visibility.autoHide else { return }
        switch event.type {
        case .leftMouseDown, .rightMouseDown, .otherMouseDown:
            guard enabled, visibility.isVisible else { return }
            let pointer = NSEvent.mouseLocation
            let frames = tabPanels.filter { $0.isVisible && !$0.ignoresMouseEvents }.map(\.frame)
            visibility.pointerDown(at: pointer, interactiveFrames: frames)
            if !visibility.isVisible {
                // A click at the screen edge must not reveal the bars again on
                // mouse-up before the pointer has left that edge.
                if let screen {
                    edgeLatched = TabBarVisibility.atTopEdge(pointer, screen: screen.frame, dragging: false)
                }
                scheduleExpiry()
                updateBarVisibility()
            }
        default: mouseMoved()
        }
    }

    private func mouseMoved() {
        guard enabled, visibility.autoHide, let screen else { return }
        let pointer = NSEvent.mouseLocation
        let dragging = NSEvent.pressedMouseButtons != 0
        let edge = revealAtTopEdge && TabBarVisibility.atTopEdge(pointer, screen: screen.frame, dragging: dragging)
        if edge && !edgeLatched {
            edgeLatched = true
            visibility.reveal(at: now)
            updateBarVisibility()
        } else if !edge {
            edgeLatched = false
        }
        let inside = visibility.isVisible && tabPanels.contains { $0.frame.contains(pointer) }
        visibility.setHovered(inside || (visibility.isVisible && dragging), at: now)
        scheduleExpiry()
    }

    private func scheduleExpiry() {
        // Do not recreate the timeout on every mouse event.
        guard visibility.canExpire, let deadline = visibility.deadline else {
            expiryTask?.cancel()
            expiryTask = nil
            scheduledDeadline = nil
            return
        }
        guard scheduledDeadline != deadline else { return }
        expiryTask?.cancel()
        scheduledDeadline = deadline
        expiryTask = Task { [weak self] in
            do { try await Task.sleep(for: .seconds(max(0, deadline - (self?.now ?? deadline)))) } catch { return }
            guard let self else { return }
            // Query the pointer once at expiry in case a move event was missed.
            mouseMoved()
            visibility.expire(at: now)
            updateBarVisibility()
            if !visibility.isVisible {
                expiryTask = nil
                scheduledDeadline = nil
            }
        }
    }
    private var scheduledDeadline: TimeInterval?

    private func updateBarVisibility() {
        for panel in tabPanels { setVisible(panel, visible: enabled && visibility.isVisible, animated: true) }
    }

    private func setVisible(_ panel: NSPanel, visible: Bool, animated: Bool) {
        let id = ObjectIdentifier(panel)
        if animated, visibilityTargets[id] == visible { return }
        visibilityTargets[id] = visible
        let revision = transitionRevisions[id, default: 0] &+ 1
        transitionRevisions[id] = revision
        // Outside clicks pass straight through, including during fade-out.
        panel.ignoresMouseEvents = !visible
        if visible && !panel.isVisible {
            panel.alphaValue = 0
            panel.orderFrontRegardless()
        }
        guard animated, panel.isVisible, !NSWorkspace.shared.accessibilityDisplayShouldReduceMotion else {
            panel.alphaValue = visible ? 1 : 0
            if !visible { panel.orderOut(nil) }
            return
        }
        NSAnimationContext.runAnimationGroup { context in
            context.duration = visible ? 0.24 : 0.18
            context.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
            panel.animator().alphaValue = visible ? 1 : 0
        } completionHandler: { [weak self, weak panel] in
            Task { @MainActor in
                guard let self, let panel, self.transitionRevisions[id] == revision else { return }
                // A previous hide finishing after a new reveal must not remove
                // the now-visible window. Only the latest transition may finish.
                if !visible { panel.orderOut(nil) }
            }
        }
    }

    func stop() {
        hide()
        if let globalMouseMonitor { NSEvent.removeMonitor(globalMouseMonitor) }
        if let localMouseMonitor { NSEvent.removeMonitor(localMouseMonitor) }
        globalMouseMonitor = nil
        localMouseMonitor = nil
        for observer in menuObservers { NotificationCenter.default.removeObserver(observer) }
        menuObservers.removeAll()
    }

    func update(model: AppModel, screen: NSScreen) {
        self.screen = screen
        visibleZones = model.activeZones
        enabled = !model.managementSuspended && !model.terminating
        if revealAtTopEdge != model.revealTabsAtTopEdge { edgeLatched = false }
        revealAtTopEdge = model.revealTabsAtTopEdge
        visibility.setAutoHide(model.autoHideTabBars, at: now)
        if enabled && !model.autoHideTabBars { visibility.reveal(at: now) }
        scheduleExpiry()
        let geometry = model.zoneGeometry(on: screen)
        guard let headers = LayoutEngine().columnHeaders(for: geometry) else {
            hide()
            return
        }
        if divider == nil {
            let panel = makePanel(floating: true)
            panel.hasShadow = true
            let handle = ColumnResizeHandleView(model: model)
            resizeHandle = handle
            panel.contentView = handle
            divider = panel
        }
        if let divider {
            resizeHandle?.refreshLocalization()
            resizeHandle?.needsDisplay = true
            present(divider, frame: headers.handle, visible: enabled && visibility.isVisible, animated: true)
        }
        if let frame = headers.rowHandle {
            if rowDivider == nil {
                let panel = makePanel(floating: true)
                let handle = ColumnResizeHandleView(model: model, rows: true)
                rowResizeHandle = handle
                panel.contentView = handle
                rowDivider = panel
            }
            if let rowDivider {
                rowResizeHandle?.refreshLocalization()
                rowResizeHandle?.needsDisplay = true
                present(rowDivider, frame: frame, visible: enabled && visibility.isVisible, animated: true)
            }
        } else if let rowDivider {
            setVisible(rowDivider, visible: false, animated: false)
        }
        let preview = model.zoneGeometry(
            on: screen,
            ratio: model.resizingRows ? nil : model.columnResizePreview,
            rowRatio: model.resizingRows ? model.columnResizePreview : nil)
        if model.resizingColumns, let previewLeft = preview[.a] {
            let guide = resizeGuide ?? makePanel(floating: true)
            if resizeGuide == nil {
                guide.contentView = NSHostingView(rootView: ColumnResizeGuide(model: model))
                resizeGuide = guide
            }
            let center = model.layoutTemplate == .splitRight ? previewLeft.content.minX : previewLeft.content.maxX
            let frame: CGRect
            if model.resizingRows, let lower = preview[.c] {
                frame = CGRect(x: lower.bar.minX, y: lower.bar.maxY - 2, width: lower.bar.width, height: 4)
            } else {
                frame = CGRect(
                    x: center - 2, y: model.layoutVisibleFrame(on: screen).minY, width: 4,
                    height: max(0, previewLeft.bar.minY - model.layoutVisibleFrame(on: screen).minY))
            }
            present(guide, frame: frame, visible: true)
            guide.ignoresMouseEvents = true
        } else if let resizeGuide {
            setVisible(resizeGuide, visible: false, animated: false)
        }
        for zone in Zone.allCases {
            guard let rects = geometry[zone] else {
                if let bar = bars[zone] { setVisible(bar, visible: false, animated: false) }
                demos[zone]?.orderOut(nil)
                continue
            }
            let bar = bars[zone] ?? makePanel(floating: true)
            if bars[zone] == nil {
                bar.contentView = TabBarHostingView(rootView: TabBarView(model: model, zone: zone))
                bars[zone] = bar
            }
            present(
                bar, frame: headers.bars[zone] ?? rects.bar, visible: enabled && visibility.isVisible, animated: true)
            if model.demo && !model.paused {
                let content = demos[zone] ?? makePanel(floating: false)
                if demos[zone] == nil {
                    content.contentView = NSHostingView(rootView: DemoZoneView(model: model, zone: zone))
                    demos[zone] = content
                }
                present(content, frame: rects.content, visible: true)
            } else {
                demos[zone]?.orderOut(nil)
            }
        }
    }

    private func present(_ panel: NSPanel, frame: CGRect, visible: Bool, animated: Bool = false) {
        if panel.frame != frame { panel.setFrame(frame, display: true) }
        setVisible(panel, visible: visible, animated: animated)
    }

    func hide() {
        resizeHandle?.cancelDrag(refresh: false)
        rowResizeHandle?.cancelDrag(refresh: false)
        enabled = false
        edgeLatched = false
        visibility.hide()
        expiryTask?.cancel()
        expiryTask = nil
        scheduledDeadline = nil
        for panel in Array(bars.values) + [divider, rowDivider].compactMap({ $0 }) + Array(demos.values)
            + [resizeGuide].compactMap({ $0 })
        { setVisible(panel, visible: false, animated: false) }
    }

    private func makePanel(floating: Bool) -> NSPanel {
        let panel = NSPanel(
            contentRect: .zero, styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        panel.isMovable = false
        panel.animationBehavior = .none
        panel.acceptsMouseMovedEvents = true
        panel.hidesOnDeactivate = false
        panel.isReleasedWhenClosed = false
        panel.level = floating ? .floating : NSWindow.Level(rawValue: NSWindow.Level.normal.rawValue - 1)
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = true
        panel.collectionBehavior = [.moveToActiveSpace, .fullScreenNone]
        return panel
    }
}
