import Darwin
import Foundation

/// Directory notifications, not a periodic application search. Bundles are not
/// watched recursively; internal writes by running apps do not trigger scans.
@MainActor
final class ApplicationDirectoryMonitor {
    private var sources: [URL: any DispatchSourceFileSystemObject] = [:]
    private var pending: Task<Void, Never>?
    var changed: () -> Void = {}

    func update(_ directories: Set<URL>) {
        for url in Set(sources.keys).subtracting(directories) { sources.removeValue(forKey: url)?.cancel() }
        for url in directories where sources[url] == nil {
            let descriptor = open(url.path, O_EVTONLY)
            guard descriptor >= 0 else { continue }
            let source = DispatchSource.makeFileSystemObjectSource(
                fileDescriptor: descriptor,
                eventMask: [.write, .delete, .rename, .revoke], queue: .main)
            source.setEventHandler { [weak self] in
                MainActor.assumeIsolated { self?.schedule() }
            }
            source.setCancelHandler { close(descriptor) }
            sources[url] = source
            source.resume()
        }
    }

    private func schedule() {
        pending?.cancel()
        pending = Task { [weak self] in
            do { try await Task.sleep(for: .milliseconds(700)) } catch { return }
            self?.changed()
        }
    }

    func stop() {
        pending?.cancel()
        for source in sources.values { source.cancel() }
        sources.removeAll()
    }
}
