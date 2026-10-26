import Carbon
import SpaceTabsCore
import SwiftUI

extension ShortcutBinding {
    static var keys: [(UInt32, String)] {
        [
            (0, "A"), (11, "B"), (8, "C"), (2, "D"), (14, "E"), (3, "F"), (5, "G"), (4, "H"), (34, "I"), (38, "J"),
            (40, "K"), (37, "L"), (46, "M"),
            (45, "N"), (31, "O"), (35, "P"), (12, "Q"), (15, "R"), (1, "S"), (17, "T"), (32, "U"), (9, "V"), (13, "W"),
            (7, "X"), (16, "Y"), (6, "Z"),
            (18, "1"), (19, "2"), (20, "3"), (21, "4"), (23, "5"), (22, "6"), (26, "7"), (28, "8"), (25, "9"),
            (29, "0"),
            (123, "←"), (124, "→"), (125, "↓"), (126, "↑"), (51, "⌫"), (117, "⌦"), (49, L10n.tr("Space")), (36, "↩"),
            (48, "⇥"),
            (122, "F1"), (120, "F2"), (99, "F3"), (118, "F4"), (96, "F5"), (97, "F6"), (98, "F7"), (100, "F8"),
            (101, "F9"),
            (109, "F10"), (103, "F11"), (111, "F12"),
        ]
    }
    var display: String {
        guard enabled else { return L10n.tr("No Shortcut") }
        return [(UInt32(controlKey), "⌃"), (UInt32(optionKey), "⌥"), (UInt32(shiftKey), "⇧"), (UInt32(cmdKey), "⌘")]
            .filter { modifiers & $0.0 != 0 }.map(\.1).joined()
            + (Self.keys.first { $0.0 == key }?.1 ?? L10n.tr("Key \(key)"))
    }
}

struct ShortcutEditor: View {
    private let localization = AppLocalization.shared
    let model: AppModel
    let action: ShortcutManager.Action
    @State private var editing = false
    @State private var enabled = true
    @State private var key: UInt32 = 0
    @State private var modifiers: UInt32 = 0
    private var binding: ShortcutBinding { model.preferences.shortcuts[action.rawValue] ?? action.defaultBinding }
    var body: some View {
        let _ = localization.language
        Button(binding.display) {
            enabled = binding.enabled
            key = binding.key
            modifiers = binding.modifiers
            editing = true
        }
        .font(.system(.body, design: .monospaced)).frame(minWidth: 90)
        .popover(isPresented: $editing) {
            VStack(alignment: .leading, spacing: 16) {
                Text(action.title).font(.headline)
                Toggle(L10n.tr("Enable this shortcut"), isOn: $enabled)
                HStack {
                    modifier(L10n.tr("⌃ Control"), UInt32(controlKey))
                    modifier(L10n.tr("⌥ Option"), UInt32(optionKey))
                }
                HStack {
                    modifier(L10n.tr("⇧ Shift"), UInt32(shiftKey))
                    modifier(L10n.tr("⌘ Command"), UInt32(cmdKey))
                }
                Picker(L10n.tr("Key"), selection: $key) {
                    ForEach(ShortcutBinding.keys, id: \.0) { item in Text(item.1).tag(item.0) }
                }
                Text(L10n.tr("Include Control, Option, or Command. macOS reports shortcuts that are already in use."))
                    .font(.caption).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
                HStack {
                    Button(L10n.tr("Cancel")) { editing = false }.keyboardShortcut(.cancelAction)
                    Spacer()
                    Button(L10n.tr("Save")) {
                        model.setShortcut(
                            action.rawValue, binding: ShortcutBinding(key: key, modifiers: modifiers, enabled: enabled))
                        editing = false
                    }.buttonStyle(.borderedProminent)
                        .disabled(!ShortcutBinding(key: key, modifiers: modifiers).isValid)
                }
            }.padding(20).frame(width: 330)
        }
    }
    private func modifier(_ title: String, _ mask: UInt32) -> some View {
        Toggle(
            title,
            isOn: Binding(
                get: { modifiers & mask != 0 },
                set: { on in
                    if on { modifiers |= mask } else { modifiers &= ~mask }
                })
        ).toggleStyle(.checkbox).frame(width: 140, alignment: .leading)
    }
}
