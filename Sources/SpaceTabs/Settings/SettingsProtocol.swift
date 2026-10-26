import Darwin
import Foundation
import Security
import SpaceTabsCore

struct SettingsPacket: Codable, Sendable {
    enum Kind: String, Codable, Sendable { case subscribe, state, command, show, close }
    let kind: Kind
    var data = Data()
}

enum SettingsTransportError: LocalizedError {
    case system(Int32)
    case untrustedPeer, invalidPath
    var errorDescription: String? {
        switch self {
        case .system(let code): L10n.tr("Local Settings connection: \(String(cString: strerror(code)))")
        case .untrustedPeer:
            L10n.tr("Could not verify the Settings process signature. Restart SpaceTabs after updating.")
        case .invalidPath: L10n.tr("Invalid Settings connection path.")
        }
    }
}

/// Wire limits shared by the manager and its bundled settings process.
enum SettingsProtocol {
    static let messageLimit = 2 * 1024 * 1024
    static let frameLimit = 4 * 1024 * 1024
}
