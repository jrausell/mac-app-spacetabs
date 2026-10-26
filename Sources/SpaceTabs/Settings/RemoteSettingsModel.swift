import AppKit
import Observation
import SpaceTabsCore

@MainActor final class RemoteSettingsModel {
    private let model: AppModel
    private var connection: SettingsChannel?
    private(set) var state: SettingsState?
    init(model: AppModel, path: String) throws {
        self.model = model
        let managerURL = Bundle.main.bundleURL.deletingLastPathComponent().deletingLastPathComponent()
            .deletingLastPathComponent()
        let verifier = SettingsPeerVerifier(application: managerURL)
        connection = try SettingsChannel.connect(
            path: path, verifier: verifier,
            packet: { [weak self] packet in
                DispatchQueue.main.async { self?.receive(packet) }
            }, disconnected: { _ in Task { @MainActor in NSApp.terminate(nil) } })
        connection?.send(SettingsPacket(kind: .subscribe))
    }
    func send(_ command: SettingsCommand) {
        guard let data = try? JSONEncoder().encode(command), data.count <= SettingsProtocol.messageLimit else { return }
        connection?.send(SettingsPacket(kind: .command, data: data))
    }
    private func receive(_ packet: SettingsPacket) {
        switch packet.kind {
        case .state:
            guard packet.data.count <= SettingsProtocol.messageLimit,
                let state = try? JSONDecoder().decode(SettingsState.self, from: packet.data)
            else { return }
            self.state = state
            state.apply(to: model)
            model.remoteSettingsConnected = true
        case .show: model.openSettings()
        case .close: NSApp.terminate(nil)
        default: break
        }
    }
}
