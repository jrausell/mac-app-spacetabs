import Darwin
import Foundation
import Security

final class SettingsSocketServer: @unchecked Sendable {
    let path: String
    private let source: DispatchSourceRead
    init(verifier: SettingsPeerVerifier, accepted: @escaping @Sendable (Int32) -> Void) throws {
        let name = "st-\(UUID().uuidString.prefix(12)).sock"
        let preferred = FileManager.default.temporaryDirectory.appendingPathComponent(name).path
        path = preferred.utf8.count < 100 ? preferred : "/tmp/\(name)"
        var address = try SettingsSocketAddress.make(path)
        let fd = socket(AF_UNIX, SOCK_STREAM, 0)
        guard fd >= 0 else { throw SettingsTransportError.system(errno) }
        let bound = withUnsafePointer(to: &address) {
            $0.withMemoryRebound(to: sockaddr.self, capacity: 1) {
                Darwin.bind(fd, $0, socklen_t(MemoryLayout<sockaddr_un>.size))
            }
        }
        guard bound == 0 else {
            let code = errno
            Darwin.close(fd)
            throw SettingsTransportError.system(code)
        }
        guard chmod(path, S_IRUSR | S_IWUSR) == 0 else {
            let code = errno
            Darwin.close(fd)
            unlink(path)
            throw SettingsTransportError.system(code)
        }
        guard listen(fd, 4) == 0 else {
            let code = errno
            Darwin.close(fd)
            unlink(path)
            throw SettingsTransportError.system(code)
        }
        source = DispatchSource.makeReadSource(
            fileDescriptor: fd, queue: DispatchQueue(label: "SpaceTabs.settings.accept"))
        source.setEventHandler {
            let client = accept(fd, nil, nil)
            guard client >= 0 else { return }
            guard verifier.accepts(client) else {
                Darwin.close(client)
                return
            }
            accepted(client)
        }
        let socketPath = path
        source.setCancelHandler {
            Darwin.close(fd)
            unlink(socketPath)
        }
        source.resume()
    }
    func stop() { source.cancel() }
    deinit { source.cancel() }
}
