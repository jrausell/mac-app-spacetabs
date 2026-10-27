import AppKit
import SpaceTabsCore
import SwiftUI

extension Color {
    init(tabColor: TabColor) {
        self.init(.sRGB, red: tabColor.red, green: tabColor.green, blue: tabColor.blue, opacity: 1)
    }
}

extension TabColor {
    init?(color: Color) {
        guard let rgb = NSColor(color).usingColorSpace(.sRGB) else { return nil }
        self.init(
            min(1, max(0, rgb.redComponent)), min(1, max(0, rgb.greenComponent)), min(1, max(0, rgb.blueComponent)))
    }
}

struct TabAppearanceSettings: View {
    private let localization = AppLocalization.shared
    @Bindable var model: AppModel
    @Environment(\.colorScheme) private var systemScheme

    private func updateAppearance(_ change: (inout TabAppearance) -> Void) {
        var appearance = model.tabAppearance
        change(&appearance)
        model.tabAppearance = appearance
        model.appearancePreferenceChanged()
    }

    private func colorBinding(_ keyPath: WritableKeyPath<TabAppearance, TabColor>) -> Binding<Color> {
        Binding(
            get: { Color(tabColor: model.tabAppearance[keyPath: keyPath]) },
            set: { color in
                if let color = TabColor(color: color) { updateAppearance { $0[keyPath: keyPath] = color } }
            })
    }
    private var backgroundBinding: Binding<Color> {
        Binding(
            get: { Color(tabColor: model.tabAppearance.palette(systemIsDark: systemScheme == .dark).background) },
            set: { color in
                if let color = TabColor(color: color) { updateAppearance { $0.backgroundOverride = color } }
            })
    }

    var body: some View {
        let _ = localization.language
        GroupBox(L10n.tr("Tab Bar and Zone Colors")) {
            VStack(alignment: .leading, spacing: 16) {
                Picker(
                    L10n.tr("Appearance"),
                    selection: Binding(
                        get: { model.tabAppearance.mode },
                        set: { mode in
                            updateAppearance {
                                $0.mode = mode
                                $0.backgroundOverride = nil
                            }
                        })
                ) {
                    Text(L10n.tr("Auto · Opposite to macOS")).tag(TabBarMode.automatic)
                    Text(L10n.tr("Light · White Background")).tag(TabBarMode.light)
                    Text(L10n.tr("Dark · Black Background")).tag(TabBarMode.dark)
                }
                Grid(alignment: .leading, horizontalSpacing: 32, verticalSpacing: 14) {
                    GridRow {
                        ColorPicker(L10n.tr("Tab Bar Background"), selection: backgroundBinding, supportsOpacity: false)
                        Button(L10n.tr("Theme Background")) { updateAppearance { $0.backgroundOverride = nil } }
                            .disabled(model.tabAppearance.backgroundOverride == nil)
                    }
                    GridRow {
                        ColorPicker(L10n.tr("A Accent"), selection: colorBinding(\.colorA), supportsOpacity: false)
                        ColorPicker(L10n.tr("B Accent"), selection: colorBinding(\.colorB), supportsOpacity: false)
                    }
                    if model.layoutTemplate != .twoColumns {
                        GridRow {
                            ColorPicker(L10n.tr("C Accent"), selection: colorBinding(\.colorC), supportsOpacity: false)
                        }
                    }
                    GridRow {
                        ColorPicker(
                            L10n.tr("Drag Preview Borders"), selection: colorBinding(\.dragBorderColor),
                            supportsOpacity: false)
                    }
                }
                HStack {
                    Text(L10n.tr("Background Opacity"))
                    Slider(
                        value: Binding(
                            get: { model.tabAppearance.backgroundOpacity },
                            set: { opacity in updateAppearance { $0.backgroundOpacity = opacity } }),
                        in: 0...1, step: 0.01
                    ).accessibilityLabel(L10n.tr("Background Opacity"))
                    Text(model.tabAppearance.backgroundOpacity, format: .percent.precision(.fractionLength(0)))
                        .monospacedDigit().frame(minWidth: 44, alignment: .trailing)
                }
                Text(
                    L10n.tr(
                        "Auto uses the opposite macOS appearance. Background opacity affects only the bar background. Text and zone labels adjust their contrast automatically."
                    )
                )
                .font(.caption).foregroundStyle(.secondary)
            }.padding(10)
        }
    }
}
