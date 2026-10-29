import Foundation
import SpaceTabsCore

/// The utility queue can report a suspected stall while the main queue is blocked.
final class ResponsivenessMonitor: @unchecked Sendable {
    private let queue = DispatchQueue(label: "dev.spacetabs.responsiveness", qos: .utility)
    private var timer: DispatchSourceTimer?
    private var state = ResponsivenessState()
    private var generation = 0
    private var context: [String: String] = [:]

    func start() {
        queue.async { [self] in
            guard timer == nil else { return }
            let timer = DispatchSource.makeTimerSource(queue: queue)
            timer.schedule(deadline: .now() + 1, repeating: 1, leeway: .milliseconds(200))
            timer.setEventHandler { [weak self] in self?.tick() }
            self.timer = timer
            timer.resume()
        }
    }

    func update(_ context: [String: String]) { queue.async { self.context = context } }
    func stop() {
        queue.sync {
            self.timer?.cancel()
            self.timer = nil
            self.generation += 1
            self.state = ResponsivenessState()
        }
    }

    private func tick() {
        let result = state.tick(at: ProcessInfo.processInfo.systemUptime)
        if result.event == .stalled {
            DiagnosticLog.shared.record("ui.suspected-stall", level: "warning", details: context)
        }
        guard result.sendHeartbeat else { return }
        generation += 1
        let request = generation
        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            self.queue.async {
                guard self.timer != nil, request == self.generation else { return }
                if case .recovered(let seconds) = self.state.acknowledge(at: ProcessInfo.processInfo.systemUptime) {
                    var fields = self.context
                    fields["seconds"] = String(format: "%.2f", seconds)
                    DiagnosticLog.shared.record("ui.recovered", details: fields)
                }
            }
        }
    }
}
