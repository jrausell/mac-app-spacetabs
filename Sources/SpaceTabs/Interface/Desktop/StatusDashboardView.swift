import SpaceTabsCore
import SwiftUI

/// A read-only presentation snapshot; menu rendering never discovers or moves windows.
struct WorkspaceMenuCard: Identifiable {
    let summary: WorkspaceSummary
    let template: LayoutTemplate
    let ratio: Double
    let rowRatio: Double
    let canRestore: Bool
    var id: UUID { summary.id }
}

struct StatusDashboardView: View {
    private let localization = AppLocalization.shared
    let cards: [WorkspaceMenuCard]
    let shortcut: String
    let settings: () -> Void
    let howTo: () -> Void
    let showTabs: () -> Void
    let show: (UUID) -> Void
    let restore: (UUID) -> Void
    let configure: (UUID) -> Void

    var body: some View {
        let _ = localization.language
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text("SpaceTabs").font(.title3.bold())
                    Text(L10n.tr("Your workspaces at a glance")).font(.caption).foregroundStyle(.secondary)
                }
                Spacer()
                Button(action: howTo) { Image(systemName: "questionmark.circle") }
                    .help(L10n.tr("How To")).accessibilityLabel(L10n.tr("How To"))
                Button(action: settings) { Image(systemName: "gearshape") }
                    .help(L10n.tr("Windows and Settings…")).accessibilityLabel(L10n.tr("Windows and Settings…"))
            }.buttonStyle(.borderless)
            Button(action: showTabs) {
                HStack {
                    Label(L10n.tr("Show Tabs"), systemImage: "rectangle.on.rectangle")
                    Spacer()
                    Text(shortcut).foregroundStyle(.secondary)
                }.frame(maxWidth: .infinity).padding(.vertical, 4)
            }.buttonStyle(.bordered)
            HStack {
                Text(L10n.tr("Workspaces")).font(.headline)
                Spacer()
                Text(L10n.tr("One per monitor + desktop")).font(.caption).foregroundStyle(.secondary)
            }
            ScrollView {
                VStack(spacing: 9) {
                    ForEach(cards) { card in workspace(card) }
                }
            }.frame(height: min(CGFloat(cards.count) * 112, 336))
            Text(L10n.tr("Profiles are saved recipes. Open or create a workspace from the menus below."))
                .font(.caption).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
        }.padding(16).frame(width: 440)
    }

    private func workspace(_ card: WorkspaceMenuCard) -> some View {
        let summary = card.summary
        let state =
            summary.isHere ? L10n.tr("Current desktop") : summary.isOpen ? L10n.tr("Other desktop") : L10n.tr("Closed")
        return HStack(alignment: .top, spacing: 12) {
            LayoutTemplatePreview(template: card.template, ratio: card.ratio, rowRatio: card.rowRatio)
                .frame(width: 74, height: 66).padding(5)
                .background(.quaternary.opacity(0.5), in: RoundedRectangle(cornerRadius: 9))
            VStack(alignment: .leading, spacing: 5) {
                HStack {
                    Text(summary.name).font(.headline).lineLimit(1)
                    Spacer(minLength: 0)
                    Circle().fill(summary.isHere ? Color.green : .secondary).frame(width: 6, height: 6)
                    Text(state).font(.caption2).foregroundStyle(.secondary)
                }
                Label(summary.displayName, systemImage: "display").font(.caption).foregroundStyle(.secondary).lineLimit(
                    1)
                HStack(spacing: 8) {
                    Button {
                        show(summary.id)
                    } label: {
                        Label(L10n.tr("Show"), systemImage: "arrow.up.forward.app")
                    }
                    .disabled(!summary.isHere)
                    Button {
                        restore(summary.id)
                    } label: {
                        Label(L10n.tr("Restore"), systemImage: "arrow.clockwise")
                    }
                    .disabled(!card.canRestore)
                    Spacer(minLength: 0)
                    Button {
                        configure(summary.id)
                    } label: {
                        Image(systemName: "slider.horizontal.3")
                    }
                    .help(L10n.tr("Windows and Settings…")).accessibilityLabel(L10n.tr("Windows and Settings…"))
                }.controlSize(.small).buttonStyle(.bordered)
            }
        }.padding(10).frame(maxWidth: .infinity, alignment: .leading)
            .background(Color.primary.opacity(summary.isHere ? 0.06 : 0.025), in: RoundedRectangle(cornerRadius: 10))
    }
}
