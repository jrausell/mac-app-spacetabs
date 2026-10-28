import AppKit
import SpaceTabsCore
import SwiftUI

struct LayoutTemplatePreview: View {
    private let localization = AppLocalization.shared
    let template: LayoutTemplate
    var ratio: Double = 0.25
    var rowRatio: Double = 0.5
    var body: some View {
        let _ = localization.language
        GeometryReader { proxy in
            let width = max(0, proxy.size.width - 4)
            let height = proxy.size.height
            HStack(spacing: 4) {
                if template == .splitRight {
                    zone(.b).frame(width: width * ratio)
                    secondaryZones(height: height)
                } else {
                    secondaryZones(height: height).frame(width: width * ratio)
                    zone(.b)
                }
            }
        }.accessibilityLabel(template.title)
    }
    private func secondaryZones(height: CGFloat) -> some View {
        VStack(spacing: 4) {
            zone(.a).frame(height: template != .twoColumns ? max(0, height - 4) * rowRatio : height)
            if template != .twoColumns { zone(.c) }
        }
    }
    private func zone(_ zone: Zone) -> some View {
        let color: Color = zone == .a ? .orange : zone == .b ? .blue : .green
        return RoundedRectangle(cornerRadius: 7)
            .fill(color.opacity(0.13))
            .overlay(RoundedRectangle(cornerRadius: 7).strokeBorder(color.opacity(0.7)))
            .overlay(Text(zone.title).font(.system(.caption, design: .rounded).bold()).foregroundStyle(color))
    }
}

struct DesignSettingsView: View {
    private let localization = AppLocalization.shared
    @Bindable var model: AppModel
    @State private var appearance = false
    var body: some View {
        let _ = localization.language
        VStack(spacing: 14) {
            Picker(L10n.tr("Design"), selection: $appearance) {
                Text(L10n.tr("Templates and Sizes")).tag(false)
                Text(L10n.tr("Colors and Appearance")).tag(true)
            }.pickerStyle(.segmented).frame(maxWidth: 380)
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    if appearance {
                        TabAppearanceSettings(model: model)
                        visibilitySettings
                    } else {
                        templates
                        sizeSettings
                    }
                }.frame(maxWidth: .infinity, alignment: .leading).padding(2)
            }
        }.padding(16)
    }
    private var templates: some View {
        HStack(alignment: .top, spacing: 16) {
            ForEach(LayoutTemplate.allCases) { template in
                Button {
                    model.changeTemplate(template)
                } label: {
                    VStack(alignment: .leading, spacing: 10) {
                        LayoutTemplatePreview(
                            template: template,
                            ratio: model.layoutTemplate == template ? model.ratio : template.defaultRatio,
                            rowRatio: model.layoutTemplate == template ? model.rowRatio : 0.5
                        )
                        .frame(height: 100)
                        HStack {
                            Text(template.title)
                                .font(.headline)
                            Spacer()
                            Image(systemName: model.layoutTemplate == template ? "checkmark.circle.fill" : "circle")
                                .foregroundStyle(model.layoutTemplate == template ? Color.accentColor : .secondary)
                        }
                    }.padding(12)
                        .background(.quaternary.opacity(0.5), in: RoundedRectangle(cornerRadius: 12))
                        .overlay(
                            RoundedRectangle(cornerRadius: 12)
                                .strokeBorder(
                                    model.layoutTemplate == template ? Color.accentColor : .clear, lineWidth: 2))
                }.buttonStyle(.plain).disabled(model.busy || model.scanning || model.terminating)
            }
        }
    }
    private var sizeSettings: some View {
        GroupBox(L10n.tr("Display and Sizes")) {
            VStack(alignment: .leading, spacing: 16) {
                Picker(L10n.tr("Display"), selection: $model.selectedScreenID) {
                    Text(L10n.tr("Main")).tag("")
                    ForEach(NSScreen.screens, id: \.self) { screen in
                        Text(screen.localizedName).tag(AppModel.screenID(screen))
                    }
                }.onChange(of: model.selectedScreenID) { model.layoutPreferenceChanged() }
                HStack {
                    Text(L10n.tr("Left \(Int(model.ratio * 100)) %")).monospacedDigit().frame(
                        width: 115, alignment: .leading)
                    Slider(value: $model.ratio, in: 0.2...0.8)
                        .onChange(of: model.ratio) { model.layoutPreferenceChanged() }
                    Text(L10n.tr("Right \(100 - Int(model.ratio * 100)) %")).monospacedDigit().frame(
                        width: 65, alignment: .trailing)
                }
                if model.layoutTemplate != .twoColumns {
                    HStack {
                        Text(L10n.tr("A above \(Int(model.rowRatio * 100)) %")).monospacedDigit().frame(
                            width: 115, alignment: .leading)
                        Slider(value: $model.rowRatio, in: 0.25...0.75)
                            .onChange(of: model.rowRatio) { model.layoutPreferenceChanged() }
                        Text(L10n.tr("C \(100 - Int(model.rowRatio * 100)) %")).monospacedDigit().frame(
                            width: 65, alignment: .trailing)
                    }
                }
                Text(
                    L10n.tr(
                        "You can also drag the horizontal and vertical arrow handles when the tab bars are visible. Each column has a minimum width of 20%."
                    )
                )
                .font(.caption).foregroundStyle(.secondary)
            }.padding(10)
        }.disabled(model.busy || model.scanning || model.terminating)
    }
    private var visibilitySettings: some View {
        GroupBox(L10n.tr("Tab Bar Visibility")) {
            VStack(alignment: .leading, spacing: 12) {
                Toggle(
                    L10n.tr("Hide tab bars automatically"),
                    isOn: Binding(get: { model.autoHideTabBars }, set: { model.setAutoHideTabBars($0) }))
                Text(
                    model.autoHideTabBars
                        ? L10n.tr("Windows use the full height. Tab bars float above them.")
                        : L10n.tr("Tab bars reserve space above their windows.")
                )
                .font(.caption).foregroundStyle(.secondary)
                Toggle(
                    L10n.tr("Keep fixed tab bars above all windows"),
                    isOn: Binding(
                        get: { !model.tabAppearance.keepFixedBarsBehindWindows },
                        set: { model.setFixedBarsAboveWindows($0) })
                ).disabled(model.autoHideTabBars)
                Text(
                    model.tabAppearance.keepFixedBarsBehindWindows
                        ? L10n.tr(
                            "Show Tabs brings them to the front for five seconds. They stay in front while you use them, then return behind app windows."
                        )
                        : L10n.tr("Fixed tab bars stay above app windows.")
                )
                .font(.caption).foregroundStyle(.secondary)
                Toggle(
                    L10n.tr("Show all tab bars when clicking a tab or group"),
                    isOn: Binding(
                        get: { model.tabAppearance.revealAllBarsOnClick },
                        set: { model.setRevealAllBarsOnClick($0) }))
                HStack {
                    Toggle(
                        L10n.tr("Show when the pointer reaches the top edge"),
                        isOn: Binding(get: { model.revealTabsAtTopEdge }, set: { model.setRevealTabsAtTopEdge($0) })
                    ).disabled(!model.autoHideTabBars)
                    Spacer()
                    Text(
                        (model.preferences.shortcuts[ShortcutManager.Action.showTabs.rawValue]
                            ?? ShortcutManager.Action.showTabs.defaultBinding).display
                    ).font(.caption).foregroundStyle(.secondary)
                }
            }.toggleStyle(.checkbox).padding(10)
        }.disabled(model.busy || model.scanning || model.terminating)
    }
}
