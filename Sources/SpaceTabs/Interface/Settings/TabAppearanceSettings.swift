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

    private func colorBinding(_ keyPath: WritableKeyPath<TabAppearance, TabColor>) -> Binding<Color> {
        Binding(
            get: { Color(tabColor: model.tabAppearance[keyPath: keyPath]) },
            set: { color in
                if let color = TabColor(color: color) { model.tabAppearance[keyPath: keyPath] = color }
            })
    }
    private var backgroundBinding: Binding<Color> {
        Binding(
            get: { Color(tabColor: model.tabAppearance.palette(systemIsDark: systemScheme == .dark).background) },
            set: { color in
                if let color = TabColor(color: color) { model.tabAppearance.backgroundOverride = color }
            })
    }

    var body: some View {
        let _ = localization.language
        GroupBox(L10n.tr("Tab Bar and Zone Colors")) {
            VStack(alignment: .leading, spacing: 16) {
                Picker(L10n.tr("Appearance"), selection: $model.tabAppearance.mode) {
                    Text(L10n.tr("Auto · Opposite to macOS")).tag(TabBarMode.automatic)
                    Text(L10n.tr("Light · White Background")).tag(TabBarMode.light)
                    Text(L10n.tr("Dark · Black Background")).tag(TabBarMode.dark)
                }
                Grid(alignment: .leading, horizontalSpacing: 32, verticalSpacing: 14) {
                    GridRow {
                        ColorPicker(L10n.tr("Tab Bar Background"), selection: backgroundBinding, supportsOpacity: false)
                        Button(L10n.tr("Theme Background")) { model.tabAppearance.backgroundOverride = nil }
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
                Text(
                    L10n.tr(
                        "Auto uses the opposite macOS appearance. Bar backgrounds use 90% opacity. Text and zone labels adjust their contrast automatically."
                    )
                )
                .font(.caption).foregroundStyle(.secondary)
            }.padding(10)
        }
        .onChange(of: model.tabAppearance.mode) {
            if model.remoteSettings?.state?.tabAppearance.mode != model.tabAppearance.mode {
                model.tabAppearance.backgroundOverride = nil
            }
        }
        .onChange(of: model.tabAppearance) { model.appearancePreferenceChanged() }
    }
}
