import AppKit
import SpaceTabsCore
import SwiftUI

@MainActor
final class WindowDragController {
    private weak var model: AppModel?
    private var globalMonitor: Any?
    private var localMonitor: Any?
    private var state = ZoneDragState()
    private var session = UUID()
    private var candidate: UUID?
    private var captureAttempted = false
    private var probeTask: Task<Void, Never>?
    private var dropTask: Task<Void, Never>?
    private var nextProbe: TimeInterval = 0
    private var panels: [Zone: NSPanel] = [:]
    private var displayedBorderColor: TabColor?
    private var displayedHover: Zone?
    private var displayedFrames: [Zone: CGRect] = [:]

    private var available: Bool {
        guard let model else { return false }
        return model.trusted && !model.managementSuspended && !model.terminating && !model.demo
            && !model.resizingColumns
    }
    private var frames: [Zone: CGRect] {
        guard let model, let screen = model.screen else { return [:] }
        return model.zoneGeometry(on: screen).mapValues { $0.content.union($0.bar) }
    }
    private func modifierHeld(_ flags: NSEvent.ModifierFlags) -> Bool {
        flags.intersection([.command, .shift, .option, .control]) == [.command, .shift]
    }

    func start(model: AppModel) {
        self.model = model
        guard globalMonitor == nil else { return }
        let mask: NSEvent.EventTypeMask = [
            .leftMouseDown, .leftMouseDragged, .leftMouseUp, .flagsChanged, .rightMouseDown,
        ]
        globalMonitor = NSEvent.addGlobalMonitorForEvents(matching: mask) { [weak self] event in
            MainActor.assumeIsolated { self?.handle(event) }
        }
        localMonitor = NSEvent.addLocalMonitorForEvents(matching: mask) { [weak self] event in
            self?.handle(event)
            return event  // Observation only: never consume or synthesize input.
        }
    }

    func update() {
        guard available else {
            cancel()
            return
        }
        if !displayedFrames.isEmpty && displayedFrames != frames { cancel() } else if state.isVisible { draw() }
    }

    private func handle(_ event: NSEvent) {
        guard available else {
            cancel()
            return
        }
        switch event.type {
        case .leftMouseDown:
            model?.cancelWorkspacePresentation()
            cancel()
            state.begin()
        case .leftMouseDragged:
            guard state.tracking else { return }
            state.update(
                pointer: NSEvent.mouseLocation, modifierHeld: modifierHeld(event.modifierFlags), windowMoved: false,
                zones: frames)
            draw()
            probeIfNeeded()
        case .flagsChanged:
            guard state.tracking else { return }
            guard NSEvent.pressedMouseButtons & 1 != 0 else {
                cancel()
                return
            }
            state.modifiersChanged(held: modifierHeld(event.modifierFlags))
            if state.dragging {
                state.update(
                    pointer: NSEvent.mouseLocation, modifierHeld: modifierHeld(event.modifierFlags), windowMoved: false,
                    zones: frames)
                probeIfNeeded()
            }
            draw()  // Releasing the chord hides targets before mouse-up.
        case .leftMouseUp:
            finish(event)
        case .rightMouseDown:
            cancel()
        default: break
        }
    }

    private func probeIfNeeded() {
        guard state.dragging, state.modifierHeld, !state.confirmedWindowMove, probeTask == nil,
            ProcessInfo.processInfo.systemUptime >= nextProbe, let model,
            let primary = NSScreen.screens.first
        else { return }
        if candidate == nil && captureAttempted { return }
        nextProbe = ProcessInfo.processInfo.systemUptime + 0.08
        let generation = session
        let point = NSEvent.mouseLocation
        let axPoint = CGPoint(x: point.x, y: primary.frame.maxY - point.y)
        let manager = model.windowManager
        probeTask = Task { [weak self] in
            guard let self, session == generation, state.tracking, !Task.isCancelled else { return }
            var token = candidate
            if token == nil {
                captureAttempted = true
                token = await manager.captureDragCandidate(at: axPoint)
            }
            guard session == generation, state.tracking, !Task.isCancelled else {
                if let token { await manager.discardDragCandidate(token) }
                return
            }
            candidate = token
            var moved = if let token { await manager.dragCandidateMoved(token) } else { false }
            if !moved, let token {
                // A short drag may stop producing pointer events before the
                // native window server has committed its first new position.
                do { try await Task.sleep(for: .milliseconds(60)) } catch { return }
                guard session == generation, state.tracking else { return }
                moved = await manager.dragCandidateMoved(token)
            }
            guard session == generation, state.tracking, !Task.isCancelled else { return }
            probeTask = nil
            state.update(
                pointer: NSEvent.mouseLocation, modifierHeld: state.modifierHeld,
                windowMoved: moved, zones: frames)
            draw()
            // Once movement is confirmed, only pointer events update previews.
            // No more AX reads are needed until the user drops the window.
        }
    }

    private func finish(_ event: NSEvent) {
        if state.dragging {
            state.update(
                pointer: NSEvent.mouseLocation, modifierHeld: modifierHeld(event.modifierFlags), windowMoved: false,
                zones: frames)
        }
        let destination = state.end(modifierHeld: modifierHeld(event.modifierFlags))
        let destinationFrame = destination.flatMap { frames[$0] }
        let token = candidate
        candidate = nil
        session = UUID()
        probeTask?.cancel()
        probeTask = nil
        hide()
        guard let token, let model else { return }
        let manager = model.windowManager
        guard let destination else {
            Task { await manager.discardDragCandidate(token) }
            return
        }
        let desktop = model.desktopRevision
        dropTask = Task { [weak self, weak model] in
            do {
                // Let the owning app finish its native mouse-up before AX writes.
                try await Task.sleep(for: .milliseconds(60))
                guard let self, let model else {
                    await manager.discardDragCandidate(token)
                    return
                }
                for _ in 0..<50 where model.busy {
                    try await Task.sleep(for: .milliseconds(20))
                }
                guard !Task.isCancelled, available, model.desktopRevision == desktop,
                    frames[destination] == destinationFrame
                else {
                    await manager.discardDragCandidate(token)
                    return
                }
                let snapshot = try await manager.finishDragCandidate(token)
                guard !Task.isCancelled, available, model.desktopRevision == desktop,
                    frames[destination] == destinationFrame
                else { return }
                model.assignDraggedWindow(snapshot, to: destination)
            } catch is CancellationError {
                await manager.discardDragCandidate(token)
            } catch {
                await manager.discardDragCandidate(token)
                if !Task.isCancelled {
                    model?.message = L10n.tr("Could not assign the dragged window: \(error.localizedDescription)")
                }
            }
        }
    }

    private func draw() {
        guard state.isVisible else {
            hide()
            return
        }
        let geometry = frames
        guard !geometry.isEmpty else {
            hide()
            return
        }
        let borderColor = model?.tabAppearance.dragBorderColor ?? .white
        if displayedFrames == geometry && displayedHover == state.hovered && displayedBorderColor == borderColor {
            return
        }
        for zone in Zone.allCases {
            guard let frame = geometry[zone] else {
                panels[zone]?.orderOut(nil)
                continue
            }
            let panel: NSPanel
            if let existing = panels[zone] {
                panel = existing
            } else {
                panel = NSPanel(
                    contentRect: .zero, styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
                panel.backgroundColor = .clear
                panel.isOpaque = false
                panel.ignoresMouseEvents = true
                panel.isMovable = false
                panel.hidesOnDeactivate = false
                panel.isReleasedWhenClosed = false
                panel.level = NSWindow.Level(rawValue: NSWindow.Level.floating.rawValue + 1)
                panel.hasShadow = false
                panel.collectionBehavior = [.moveToActiveSpace, .fullScreenNone]
                panel.setAccessibilityElement(false)
                panels[zone] = panel
            }
            panel.contentView = NSHostingView(
                rootView: ZoneDropOverlay(zone: zone, highlighted: state.hovered == zone, borderColor: borderColor))
            if panel.frame != frame { panel.setFrame(frame, display: true) }
            if !panel.isVisible { panel.orderFrontRegardless() }
        }
        displayedBorderColor = borderColor
        displayedFrames = geometry
        displayedHover = state.hovered
    }

    private func hide() {
        guard !displayedFrames.isEmpty || panels.values.contains(where: { $0.isVisible }) else { return }
        for panel in panels.values { panel.orderOut(nil) }
        displayedFrames = [:]
        displayedHover = nil
        displayedBorderColor = nil
    }
    private func cancel() {
        session = UUID()
        state.cancel()
        captureAttempted = false
        nextProbe = 0
        probeTask?.cancel()
        probeTask = nil
        dropTask?.cancel()
        dropTask = nil
        if let candidate, let manager = model?.windowManager {
            Task { await manager.discardDragCandidate(candidate) }
        }
        candidate = nil
        hide()
    }
    func stop() {
        cancel()
        if let globalMonitor { NSEvent.removeMonitor(globalMonitor) }
        if let localMonitor { NSEvent.removeMonitor(localMonitor) }
        globalMonitor = nil
        localMonitor = nil
    }
}

struct ZoneDropOverlay: View {
    private let localization = AppLocalization.shared
    let zone: Zone
    let highlighted: Bool
    let borderColor: TabColor
    private var tint: Color { Color(tabColor: borderColor) }

    var body: some View {
        let _ = localization.language
        RoundedRectangle(cornerRadius: 16)
            .fill(tint.opacity(highlighted ? 0.14 : 0.025))
            .overlay(
                RoundedRectangle(cornerRadius: 16).strokeBorder(
                    tint.opacity(highlighted ? 0.95 : 0.42), lineWidth: highlighted ? 5 : 2
                )
                .shadow(color: .black.opacity(0.3), radius: 3)
            )
            .overlay {
                if highlighted {
                    Text(L10n.tr("Release to assign")).font(.callout)
                        .foregroundStyle(.white).padding(16)
                        .background(.black.opacity(0.6), in: RoundedRectangle(cornerRadius: 12))
                }
            }
            .overlay(alignment: .topLeading) {
                Text(zone.title)
                    .font(.system(size: 24, weight: .bold, design: .rounded))
                    .foregroundStyle(borderColor.usesLightText ? Color.white : Color.black)
                    .frame(width: 44, height: 44)
                    .background(tint, in: RoundedRectangle(cornerRadius: 10))
                    .shadow(color: .black.opacity(0.3), radius: 3, y: 2)
                    .padding(12)
            }
            .padding(5)
            .allowsHitTesting(false)
            .accessibilityHidden(true)
    }
}
