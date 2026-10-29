import Darwin
import Foundation
import Synchronization
import os

/// Bounded local history. Disk work never runs on a caller's executor.
public final class DiagnosticLog: Sendable {
    public static let directory = FileManager.default.homeDirectoryForCurrentUser
        .appendingPathComponent("Library/Logs/SpaceTabs", isDirectory: true)
    public static let shared = DiagnosticLog(
        directory: directory,
        name: Bundle.main.bundleIdentifier == SpaceTabsIdentity.settingsBundleID ? "settings" : "manager",
        enabled: false)
    private let queue = DispatchQueue(label: "dev.spacetabs.diagnostic-log", qos: .utility)
    private let state: Mutex<(enabled: Bool, pending: Int, dropped: Int)>
    public let url: URL
    private let previousURL: URL
    private let maximumBytes: Int
    private let fallback = Logger(subsystem: SpaceTabsIdentity.appBundleID, category: "DiagnosticLog")

    public init(directory: URL, name: String, maximumBytes: Int = 1_048_576, enabled: Bool = true) {
        precondition(["manager", "settings", "test"].contains(name))
        self.maximumBytes = min(max(maximumBytes, 1024), LocalConfigurationFile.maximumBytes)
        url = directory.appendingPathComponent("\(name).jsonl")
        previousURL = directory.appendingPathComponent("\(name)-previous.jsonl")
        state = Mutex((enabled, 0, 0))
    }

    public func start() {
        state.withLock { $0.enabled = true }
        record(
            "session.start",
            details: [
                "version": Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "development",
                "macOS": ProcessInfo.processInfo.operatingSystemVersionString,
                "bundle": Bundle.main.bundleURL.path,
            ])
    }

    public func record(
        _ event: String, level: String = "info", details: [String: String] = [:],
        file: String = #fileID, function: String = #function, line: Int = #line
    ) {
        let occurredAt = Date()
        // Bound individual records as well as the pending queue and files.
        let bounded = details.sorted(by: { $0.key < $1.key }).prefix(24).reduce(into: [String: String]()) {
            result, entry in
            result[String(entry.key.prefix(128))] = String(entry.value.prefix(2048))
        }
        state.withLock { state in
            guard state.enabled else { return }
            guard state.pending < 256 || event == "session.end" else {
                state.dropped += 1
                return
            }
            state.pending += 1
            if event == "session.end" { state.enabled = false }
            enqueue(
                event, level: level, details: bounded, occurredAt: occurredAt, file: file, function: function,
                line: line)
        }
    }

    // Enqueue while holding the admission lock, so shutdown follows every accepted record.
    private func enqueue(
        _ event: String, level: String, details: [String: String], occurredAt: Date,
        file: String, function: String, line: Int
    ) {
        queue.async { [self] in
            defer { state.withLock { $0.pending -= 1 } }
            let dropped = state.withLock { state in
                let count = state.dropped
                state.dropped = 0
                return count
            }
            let formatter = ISO8601DateFormatter()
            formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
            let record: [String: Any] = [
                "time": formatter.string(from: occurredAt),
                "pid": ProcessInfo.processInfo.processIdentifier,
                "level": String(level.prefix(32)), "event": String(event.prefix(128)),
                "source": "\(file):\(line) \(function)", "details": details,
                "droppedRecords": dropped,
            ]
            do {
                if event == "session.start", let data = try LocalConfigurationFile.read(at: url),
                    let last = data.split(separator: 0x0A).last,
                    let previous = try? JSONSerialization.jsonObject(with: Data(last)) as? [String: Any],
                    previous["event"] as? String != "session.end"
                {
                    var warning = record
                    warning["event"] = "session.previous-not-closed"
                    warning["level"] = "warning"
                    warning["details"] = [
                        "previousPID": String(describing: previous["pid"] ?? "unknown"),
                        "lastEvent": previous["event"] as? String ?? "unknown",
                        "reason":
                            "No clean shutdown marker; possible crash, force quit, or interrupted session. This is not a confirmed crash.",
                    ]
                    var warningData = try JSONSerialization.data(withJSONObject: warning, options: [.sortedKeys])
                    warningData.append(0x0A)
                    try append(warningData)
                }
                var data = try JSONSerialization.data(withJSONObject: record, options: [.sortedKeys])
                data.append(0x0A)
                try append(data)
            } catch {
                fallback.error("Could not write diagnostic history: \(String(describing: error), privacy: .public)")
            }
        }
    }

    public func failure(
        _ error: Error, operation: String, details: [String: String] = [:],
        file: String = #fileID, function: String = #function, line: Int = #line
    ) {
        let ns = error as NSError
        var fields = details
        fields["operation"] = operation
        fields["errorType"] = String(reflecting: type(of: error))
        fields["errorDomain"] = ns.domain
        fields["errorCode"] = String(ns.code)
        fields["reason"] = ns.localizedDescription
        if let failure = error as? WindowAccessError {
            fields["attribute"] = failure.attribute
            fields["axCode"] = failure.code.map(String.init)
            fields["retryable"] = String(failure.retryable)
        }
        if let failure = error as? WindowOperationError {
            fields["window"] = failure.windowID?.uuidString
            fields["recoveryWindows"] = String(failure.recoveryStates.count)
        }
        record("operation.error", level: "error", details: fields, file: file, function: function, line: line)
    }

    public func history() async -> String {
        await withCheckedContinuation { continuation in
            queue.async { [self] in
                var sections = [String]()
                for name in ["manager-previous.jsonl", "manager.jsonl", "settings-previous.jsonl", "settings.jsonl"] {
                    do {
                        if let data = try LocalConfigurationFile.read(
                            at: url.deletingLastPathComponent().appendingPathComponent(name))
                        {
                            sections.append("--- \(name) ---\n" + String(decoding: data, as: UTF8.self))
                        }
                    } catch {
                        sections.append("--- \(name): could not read log (\(error.localizedDescription)) ---")
                    }
                }
                continuation.resume(returning: sections.joined(separator: "\n"))
            }
        }
    }

    /// Use only at shutdown or in tests, never for normal UI logging.
    public func flush() { queue.sync {} }

    private func append(_ data: Data) throws {
        if !FileManager.default.fileExists(atPath: url.path) {
            try LocalConfigurationFile.write(Data(), to: url)
        }
        let parent = Darwin.open(url.deletingLastPathComponent().path, O_RDONLY | O_DIRECTORY | O_NOFOLLOW | O_CLOEXEC)
        guard parent >= 0 else { throw POSIXError(.EPERM) }
        defer { Darwin.close(parent) }
        var directoryInfo = stat()
        guard fstat(parent, &directoryInfo) == 0, directoryInfo.st_uid == getuid(), directoryInfo.st_mode & 0o022 == 0
        else { throw POSIXError(.EPERM) }
        let fd = openat(parent, url.lastPathComponent, O_WRONLY | O_APPEND | O_NOFOLLOW | O_NONBLOCK | O_CLOEXEC)
        guard fd >= 0 else { throw POSIXError(.EIO) }
        defer { Darwin.close(fd) }
        var info = stat()
        guard fstat(fd, &info) == 0, info.st_mode & S_IFMT == S_IFREG,
            info.st_uid == getuid(), info.st_mode & 0o077 == 0, info.st_size >= 0,
            info.st_size <= LocalConfigurationFile.maximumBytes
        else { throw POSIXError(.EPERM) }
        guard data.count <= maximumBytes else { return }
        if info.st_size + Int64(data.count) > maximumBytes {
            if let previous = try LocalConfigurationFile.read(at: url) {
                try LocalConfigurationFile.write(previous, to: previousURL)
            }
            try LocalConfigurationFile.write(data, to: url)
            return
        }
        try data.withUnsafeBytes { bytes in
            var offset = 0
            while offset < bytes.count {
                let count = Darwin.write(fd, bytes.baseAddress!.advanced(by: offset), bytes.count - offset)
                if count < 0, errno == EINTR { continue }
                guard count > 0 else { throw POSIXError(.EIO) }
                offset += count
            }
        }
    }
}
