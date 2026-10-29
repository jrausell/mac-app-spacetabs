import Darwin
import Foundation
import Security
import SpaceTabsCore

/// Framed, bounded messages. All IO runs on a serial background queue. Writes
/// have a timeout; a slow/disconnected helper cannot block the window manager.
final class SettingsChannel: @unchecked Sendable {
    static let limit = SettingsProtocol.frameLimit
    let id = UUID()
    private let fd: Int32
    private let queue = DispatchQueue(label: "SpaceTabs.settings.channel")
    private let source: DispatchSourceRead
    private var buffer = Data()
    private var stopped = false
    private let packet: @Sendable (SettingsPacket) -> Void
    private let disconnected: @Sendable (UUID) -> Void
    init(
        descriptor: Int32, packet: @escaping @Sendable (SettingsPacket) -> Void,
        disconnected: @escaping @Sendable (UUID) -> Void
    ) {
        fd = descriptor
        self.packet = packet
        self.disconnected = disconnected
        var one: Int32 = 1
        setsockopt(fd, SOL_SOCKET, SO_NOSIGPIPE, &one, socklen_t(MemoryLayout<Int32>.size))
        var timeout = timeval(tv_sec: 2, tv_usec: 0)
        setsockopt(fd, SOL_SOCKET, SO_SNDTIMEO, &timeout, socklen_t(MemoryLayout<timeval>.size))
        source = DispatchSource.makeReadSource(fileDescriptor: fd, queue: queue)
        let socketFD = fd
        source.setCancelHandler { Darwin.close(socketFD) }
        source.setEventHandler { [weak self] in self?.read() }
        source.resume()
    }
    static func connect(
        path: String, verifier: SettingsPeerVerifier,
        packet: @escaping @Sendable (SettingsPacket) -> Void,
        disconnected: @escaping @Sendable (UUID) -> Void
    ) throws -> SettingsChannel {
        var address = try SettingsSocketAddress.make(path)
        let fd = socket(AF_UNIX, SOCK_STREAM, 0)
        guard fd >= 0 else { throw SettingsTransportError.system(errno) }
        let result = withUnsafePointer(to: &address) {
            $0.withMemoryRebound(to: sockaddr.self, capacity: 1) {
                Darwin.connect(fd, $0, socklen_t(MemoryLayout<sockaddr_un>.size))
            }
        }
        guard result == 0 else {
            let code = errno
            Darwin.close(fd)
            throw SettingsTransportError.system(code)
        }
        guard verifier.accepts(fd) else {
            Darwin.close(fd)
            throw SettingsTransportError.untrustedPeer
        }
        return SettingsChannel(descriptor: fd, packet: packet, disconnected: disconnected)
    }
    func send(_ value: SettingsPacket) {
        guard let payload = try? JSONEncoder().encode(value), payload.count <= Self.limit else { return }
        var size = UInt32(payload.count).bigEndian
        var frame = withUnsafeBytes(of: &size) { Data($0) }
        frame.append(payload)
        let output = frame
        queue.async { [self] in
            guard !stopped else { return }
            let success = output.withUnsafeBytes { bytes -> Bool in
                var offset = 0
                while offset < bytes.count {
                    let count = Darwin.send(fd, bytes.baseAddress!.advanced(by: offset), bytes.count - offset, 0)
                    if count < 0 && errno == EINTR { continue }
                    guard count > 0 else { return false }
                    offset += count
                }
                return true
            }
            if !success {
                DiagnosticLog.shared.record("settings.write-failed", level: "error", details: ["errno": String(errno)])
                finish()
            }
        }
    }
    private func read() {
        guard !stopped else { return }
        var bytes = [UInt8](repeating: 0, count: 64 * 1024)
        let count = recv(fd, &bytes, bytes.count, 0)
        if count < 0 && errno == EINTR { return }
        guard count > 0 else {
            DiagnosticLog.shared.record(
                "settings.disconnected",
                details: ["readResult": String(count), "errno": count < 0 ? String(errno) : "0"])
            finish()
            return
        }
        buffer.append(contentsOf: bytes.prefix(count))
        while buffer.count >= 4 {
            let length = buffer.prefix(4).reduce(0) { ($0 << 8) | Int($1) }
            guard length > 0, length <= Self.limit else {
                DiagnosticLog.shared.record("settings.invalid-frame", level: "error")
                finish()
                return
            }
            guard buffer.count >= length + 4 else { return }
            let data = Data(buffer.dropFirst(4).prefix(length))
            buffer.removeFirst(length + 4)
            guard let value = try? JSONDecoder().decode(SettingsPacket.self, from: data) else {
                DiagnosticLog.shared.record("settings.invalid-packet", level: "error")
                finish()
                return
            }
            packet(value)
        }
    }
    private func finish() {
        guard !stopped else { return }
        stopped = true
        shutdown(fd, SHUT_RDWR)
        source.cancel()
        disconnected(id)
    }
    func close() { queue.async { [self] in finish() } }
    deinit { source.cancel() }
}
