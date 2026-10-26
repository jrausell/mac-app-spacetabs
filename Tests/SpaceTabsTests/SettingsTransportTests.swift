import Darwin
import Foundation
import Testing

@testable import SpaceTabs

private final class PacketInbox: @unchecked Sendable {
    private let lock = NSLock()
    private var storedPackets: [SettingsPacket] = []
    private var isClosed = false
    var packets: [SettingsPacket] { lock.withLock { storedPackets } }
    var closed: Bool { lock.withLock { isClosed } }
    func append(_ packet: SettingsPacket) { lock.withLock { storedPackets.append(packet) } }
    func markClosed() { lock.withLock { isClosed = true } }
}

@Test func settingsChannelTransfersFramedMessagesInBothDirections() async throws {
    var sockets: [Int32] = [0, 0]
    #expect(socketpair(AF_UNIX, SOCK_STREAM, 0, &sockets) == 0)
    let firstInbox = PacketInbox()
    let secondInbox = PacketInbox()
    let first = SettingsChannel(
        descriptor: sockets[0],
        packet: { packet in
            firstInbox.append(packet)
        }, disconnected: { _ in })
    let second = SettingsChannel(
        descriptor: sockets[1],
        packet: { packet in
            secondInbox.append(packet)
        }, disconnected: { _ in })
    defer {
        first.close()
        second.close()
    }
    first.send(SettingsPacket(kind: .state, data: Data(repeating: 42, count: 180_000)))
    first.send(SettingsPacket(kind: .show))
    second.send(SettingsPacket(kind: .command, data: Data("test".utf8)))
    for _ in 0..<200 {
        if firstInbox.packets.count == 1, secondInbox.packets.count == 2 { break }
        try await Task.sleep(for: .milliseconds(5))
    }
    #expect(firstInbox.packets.map(\.kind) == [.command])
    #expect(secondInbox.packets.map(\.kind) == [.state, .show])
    #expect(secondInbox.packets.first?.data == Data(repeating: 42, count: 180_000))
}

@Test func settingsChannelRejectsOversizedFrameBeforeReadingItsBody() async throws {
    var sockets: [Int32] = [0, 0]
    #expect(socketpair(AF_UNIX, SOCK_STREAM, 0, &sockets) == 0)
    let inbox = PacketInbox()
    let channel = SettingsChannel(
        descriptor: sockets[0],
        packet: { packet in
            inbox.append(packet)
        }, disconnected: { _ in inbox.markClosed() })
    defer {
        channel.close()
        Darwin.close(sockets[1])
    }
    var length = UInt32(SettingsChannel.limit + 1).bigEndian
    let written = withUnsafeBytes(of: &length) { Darwin.send(sockets[1], $0.baseAddress, $0.count, 0) }
    #expect(written == 4)
    for _ in 0..<200 {
        if inbox.closed { break }
        try await Task.sleep(for: .milliseconds(5))
    }
    #expect(inbox.closed)
    #expect(inbox.packets.isEmpty)
}

@Test func settingsConnectionDoesNotTrustAMissingOrUnsignedHelper() {
    let verifier = SettingsPeerVerifier(application: URL(fileURLWithPath: "/nonexistent/SpaceTabs Ajustes.app"))
    #expect(verifier.requirement == nil)
    #expect(!verifier.accepts(-1))
}

@Test func settingsPeerVerificationAcceptsOnlyTheExpectedSignedProcess() throws {
    var sockets: [Int32] = [0, 0]
    try #require(socketpair(AF_UNIX, SOCK_STREAM, 0, &sockets) == 0)
    defer {
        Darwin.close(sockets[0])
        Darwin.close(sockets[1])
    }
    let executable = URL(fileURLWithPath: CommandLine.arguments[0])
    let verifier = SettingsPeerVerifier(application: executable)
    try #require(verifier.requirement != nil)
    #expect(verifier.accepts(sockets[0]))
    #expect(verifier.accepts(sockets[1]))
    let other = SettingsPeerVerifier(application: URL(fileURLWithPath: "/usr/bin/true"))
    try #require(other.requirement != nil)
    #expect(!other.accepts(sockets[0]))
}

private actor LocalSettingsTestServer {
    var channel: SettingsChannel?
    func accept(_ fd: Int32) {
        channel = SettingsChannel(
            descriptor: fd,
            packet: { [weak self] value in
                Task { await self?.respond(value) }
            }, disconnected: { _ in })
    }
    func respond(_ packet: SettingsPacket) { channel?.send(SettingsPacket(kind: .state, data: packet.data)) }
    func close() {
        channel?.close()
        channel = nil
    }
}

@Test(
    .enabled(
        if: ProcessInfo.processInfo.environment["SPACETABS_TEST_LOCAL_LISTENER"] == "1",
        "Requires local socket listeners. Run with SPACETABS_TEST_LOCAL_LISTENER=1."))
func settingsLocalSocketAuthenticatesPeersAndExchangesMessages() async throws {
    let verifier = SettingsPeerVerifier(application: URL(fileURLWithPath: CommandLine.arguments[0]))
    try #require(verifier.requirement != nil)
    let state = LocalSettingsTestServer()
    let inbox = PacketInbox()
    let server = try SettingsSocketServer(verifier: verifier) { fd in Task { await state.accept(fd) } }
    let channel = try SettingsChannel.connect(
        path: server.path, verifier: verifier,
        packet: { packet in
            inbox.append(packet)
        }, disconnected: { _ in })
    defer {
        channel.close()
        server.stop()
        Task { await state.close() }
    }
    let attributes = try FileManager.default.attributesOfItem(atPath: server.path)
    #expect((attributes[.posixPermissions] as? NSNumber)?.intValue == 0o600)
    channel.send(SettingsPacket(kind: .command, data: Data("hello".utf8)))
    for _ in 0..<200 {
        if inbox.packets.count == 1 { break }
        try await Task.sleep(for: .milliseconds(5))
    }
    #expect(inbox.packets.first?.kind == .state)
    #expect(inbox.packets.first?.data == Data("hello".utf8))
}
