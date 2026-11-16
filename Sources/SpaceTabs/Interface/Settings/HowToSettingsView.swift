import SpaceTabsCore
import SwiftUI

/// Code-drawn illustrations stay sharp at any display scale and follow app language.
struct HowToSettingsView: View {
    private let localization = AppLocalization.shared
    var body: some View {
        let _ = localization.language
        ScrollView {
            VStack(alignment: .leading, spacing: 22) {
                SettingsCard(
                    title: L10n.tr("A saved recipe and a place to use it"),
                    subtitle: L10n.tr("Profiles and workspaces are related, but neither contains the other.")
                ) {
                    HStack(spacing: 16) {
                        concept(
                            "rectangle.stack", L10n.tr("Profile"),
                            L10n.tr("Saved recipe: layout, appearance, and assigned windows."), .purple)
                        VStack {
                            Image(systemName: "arrow.right")
                            Text(L10n.tr("Open here")).font(.caption)
                        }.foregroundStyle(.secondary)
                        concept(
                            "display", L10n.tr("Workspace"),
                            L10n.tr("Your working arrangement on one monitor and one macOS desktop."), .blue)
                    }
                    Text(
                        L10n.tr(
                            "You can start with an empty workspace. Saving a profile is optional. Accepted workspace changes are saved automatically; a named profile is a separate snapshot."
                        )
                    )
                    .font(.callout).foregroundStyle(.secondary)
                    Label(
                        L10n.tr("Monitor + macOS desktop → one open workspace → zones → window tabs"),
                        systemImage: "square.stack.3d.up"
                    )
                    .font(.callout.weight(.medium))
                }
                SettingsCard(
                    title: L10n.tr("1 · One monitor, a work setup"),
                    subtitle: L10n.tr("One workspace, optionally saved as the Work profile. Choose A/C on the Left.")
                ) {
                    WorkspaceSketch(kind: .work, caption: L10n.tr("Main monitor · Desktop 1 · Work")).frame(height: 285)
                    Text(
                        L10n.tr(
                            "A: Notes. C: Terminal. B: browser and VS Code as two tabs in the same zone. Only the selected B window is in front; Notes and Terminal keep their selections."
                        ))
                    Text(
                        L10n.tr(
                            "Each app keeps its own title bar and window buttons. The dark SpaceTabs strip is a separate control above it."
                        )
                    )
                    .font(.caption).foregroundStyle(.secondary)
                    steps([
                        L10n.tr("Create a workspace on the main monitor."),
                        L10n.tr("In Design, choose A/C on the Left; assign the windows in Apps."),
                        L10n.tr("Optionally save a profile named Work."),
                    ])
                }
                SettingsCard(
                    title: L10n.tr("2 · Two monitors, two independent workspaces"),
                    subtitle: L10n.tr("Keep Work on the main monitor and create another workspace on the BenQ.")
                ) {
                    HStack(alignment: .top, spacing: 24) {
                        WorkspaceSketch(kind: .work, caption: L10n.tr("Main · Work")).frame(maxWidth: .infinity).frame(
                            height: 285)
                        VStack(spacing: 8) {
                            WorkspaceSketch(kind: .portrait, caption: L10n.tr("BenQ · Music & browsing")).frame(
                                width: 185, height: 310)
                            Label(L10n.tr("Two-row layout: planned"), systemImage: "clock").font(.caption)
                                .foregroundStyle(.orange)
                        }
                    }
                    Text(
                        L10n.tr(
                            "The BenQ gets its own workspace. You may save a second profile, such as Music & browsing. Work does not currently contain several monitors or a rule that automatically detects a vertical BenQ."
                        ))
                    Text(
                        L10n.tr(
                            "The portrait sketch shows the requested future layout: Spotify above a second Chrome window. Two Rows is not available in Design yet; the current templates use columns."
                        )
                    )
                    .font(.callout).foregroundStyle(.secondary)
                    steps([
                        L10n.tr("From the menu bar, create a workspace on the BenQ."),
                        L10n.tr("Assign separate windows there; optionally save its own profile."),
                        L10n.tr("A window belongs to one open workspace. Use a second Chrome window for the BenQ."),
                    ])
                }
                SettingsCard(
                    title: L10n.tr("3 · One monitor, two macOS desktops"),
                    subtitle: L10n.tr("Work on Desktop 1; Personal on Desktop 2. Each has its own workspace.")
                ) {
                    HStack(spacing: 20) {
                        WorkspaceSketch(kind: .work, caption: L10n.tr("Desktop 1 · Work")).frame(maxWidth: .infinity)
                        Image(systemName: "arrow.left.arrow.right").foregroundStyle(.secondary)
                        WorkspaceSketch(kind: .personal, caption: L10n.tr("Desktop 2 · Personal")).frame(
                            maxWidth: .infinity)
                    }.frame(height: 235)
                    Text(
                        L10n.tr(
                            "Create the macOS desktops in Mission Control. Open a workspace on each. Their bars stay on their own desktop while SpaceTabs runs. Profiles Work and Personal are optional saved recipes for those workspaces."
                        ))
                    steps([
                        L10n.tr("On Desktop 1, open Work here on the main monitor."),
                        L10n.tr("Switch to Desktop 2 and create a workspace or open Personal here."),
                        L10n.tr(
                            "After restarting SpaceTabs, use Open here again on each intended desktop. Native desktop bindings are not remembered across app restarts."
                        ),
                    ])
                }
                SettingsCard(
                    title: L10n.tr("Can I have several workspaces here?"),
                    subtitle: L10n.tr("Several saved; one open per monitor and macOS desktop.")
                ) {
                    HStack(spacing: 12) {
                        Label(L10n.tr("Work"), systemImage: "rectangle.stack")
                        Label(L10n.tr("Personal"), systemImage: "rectangle.stack")
                        Image(systemName: "arrow.right").foregroundStyle(.secondary)
                        Label(L10n.tr("One open here"), systemImage: "display").foregroundStyle(.blue)
                    }.font(.headline)
                    Text(
                        L10n.tr(
                            "Opening a different workspace at an occupied destination saves and closes the previous workspace first. Its apps remain running and its assignments stay saved. Other monitors and desktops keep their own workspaces."
                        ))
                }
                SettingsCard(
                    title: L10n.tr("Which action do I need?"),
                    subtitle: L10n.tr("The menu bar provides quick access to each workspace.")
                ) {
                    action(
                        "arrow.up.forward.app", L10n.tr("Show"),
                        L10n.tr("Bring the selected windows forward without changing their size."))
                    action(
                        "arrow.clockwise", L10n.tr("Restore"),
                        L10n.tr("Repair window sizes and positions and retry missing assigned apps."))
                    action("rectangle.on.rectangle", L10n.tr("Show Tabs"), L10n.tr("Reveal the SpaceTabs controls."))
                    action(
                        "rectangle.badge.plus", L10n.tr("Open here"),
                        L10n.tr("Open a saved workspace on the chosen monitor of the current desktop."))
                    action(
                        "xmark.circle", L10n.tr("Close workspace"),
                        L10n.tr("Save the workspace and release its windows; keep the apps running."))
                }
            }.padding(24).frame(maxWidth: 900).frame(maxWidth: .infinity)
        }
    }
    private func concept(_ icon: String, _ title: String, _ detail: String, _ color: Color) -> some View {
        VStack(alignment: .leading, spacing: 9) {
            Image(systemName: icon).font(.title2).foregroundStyle(color)
            Text(title).font(.headline)
            Text(detail).font(.callout).fixedSize(horizontal: false, vertical: true)
        }.padding(16).frame(maxWidth: .infinity, alignment: .leading)
            .background(color.opacity(0.08), in: RoundedRectangle(cornerRadius: 12))
    }
    private func steps(_ lines: [String]) -> some View {
        VStack(alignment: .leading, spacing: 7) {
            ForEach(Array(lines.enumerated()), id: \.offset) { index, line in
                HStack(alignment: .top, spacing: 8) {
                    Text("\(index + 1)").font(.caption.bold()).frame(width: 22, height: 22).background(
                        .quaternary, in: Circle())
                    Text(line).font(.callout).fixedSize(horizontal: false, vertical: true)
                }
            }
        }
    }
    private func action(_ icon: String, _ title: String, _ detail: String) -> some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: icon).foregroundStyle(.blue).frame(width: 24)
            Text(title).fontWeight(.semibold).frame(width: 110, alignment: .leading)
            Text(detail).foregroundStyle(.secondary).frame(maxWidth: .infinity, alignment: .leading)
        }.font(.callout)
    }
}

struct WorkspaceSketch: View {
    enum Kind { case work, personal, portrait }
    private let localization = AppLocalization.shared
    let kind: Kind
    let caption: String
    var body: some View {
        let _ = localization.language
        GeometryReader { proxy in
            let aspect: CGFloat = kind == .portrait ? 9.0 / 16 : 16.0 / 9
            let width = min(proxy.size.width, max(0, proxy.size.height - 48) * aspect)
            VStack(spacing: 0) {
                VStack(spacing: 8) {
                    HStack(spacing: 4) {
                        Circle().fill(.secondary.opacity(0.5)).frame(width: 4, height: 4)
                        Text("macOS").font(.system(size: 8))
                        Spacer()
                    }.padding(.horizontal, 5)
                    if kind == .work {
                        HStack(spacing: 8) {
                            VStack(spacing: 8) {
                                sketchZone("A", .orange, apps: ["Notes"])
                                sketchZone("C", .green, apps: ["Terminal"])
                            }.frame(maxWidth: .infinity)
                            sketchZone("B", .blue, apps: [L10n.tr("Browser"), "VS Code"]).frame(maxWidth: .infinity)
                        }
                    } else if kind == .portrait {
                        VStack(spacing: 8) {
                            sketchZone("A", .orange, apps: ["Spotify"])
                            sketchZone("B", .blue, apps: [L10n.tr("Chrome · second window")])
                        }
                    } else {
                        HStack(spacing: 8) {
                            sketchZone("A", .orange, apps: ["Mail"])
                            sketchZone("B", .blue, apps: [L10n.tr("Browser")])
                        }
                    }
                }.padding(9).background(
                    LinearGradient(
                        colors: [.blue.opacity(0.09), .purple.opacity(0.12)], startPoint: .topLeading,
                        endPoint: .bottomTrailing)
                )
                .clipShape(RoundedRectangle(cornerRadius: 8))
                .padding(5).background(Color.primary.opacity(0.8), in: RoundedRectangle(cornerRadius: 12))
                .frame(width: width, height: width / aspect)
                Rectangle().fill(.secondary.opacity(0.6)).frame(width: 22, height: 8)
                Capsule().fill(.secondary.opacity(0.6)).frame(width: 68, height: 4)
                Text(caption).font(.caption.weight(.medium)).multilineTextAlignment(.center).padding(.top, 8)
            }.frame(width: proxy.size.width, height: proxy.size.height, alignment: .top)
        }.accessibilityElement(children: .combine)
    }
    private func sketchZone(_ zone: String, _ color: Color, apps: [String]) -> some View {
        VStack(spacing: 4) {
            HStack(spacing: 4) {
                Text(zone).fontWeight(.heavy).foregroundStyle(color)
                ForEach(apps, id: \.self) { app in
                    Text(app).lineLimit(1).foregroundStyle(.white.opacity(0.9))
                        .padding(.horizontal, 3).padding(.vertical, 2)
                        .background(
                            .white.opacity(app == apps.last ? 0.16 : 0.04), in: RoundedRectangle(cornerRadius: 3))
                }
                Spacer(minLength: 0)
            }.font(.system(size: 9)).padding(5).background(Color(white: 0.18), in: RoundedRectangle(cornerRadius: 4))
            VStack(spacing: 0) {
                HStack(spacing: 3) {
                    ForEach(0..<3) { index in
                        Circle().fill([Color.red, .yellow, .green][index]).frame(width: 4, height: 4)
                    }
                    Spacer(minLength: 0)
                    Text(apps.last ?? "").font(.system(size: 8)).lineLimit(1)
                }.padding(5).background(.quaternary)
                VStack(alignment: .leading, spacing: 6) {
                    ForEach(0..<3) { index in
                        Capsule().fill(color.opacity(index == 0 ? 0.4 : 0.12)).frame(height: 4).padding(
                            .trailing, CGFloat(index * 8))
                    }
                    Spacer(minLength: 0)
                }.padding(8).frame(maxWidth: .infinity, maxHeight: .infinity)
            }.background(Color(nsColor: .controlBackgroundColor), in: RoundedRectangle(cornerRadius: 5))
                .overlay(RoundedRectangle(cornerRadius: 5).strokeBorder(color.opacity(0.4)))
        }.frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}
