import Darwin
import Foundation

/// Data-only, bounded local storage. Files are never evaluated or used as commands.
/// No symlink following; writes replace a private temporary file atomically.
public enum LocalConfigurationFile {
    public static let maximumBytes = 2 * 1024 * 1024

    public static func read(at url: URL) throws -> Data? {
        guard url.isFileURL, url.host == nil || url.host == "" || url.host == "localhost" else { throw invalid() }
        let fd = Darwin.open(url.path, O_RDONLY | O_NOFOLLOW | O_NONBLOCK | O_CLOEXEC)
        guard fd >= 0 else {
            if errno == ENOENT { return nil }
            throw invalid()
        }
        defer { Darwin.close(fd) }
        var info = stat()
        guard fstat(fd, &info) == 0, info.st_mode & S_IFMT == S_IFREG,
            info.st_uid == getuid(), info.st_mode & 0o022 == 0,
            info.st_size >= 0, info.st_size <= maximumBytes
        else { throw invalid() }
        var result = Data()
        var buffer = [UInt8](repeating: 0, count: 16_384)
        while true {
            let count = buffer.withUnsafeMutableBytes { Darwin.read(fd, $0.baseAddress!, $0.count) }
            if count < 0, errno == EINTR { continue }
            guard count >= 0 else { throw invalid() }
            if count == 0 { return result }
            guard result.count + count <= maximumBytes else { throw invalid() }
            result.append(contentsOf: buffer.prefix(count))
        }
    }

    public static func write(_ data: Data, to url: URL) throws {
        guard url.isFileURL, url.host == nil || url.host == "" || url.host == "localhost",
            data.count <= maximumBytes
        else { throw invalid() }
        let parent = url.deletingLastPathComponent()
        try FileManager.default.createDirectory(
            at: parent, withIntermediateDirectories: true,
            attributes: [.posixPermissions: 0o700])
        let directory = Darwin.open(parent.path, O_RDONLY | O_DIRECTORY | O_NOFOLLOW | O_CLOEXEC)
        guard directory >= 0 else { throw invalid() }
        defer { Darwin.close(directory) }
        var info = stat()
        guard fstat(directory, &info) == 0, info.st_uid == getuid(), info.st_mode & 0o022 == 0 else { throw invalid() }
        let name = url.lastPathComponent
        guard !name.isEmpty, name != ".", name != ".." else { throw invalid() }
        if fstatat(directory, name, &info, AT_SYMLINK_NOFOLLOW) == 0 {
            guard info.st_mode & S_IFMT == S_IFREG, info.st_uid == getuid() else { throw invalid() }
        } else if errno != ENOENT {
            throw invalid()
        }
        let temporary = ".spacetabs-\(UUID().uuidString).tmp"
        let fd = openat(directory, temporary, O_WRONLY | O_CREAT | O_EXCL | O_NOFOLLOW | O_CLOEXEC, mode_t(0o600))
        guard fd >= 0 else { throw invalid() }
        defer {
            Darwin.close(fd)
            unlinkat(directory, temporary, 0)
        }
        try data.withUnsafeBytes { bytes in
            var offset = 0
            while offset < bytes.count {
                let count = Darwin.write(fd, bytes.baseAddress!.advanced(by: offset), bytes.count - offset)
                if count < 0, errno == EINTR { continue }
                guard count > 0 else { throw invalid() }
                offset += count
            }
        }
        guard fsync(fd) == 0, renameat(directory, temporary, directory, name) == 0 else { throw invalid() }
    }

    private static func invalid() -> ConfigurationError {
        ConfigurationError(
            L10n.tr(
                "Local configuration rejected. It must be a regular file owned by the current user, without symbolic links or shared write access, and no larger than 2 MB."
            )
        )
    }
}
