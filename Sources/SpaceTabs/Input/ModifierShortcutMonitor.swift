import AppKit
import Carbon
import SpaceTabsCore

/// Passive observation leaves ordinary shortcuts and pointer gestures intact.
@MainActor
final class ModifierShortcutMonitor {
    private let bindings: [ShortcutManager.Action: ShortcutBinding]
    private let handler: (ShortcutManager.Action) -> Void
    private var state = ModifierTapState()
    private var heldKeys: Set<UInt16> = []
    private var globalMonitor: Any?
    private var localMonitor: Any?

    init(bindings: [ShortcutManager.Action: ShortcutBinding], handler: @escaping (ShortcutManager.Action) -> Void) {
        self.bindings = bindings
        self.handler = handler
    }

    func start() -> Bool {
        state.cancel()  // Require a clean release after installing or changing bindings.
        let mask: NSEvent.EventTypeMask = [
            .flagsChanged, .keyDown, .keyUp, .leftMouseDown, .rightMouseDown, .otherMouseDown,
            .leftMouseDragged, .rightMouseDragged, .otherMouseDragged, .scrollWheel,
        ]
        globalMonitor = NSEvent.addGlobalMonitorForEvents(matching: mask) { [weak self] event in
            MainActor.assumeIsolated { self?.handle(event) }
        }
        localMonitor = NSEvent.addLocalMonitorForEvents(matching: mask) { [weak self] event in
            self?.handle(event)
            return event
        }
        // No keys are held on a normal startup, so the first tap can be recognized.
        handleFlags(NSEvent.modifierFlags, interrupted: NSEvent.pressedMouseButtons != 0)
        guard globalMonitor != nil, localMonitor != nil else {
            stop()
            return false
        }
        return true
    }

    func cancel() { state.cancel() }

    private func handle(_ event: NSEvent) {
        if event.type == .keyDown { heldKeys.insert(event.keyCode) }
        if event.type == .keyUp { heldKeys.remove(event.keyCode) }
        handleFlags(
            event.modifierFlags,
            interrupted: event.type != .flagsChanged || !heldKeys.isEmpty || NSEvent.pressedMouseButtons != 0)
    }

    private func handleFlags(_ flags: NSEvent.ModifierFlags, interrupted: Bool) {
        var modifiers: UInt32 = 0
        for (flag, mask) in [
            (NSEvent.ModifierFlags.control, controlKey), (.option, optionKey), (.command, cmdKey), (.shift, shiftKey),
        ] {
            if flags.contains(flag) { modifiers |= UInt32(mask) }
        }
        let targets = Set(bindings.values.map(\.modifiers))
        guard
            let match = state.update(
                modifiers: modifiers, targets: targets, interrupted: interrupted || flags.contains(.function)),
            let action = bindings.first(where: { $0.value.modifiers == match })?.key
        else { return }
        handler(action)
    }

    func stop() {
        if let globalMonitor { NSEvent.removeMonitor(globalMonitor) }
        if let localMonitor { NSEvent.removeMonitor(localMonitor) }
        globalMonitor = nil
        localMonitor = nil
        state = ModifierTapState()
        heldKeys.removeAll()
    }
}
