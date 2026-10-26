import AppKit
import Carbon
import SpaceTabsCore

@MainActor
final class ShortcutManager {
    enum Action: UInt32, CaseIterable {
        case focusA = 1
        case focusB, previous, next, moveA, moveB, release, showTabs, focusC, moveC, quickSwitcher, zoom, focusLeft,
            focusRight, focusUp, focusDown, moveLeft, moveRight, moveUp, moveDown
        var label: String {
            switch self {
            case .quickSwitcher: L10n.tr("Search Tabs or Profiles · ⌃⌥Space")
            case .zoom: L10n.tr("Zoom / Restore Window · ⌃⌥↩")
            case .focusLeft: L10n.tr("Focus Left · ⌃⌥⌘←")
            case .focusRight: L10n.tr("Focus Right · ⌃⌥⌘→")
            case .focusUp: L10n.tr("Focus Up · ⌃⌥⌘↑")
            case .focusDown: L10n.tr("Focus Down · ⌃⌥⌘↓")
            case .moveLeft: L10n.tr("Move Left · ⌃⌥⌘⇧←")
            case .moveRight: L10n.tr("Move Right · ⌃⌥⌘⇧→")
            case .moveUp: L10n.tr("Move Up · ⌃⌥⌘⇧↑")
            case .moveDown: L10n.tr("Move Down · ⌃⌥⌘⇧↓")
            case .focusA: L10n.tr("Focus A · ⌃⌥1")
            case .focusB: L10n.tr("Focus B · ⌃⌥2")
            case .focusC: L10n.tr("Focus C · ⌃⌥3")
            case .moveC: L10n.tr("Move to C · ⌃⌥⇧3")
            case .previous: L10n.tr("Previous Tab · ⌃⌥←")
            case .next: L10n.tr("Next Tab · ⌃⌥→")
            case .moveA: L10n.tr("Move to A · ⌃⌥⇧←")
            case .moveB: L10n.tr("Move to B · ⌃⌥⇧→")
            case .release: L10n.tr("Release Window · ⌃⌥⌫")
            case .showTabs: L10n.tr("Show Tabs · ⌃⌥T")
            }
        }
        var title: String { label.components(separatedBy: " · ")[0] }
        var defaultBinding: ShortcutBinding {
            let spatial = rawValue >= Action.focusLeft.rawValue
            let moving = [Action.moveA, .moveB, .moveC, .moveLeft, .moveRight, .moveUp, .moveDown].contains(self)
            return ShortcutBinding(
                key: UInt32(key),
                modifiers: UInt32(controlKey | optionKey | (moving ? shiftKey : 0) | (spatial ? cmdKey : 0)))
        }
        var key: Int {
            switch self {
            case .focusA: kVK_ANSI_1
            case .focusB: kVK_ANSI_2
            case .focusC, .moveC: kVK_ANSI_3
            case .previous, .moveA, .focusLeft, .moveLeft: kVK_LeftArrow
            case .next, .moveB, .focusRight, .moveRight: kVK_RightArrow
            case .release: kVK_Delete
            case .showTabs: kVK_ANSI_T
            case .quickSwitcher: kVK_Space
            case .zoom: kVK_Return
            case .focusUp, .moveUp: kVK_UpArrow
            case .focusDown, .moveDown: kVK_DownArrow
            }
        }
    }

    private(set) var registeredActions: Set<Action> = []
    private var refs: [EventHotKeyRef] = []
    private var eventHandler: EventHandlerRef?
    var handler: (Action) -> Void = { _ in }

    static func validateBindings(_ overrides: [UInt32: ShortcutBinding]) throws {
        let all = Action.allCases.map { overrides[$0.rawValue] ?? $0.defaultBinding }
        let bindings = all.filter(\.enabled)
        guard all.allSatisfy(\.isValid), Set(bindings).count == bindings.count else {
            throw ConfigurationError(L10n.tr("Some keyboard shortcuts are duplicated or invalid."))
        }
    }

    /// Preserve existing custom bindings when an update adds a conflicting
    /// default. Only the new/default action becomes unbound, never the user's.
    static func migratedBindings(_ overrides: [UInt32: ShortcutBinding]) -> [UInt32: ShortcutBinding] {
        var result = overrides
        var used = Set(overrides.values.filter(\.enabled))
        for action in Action.allCases where overrides[action.rawValue] == nil {
            var binding = action.defaultBinding
            if used.contains(binding) {
                binding.enabled = false
                result[action.rawValue] = binding
            } else {
                used.insert(binding)
            }
        }
        return result
    }

    func start(bindings: [UInt32: ShortcutBinding] = [:]) -> [String] {
        stop()
        var spec = EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyPressed))
        let error = InstallEventHandler(
            GetEventDispatcherTarget(),
            { _, event, context in
                guard let event, let context else { return OSStatus(eventNotHandledErr) }
                var id = EventHotKeyID()
                let result = GetEventParameter(
                    event, EventParamName(kEventParamDirectObject), EventParamType(typeEventHotKeyID), nil,
                    MemoryLayout<EventHotKeyID>.size, nil, &id)
                guard result == noErr, id.signature == 0x5354_4253, let action = Action(rawValue: id.id) else {
                    return OSStatus(eventNotHandledErr)
                }
                let manager = Unmanaged<ShortcutManager>.fromOpaque(context).takeUnretainedValue()
                Task { @MainActor in manager.handler(action) }
                return noErr
            }, 1, &spec, Unmanaged.passUnretained(self).toOpaque(), &eventHandler)
        guard error == noErr else { return [L10n.tr("Could not register shortcuts (\(error)).")] }
        var failures: [String] = []
        for action in Action.allCases {
            var ref: EventHotKeyRef?
            let binding = bindings[action.rawValue] ?? action.defaultBinding
            guard binding.enabled else { continue }
            let modifiers = binding.modifiers
            let status = RegisterEventHotKey(
                binding.key, modifiers,
                EventHotKeyID(signature: 0x5354_4253, id: action.rawValue),
                GetEventDispatcherTarget(), OptionBits(kEventHotKeyExclusive), &ref)
            if status == noErr, let ref {
                refs.append(ref)
                registeredActions.insert(action)
            } else {
                let detail =
                    status == eventHotKeyExistsErr
                    ? L10n.tr("this shortcut is already used by another app or instance")
                    : L10n.tr("macOS rejected the shortcut registration")
                failures.append("\(action.title) · \(binding.display): \(detail) (\(status)).")
            }
        }
        return failures
    }

    func stop() {
        for ref in refs { UnregisterEventHotKey(ref) }
        refs.removeAll()
        registeredActions.removeAll()
        if let eventHandler { RemoveEventHandler(eventHandler) }
        eventHandler = nil
    }
}
