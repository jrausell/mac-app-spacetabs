import Foundation
import Synchronization

/// Records the caller before async work starts, including work waiting on AX.
public final class DiagnosticOperation: Sendable {
    private let log: DiagnosticLog
    private let details: [String: String]
    private let source: (file: String, function: String, line: Int)
    private let started = ContinuousClock.now
    private let state = Mutex((finished: false, slowReported: false))
    private let timer: DispatchSourceTimer

    public init(
        _ name: String, details: [String: String] = [:], log: DiagnosticLog = .shared,
        file: String = #fileID, function: String = #function, line: Int = #line
    ) {
        self.log = log
        self.details = details.merging(["operation": name, "id": UUID().uuidString]) { _, new in new }
        source = (file, function, line)
        timer = DispatchSource.makeTimerSource(queue: .global(qos: .utility))
        log.record("operation.begin", details: self.details, file: file, function: function, line: line)
        timer.schedule(deadline: .now() + 10)
        timer.setEventHandler { [weak self] in self?.reportSlowIfNeeded() }
        timer.resume()
    }

    func reportSlowIfNeeded() {
        guard
            state.withLock({ value in
                guard !value.finished, !value.slowReported else { return false }
                value.slowReported = true
                return true
            })
        else { return }
        log.record(
            "operation.slow", level: "warning", details: details,
            file: source.file, function: source.function, line: source.line)
    }

    public func finish() {
        guard
            state.withLock({ value in
                if value.finished { return false }
                value.finished = true
                return true
            })
        else { return }
        timer.cancel()
        let duration = started.duration(to: .now).components
        var fields = details
        fields["seconds"] = String(Double(duration.seconds) + Double(duration.attoseconds) / 1e18)
        log.record("operation.end", details: fields, file: source.file, function: source.function, line: source.line)
    }
    deinit { timer.cancel() }
}
