import Darwin
import Foundation

enum SettingsSocketAddress {
    static func make(_ path: String) throws -> sockaddr_un {
        var address = sockaddr_un()
        let bytes = Array(path.utf8CString)
        guard bytes.count <= MemoryLayout.size(ofValue: address.sun_path) else {
            throw SettingsTransportError.invalidPath
        }
        address.sun_family = sa_family_t(AF_UNIX)
        address.sun_len = UInt8(MemoryLayout<sockaddr_un>.size)
        withUnsafeMutableBytes(of: &address.sun_path) { storage in
            for (index, byte) in bytes.enumerated() { storage[index] = UInt8(bitPattern: byte) }
        }
        return address
    }
}
