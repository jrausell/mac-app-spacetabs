import AppKit
import SpaceTabsCore
import SwiftUI

/// Filter only the chord. AX, UI rendering and placement happen outside the
/// callback. Event coordinates come directly from Quartz, never NSEvent cache.
@MainActor final class RightButtonDragController {
    private weak var model: AppModel?
    private var tap: CFMachPort?
    private var source: CFRunLoopSource?
    private var state = RightDragState()
    private var lease = RightDragCaptureLease()
    private var token: UUID?
    private var capture: Task<Void, Never>?
    private var drop: Task<Void, Never>?
    private var panels: [Zone: NSPanel] = [:]
    private var ghost: NSPanel?
    private var sourceFrame: CGRect?
    private var sourceTitle = L10n.tr("Window")
    private var hover: Zone?
    private var previewVisible = false
    private var attempted = false
    private var drawScheduled = false
    private var revision = 0
    private var interaction = 0
    private var rawDownCount = 0
    private var lastFlags: UInt64 = 0
    private var downCount = 0
    private var motionCount = 0
    private var dragMotionCount = 0
    private var plainMotionCount = 0
    private var captureCount = 0
    private var dropCount = 0
    private var motionReported = false
    private var journal: [String] = []
    private var available: Bool {
        guard let model else { return false }
        return model.preferences.controlRightDrag && model.trusted && !model.managementSuspended && !model.terminating
            && !model.demo && !model.resizingColumns
    }
    private var frames: [Zone: CGRect] {
        guard let model, let screen = model.screen else { return [:] }
        return model.zoneGeometry(on: screen).mapValues { $0.content.union($0.bar) }
    }
    func start(model: AppModel) {
        self.model = model
        update()
    }
    func update() {
        guard let model else { return }
        if !available {
            cancel(reason: L10n.tr("Gesture cancelled. Window management is paused, unavailable, or disabled."))
        }
        if !model.preferences.controlRightDrag || !model.trusted || model.terminating {
            if !state.tracking { removeTap() }
            return
        }
        guard tap == nil, !attempted else { return }
        attempted = true
        let mask = RightDragState.eventTypes.reduce(CGEventMask(0)) { $0 | (CGEventMask(1) << $1.rawValue) }
        let created = CGEvent.tapCreate(
            tap: .cgSessionEventTap, place: .headInsertEventTap, options: .defaultTap,
            eventsOfInterest: mask,
            callback: { _, type, event, context in
                guard let context else { return Unmanaged.passUnretained(event) }
                let controller = Unmanaged<RightButtonDragController>.fromOpaque(context).takeUnretainedValue()
                let consumed = MainActor.assumeIsolated { controller.filter(type, event: event) }
                return consumed ? nil : Unmanaged.passUnretained(event)
            }, userInfo: Unmanaged.passUnretained(self).toOpaque())
        guard let created, let runSource = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, created, 0) else {
            record(
                L10n.tr(
                    "Control + right-drag is unavailable. Check Accessibility access or turn the gesture off and on to retry."
                )
            )
            return
        }
        tap = created
        source = runSource
        CFRunLoopAddSource(CFRunLoopGetMain(), runSource, .commonModes)
        CGEvent.tapEnable(tap: created, enable: true)
        record(
            CGEvent.tapIsEnabled(tap: created)
                ? L10n.tr("Control + right-drag is ready.") : L10n.tr("macOS has not enabled the mouse filter."))
    }
    private func control(_ event: CGEvent) -> Bool {
        event.flags.intersection([.maskControl, .maskShift, .maskAlternate, .maskCommand]) == .maskControl
    }
    private func filter(_ type: CGEventType, event: CGEvent) -> Bool {
        if type == .tapDisabledByTimeout || type == .tapDisabledByUserInput {
            cancel(reason: L10n.tr("macOS interrupted the gesture. The window has not moved."))
            if let tap { CGEvent.tapEnable(tap: tap, enable: true) }
            record(
                tap.map { CGEvent.tapIsEnabled(tap: $0) } == true
                    ? L10n.tr("The filter is active again. The previous gesture was cancelled.")
                    : L10n.tr("macOS disabled the gesture filter."))
            return false
        }
        switch type {
        case .rightMouseDown:
            rawDownCount += 1
            lastFlags = event.flags.rawValue
            if state.tracking {
                state.reset()
                clearCapture()
            }
            guard control(event) else {
                publishDiagnostics()
                return false
            }
            downCount += 1
            guard available, !CGEventSource.buttonState(.combinedSessionState, button: .left) else {
                record(
                    L10n.tr(
                        "Control + right-click received, but window management is unavailable or the left button is held."
                    ))
                return false
            }
            clearCapture()
            let ticket = lease.begin()
            state.begin(at: event.unflippedLocation)
            motionReported = false
            revision = model?.desktopRevision ?? 0
            model?.noteUserInteraction()
            interaction = model?.presentationRevision ?? 0
            record(L10n.tr("Gesture received. Finding the window under the pointer…"))
            let point = event.location
            guard let model else { return true }
            let manager = model.windowManager
            capture = Task { [weak self] in
                do {
                    let result = try await manager.captureRightDrag(at: point)
                    guard let self, lease.accepts(ticket), !Task.isCancelled else {
                        await manager.discardDragCandidate(result.token)
                        return
                    }
                    token = result.token
                    captureCount += 1
                    ghost?.orderOut(nil)
                    ghost?.contentView = nil
                    ghost = nil
                    sourceTitle = result.title.isEmpty ? L10n.tr("Window") : result.title
                    sourceFrame = LayoutEngine.appKitFrame(
                        from: result.initialFrame, primaryDisplayTop: NSScreen.screens.first?.frame.maxY ?? 0)
                    record(
                        lease.pendingDrop
                            ? L10n.tr("Window found. Completing the assignment…")
                            : L10n.tr("Window found. Drag to a zone and release the right button."))
                    scheduleDraw()
                } catch {
                    guard let self, lease.accepts(ticket), !Task.isCancelled else { return }
                    lease.invalidate()
                    state.cancel()
                    record(L10n.tr("Could not capture the window: \(error.localizedDescription)"))
                    scheduleDraw()
                }
            }
            return true
        case .rightMouseDragged, .mouseMoved:
            if state.tracking && !control(event) {
                cancel(reason: L10n.tr("Assignment cancelled when Control was released."))
            }
            guard state.receiveMotion(type, pointer: event.unflippedLocation, controlHeld: control(event)) else {
                return false
            }
            motionCount += 1
            if type == .mouseMoved { plainMotionCount += 1 } else { dragMotionCount += 1 }
            if !available || model?.desktopRevision != revision {
                cancel(reason: L10n.tr("Gesture cancelled because the desktop or manager state changed."))
            }
            if state.dragged && !state.cancelled && !motionReported {
                motionReported = true
                record(
                    L10n.tr(
                        "Pointer movement received from Quartz\(token == nil ? L10n.tr("; waiting for the window capture") : "")."
                    ))
            }
            scheduleDraw()
            return type == .rightMouseDragged
        case .flagsChanged:
            if state.tracking && !control(event) {
                cancel(reason: L10n.tr("Assignment cancelled when Control was released."))
            }
            return false
        case .rightMouseUp:
            guard state.tracking else { return false }
            defer { Task { [weak self] in self?.update() } }
            state.update(at: event.unflippedLocation, controlHeld: control(event))
            let wasDragged = state.dragged
            let wasCancelled = state.cancelled
            let destination =
                available && model?.desktopRevision == revision
                ? state.end(controlHeld: control(event), zones: frames) : nil
            state.reset()
            scheduleDraw()
            guard let destination, let model else {
                clearCapture()
                if !wasCancelled {
                    record(
                        wasDragged
                            ? L10n.tr("Dropped outside a zone. The window has not moved.")
                            : L10n.tr("Click without dragging. The window has not moved."))
                }
                return true
            }
            lease.dropped()
            let ticket = lease.generation
            let desktop = revision
            let userRevision = interaction
            let target = frames[destination]
            let pendingCapture = capture
            record(
                token == nil
                    ? L10n.tr("Dropped in \(destination.title); waiting for the window capture…")
                    : L10n.tr("Dropped in \(destination.title); preparing the assignment…"))
            drop = Task { [weak self, weak model] in
                await pendingCapture?.value
                guard let self, let model, lease.accepts(ticket), !Task.isCancelled else { return }
                let manager = model.windowManager
                guard let candidate = token else {
                    record(L10n.tr("No valid window was found."))
                    lease.invalidate()
                    return
                }
                token = nil
                do {
                    for _ in 0..<50 where model.busy { try await Task.sleep(for: .milliseconds(20)) }
                    guard !Task.isCancelled, lease.accepts(ticket), available, model.desktopRevision == desktop,
                        model.presentationRevision == userRevision, frames[destination] == target
                    else {
                        await manager.discardDragCandidate(candidate)
                        record(L10n.tr("Assignment cancelled by a newer action or layout change."))
                        lease.invalidate()
                        return
                    }
                    let window = try await manager.finishDragCandidate(candidate)
                    guard !Task.isCancelled, lease.accepts(ticket), available, model.desktopRevision == desktop,
                        model.presentationRevision == userRevision
                    else { return }
                    lease.invalidate()
                    dropCount += 1
                    model.assignDraggedWindow(window, to: destination)
                    record(L10n.tr("Assignment requested for zone \(destination.title)."))
                } catch {
                    await manager.discardDragCandidate(candidate)
                    if !Task.isCancelled {
                        record(L10n.tr("Could not assign the window: \(error.localizedDescription)"))
                        model.message = error.localizedDescription
                    }
                    lease.invalidate()
                }
            }
            return true
        default: return false
        }
    }
    private func record(_ stage: String) {
        journal.append("\(Date.now.formatted(date: .omitted, time: .standard)) · \(stage)")
        if journal.count > 12 { journal.removeFirst(journal.count - 12) }
        model?.rightDragStatus = stage
        publishDiagnostics()
    }
    private func publishDiagnostics() {
        let enabled = tap.map { CGEvent.tapIsEnabled(tap: $0) } ?? false
        model?.rightDragDetails =
            L10n.tr(
                "Filter active: \(enabled)\nRight-button presses received: \(rawDownCount)\nLast Quartz modifiers: 0x\(String(lastFlags, radix: 16))\nControl + right-clicks received: \(downCount)\nPointer movements: \(motionCount) (drag: \(dragMotionCount), mouseMoved: \(plainMotionCount))\nWindows captured: \(captureCount)\nAssignments requested: \(dropCount)\n"
            )
            + journal.joined(separator: "\n")
    }
    private func scheduleDraw() {
        guard !drawScheduled else { return }
        drawScheduled = true
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.0 / 60) { [weak self] in
            guard let self else { return }
            self.drawScheduled = false
            self.draw()
        }
    }
    private func draw() {
        // Do not cover the hit-test point with our own AX windows while the
        // asynchronous capture is still resolving the original application.
        guard state.isVisible, token != nil, let origin = state.origin, let sourceFrame, let model else {
            hide()
            return
        }
        let previewFrame = sourceFrame.offsetBy(dx: state.pointer.x - origin.x, dy: state.pointer.y - origin.y)
        if ghost == nil {
            let panel = makePanel()
            panel.level = NSWindow.Level(rawValue: NSWindow.Level.floating.rawValue + 2)
            panel.contentView = NSHostingView(
                rootView: RightDragGhost(title: sourceTitle, color: model.tabAppearance.dragBorderColor))
            ghost = panel
        }
        if let ghost {
            if ghost.frame != previewFrame { ghost.setFrame(previewFrame, display: true) }
            if !ghost.isVisible { ghost.orderFrontRegardless() }
        }
        let hovered = Zone.allCases.first { frames[$0]?.contains(state.pointer) == true }
        if previewVisible && hover == hovered { return }
        hover = hovered
        previewVisible = true
        for zone in model.activeZones {
            guard let frame = frames[zone] else { continue }
            let panel = panels[zone] ?? makePanel()
            panels[zone] = panel
            panel.contentView = NSHostingView(
                rootView: ZoneDropOverlay(
                    zone: zone, highlighted: zone == hovered, borderColor: model.tabAppearance.dragBorderColor))
            panel.setFrame(frame, display: true)
            panel.orderFrontRegardless()
        }
    }
    private func makePanel() -> NSPanel {
        let panel = NSPanel(
            contentRect: .zero, styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.ignoresMouseEvents = true
        panel.hidesOnDeactivate = false
        panel.isReleasedWhenClosed = false
        panel.level = NSWindow.Level(rawValue: NSWindow.Level.floating.rawValue + 1)
        panel.collectionBehavior = [.moveToActiveSpace, .fullScreenNone]
        panel.setAccessibilityElement(false)
        return panel
    }
    private func hide() {
        for panel in panels.values where panel.isVisible { panel.orderOut(nil) }
        if ghost?.isVisible == true { ghost?.orderOut(nil) }
        hover = nil
        previewVisible = false
    }
    private func clearCapture() {
        lease.invalidate()
        capture?.cancel()
        capture = nil
        drop?.cancel()
        drop = nil
        if let token, let model { Task { await model.windowManager.discardDragCandidate(token) } }
        token = nil
        sourceFrame = nil
        scheduleDraw()
    }
    private func cancel(reason: String) {
        let live = (state.tracking && !state.cancelled) || lease.pendingDrop
        state.cancel()
        clearCapture()
        if live { record(reason) }
    }
    private func removeTap() {
        guard tap != nil || attempted else { return }
        if let source { CFRunLoopRemoveSource(CFRunLoopGetMain(), source, .commonModes) }
        if let tap {
            CGEvent.tapEnable(tap: tap, enable: false)
            CFMachPortInvalidate(tap)
        }
        tap = nil
        source = nil
        attempted = false
        record(L10n.tr("Control + right-drag is disabled."))
    }
    func stop() {
        cancel(reason: L10n.tr("Gesture stopped."))
        state.reset()
        hide()
        removeTap()
    }
}

private struct RightDragGhost: View {
    private let localization = AppLocalization.shared
    let title: String
    let color: TabColor
    var body: some View {
        let _ = localization.language
        RoundedRectangle(cornerRadius: 12)
            .fill(Color(tabColor: color).opacity(0.08))
            .overlay(
                RoundedRectangle(cornerRadius: 12).strokeBorder(
                    Color(tabColor: color).opacity(0.9), style: StrokeStyle(lineWidth: 3, dash: [8, 4]))
            )
            .overlay(alignment: .top) {
                Text(title).font(.callout.bold()).lineLimit(1)
                    .foregroundStyle(color.usesLightText ? Color.white : Color.black)
                    .padding(.horizontal, 14).padding(.vertical, 8)
                    .background(Color(tabColor: color), in: Capsule()).padding(12)
            }
            .padding(3)
            .accessibilityHidden(true)
    }
}
