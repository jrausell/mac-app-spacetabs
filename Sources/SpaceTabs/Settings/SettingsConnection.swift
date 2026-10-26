import AppKit
import Darwin
import Foundation
import Observation
import SpaceTabsCore

@MainActor final class SettingsHost {
    static let helperID = SpaceTabsIdentity.settingsBundleID
    private let model: AppModel
    private var server: SettingsSocketServer?
    private var connection: SettingsChannel?
    private var helper: NSRunningApplication?
    private var launching = false
    private var observing = false
    private var lastState: SettingsState?
    private var helperURL: URL { Bundle.main.bundleURL.appendingPathComponent(SpaceTabsIdentity.settingsBundlePath) }
    init(model: AppModel) { self.model = model }
    func show() {
        if let helper, !helper.isTerminated {
            NSApp.yieldActivation(to: helper)
            connection?.send(SettingsPacket(kind: .show))
            let configuration = NSWorkspace.OpenConfiguration()
            configuration.activates = true
            NSWorkspace.shared.openApplication(at: helperURL, configuration: configuration) { _, _ in }
            return
        }
        guard !launching else { return }
        guard FileManager.default.fileExists(atPath: helperURL.path) else {
            model.message = L10n.tr(
                "SpaceTabs Settings was not found. Build the full app with Scripts/build-app.sh release.")
            return
        }
        do {
            if server == nil {
                let verifier = SettingsPeerVerifier(application: helperURL)
                guard verifier.requirement != nil else { throw SettingsTransportError.untrustedPeer }
                server = try SettingsSocketServer(verifier: verifier) { [weak self] fd in
                    Task { @MainActor in
                        guard let self else {
                            Darwin.close(fd)
                            return
                        }
                        self.accept(fd)
                    }
                }
            }
            guard let server else { return }
            let configuration = NSWorkspace.OpenConfiguration()
            configuration.arguments = [
                "--settings-socket", server.path, "--language", model.preferences.language.rawValue,
            ]
            configuration.activates = true
            launching = true
            NSWorkspace.shared.openApplication(at: helperURL, configuration: configuration) {
                [weak self] application, error in
                Task { @MainActor in
                    guard let self else { return }
                    self.launching = false
                    self.helper = application
                    if let error {
                        self.model.message = L10n.tr("Could not open Settings: \(error.localizedDescription)")
                    }
                }
            }
        } catch { model.message = error.localizedDescription }
    }
    private func accept(_ fd: Int32) {
        connection?.close()
        lastState = nil
        connection = SettingsChannel(
            descriptor: fd,
            packet: { [weak self] packet in
                DispatchQueue.main.async { self?.receivePacket(packet) }
            },
            disconnected: { [weak self] id in
                Task { @MainActor in
                    guard let self, self.connection?.id == id else { return }
                    self.connection = nil
                    self.lastState = nil
                }
            })
    }
    private func receivePacket(_ packet: SettingsPacket) {
        switch packet.kind {
        case .subscribe:
            if !observing {
                observing = true
                observeState()
            } else {
                pushState()
            }
        case .command: receive(packet.data)
        default: break
        }
    }
    private func observeState() {
        guard connection != nil else {
            observing = false
            return
        }
        let state = withObservationTracking {
            SettingsState(model)
        } onChange: { [weak self] in
            Task { @MainActor in self?.observeState() }
        }
        push(state)
    }
    private func pushState() { push(SettingsState(model)) }
    private func push(_ state: SettingsState) {
        guard state != lastState, let data = try? JSONEncoder().encode(state),
            data.count <= SettingsProtocol.messageLimit
        else {
            return
        }
        lastState = state
        connection?.send(SettingsPacket(kind: .state, data: data))
    }
    func receive(_ data: Data) {
        guard data.count <= SettingsProtocol.messageLimit,
            let command = try? JSONDecoder().decode(SettingsCommand.self, from: data)
        else { return }
        model.noteUserInteraction()
        switch command {
        case .bindProfile(let id, let enabled): model.bindProfile(id, enabled: enabled)
        case .zoom: model.toggleZoom()
        case .openSwitcher: model.showQuickSwitcher()
        case .reorderTab(let id, let zone, let before): model.reorderTab(id, to: zone, before: before)
        case .language(let language): model.setLanguage(language)
        case .rightDrag(let enabled): model.setRightDrag(enabled)
        case .resetPreferences: model.resetUserPreferences()
        case .binding(let id, let binding): model.setShortcut(id, binding: binding)
        case .resetBindings: model.resetShortcutBindings()
        case .zoneName(let zone, let name): model.setZoneName(zone, name: name)
        case .saveProfile(let name, let id): model.saveProfile(name: name, replacing: id)
        case .applyProfile(let id): model.applyProfile(id)
        case .deleteProfile(let id): model.deleteProfile(id)
        case .login(let enabled): model.setLoginEnabled(enabled)
        case .loginSettings: model.openLoginSettings()
        case .loginStatus: model.refreshLoginStatus()
        case .showTabs: model.showTabBars()
        case .refreshApps: model.refreshApplications()
        case .refreshWindows: model.refresh()
        case .permission: model.requestPermission()
        case .recheck: model.recheckPermission()
        case .assign(let id, let zone): model.assign(id, to: zone, requestFocus: false)
        case .release(let id): model.release(id)
        case .releaseAll: model.releaseAll()
        case .pause: model.togglePause()
        case .template(let template): model.changeTemplate(template)
        case .layout(let preferences):
            guard preferences.isValid,
                preferences.screenID.isEmpty
                    || NSScreen.screens.contains(where: { AppModel.screenID($0) == preferences.screenID })
            else { return }
            model.ratio = preferences.ratio
            model.rowRatio = preferences.rowRatio
            model.selectedScreenID = preferences.screenID
            model.autoHideTabBars = preferences.autoHide
            model.revealTabsAtTopEdge = preferences.revealAtTop
            model.layoutPreferenceChanged()
        case .appearance(let appearance):
            guard appearance.isValid else { return }
            model.tabAppearance = appearance
            model.appearancePreferenceChanged()
        case .launch(let id):
            if let app = model.installedApplications.first(where: { $0.id == id }) { model.launchApplication(app) }
        case .assignApp(let id, let zone):
            if let app = model.installedApplications.first(where: { $0.id == id }) {
                model.assignApplication(app, to: zone)
            }
        case .removeApp(let id):
            if let rule = model.applicationAssignments.first(where: { $0.id == id }) {
                model.removeApplicationAssignment(rule)
            }
        case .restore: model.restoreSavedSession()
        case .forget: model.forgetPending()
        case .demo: model.demo ? model.stopDemo() : model.startDemo()
        case .reset: model.resetConfiguration()
        case .reapply: model.reapplyLayout()
        case .diagnostics: model.copyDiagnostics()
        case .restartShortcuts: model.restartShortcuts()
        case .shortcut(let id):
            if let action = ShortcutManager.Action(rawValue: id) {
                model.handleShortcut(action, source: L10n.tr("Test in Settings"))
            }
        case .addApps(let urls):
            guard urls.count <= 32, urls.allSatisfy({ $0.isFileURL }) else { return }
            Task {
                do {
                    _ = try await model.applicationCatalog.add(urls)
                    model.refreshApplications()
                } catch { model.catalogMessage = error.localizedDescription }
            }
        case .filter(let zone): model.assignmentZone = zone
        case .clearMessage: model.message = nil
        case .revealApplication: PermissionService.revealCurrentApplication()
        }
        pushState()
    }
    func stop() {
        connection?.send(SettingsPacket(kind: .close))
        connection?.close()
        connection = nil
        helper?.terminate()
        server?.stop()
        server = nil
    }
}
