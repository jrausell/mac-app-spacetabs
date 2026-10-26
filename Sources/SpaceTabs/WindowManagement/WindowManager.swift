import AppKit
import ApplicationServices
import SpaceTabsCore
import os

/// The coordinator never performs synchronous AX calls. Each process owns an
/// independent actor and AX handles. A slow discovery cannot hold other apps.
actor WindowManager: WindowLayoutAccess, WindowFocusAccess, WindowPresentationAccess, ManagedWindowFocusSource {
    private var sessions: [Int32: WindowProcessSession] = [:]
    private var owners: [UUID: Int32] = [:]
    private var candidates: [UUID: Int32] = [:]
    private var snapshots: [UUID: WindowSnapshot] = [:]
    private var warnings: [Int32: [String]] = [:]
    private var notices: [Int32: [String]] = [:]
    private var fullDiscoveries = 0
    private var scopedDiscoveries = 0
    private var stopped = false
    private let locator = WindowProcessLocator()
    private var discoveryTiming = TimingStatistics()
    private let signposter = OSSignposter(subsystem: SpaceTabsIdentity.appBundleID, category: L10n.tr("Accessibility"))

    private func session(_ pid: Int32) -> WindowProcessSession {
        if let value = sessions[pid] { return value }
        let value = WindowProcessSession(processID: pid)
        sessions[pid] = value
        return value
    }
    private func owner(_ id: UUID) throws -> WindowProcessSession {
        guard !stopped, let pid = owners[id], let session = sessions[pid] else {
            throw WindowOperationError(message: L10n.tr("The window is no longer available. Refresh the list."))
        }
        return session
    }
    func scan(apps: [ApplicationDescriptor], only processes: Set<Int32>? = nil) async -> ScanResult {
        guard !stopped else { return ScanResult(windows: [], warnings: [], removed: [], focused: nil) }
        if processes == nil { fullDiscoveries += 1 } else { scopedDiscoveries += 1 }
        let active = Set(apps.map(\.pid))
        let lost = Set(sessions.keys).subtracting(active)
        for pid in lost {
            if let old = sessions.removeValue(forKey: pid) { await old.shutdown() }
            warnings[pid] = nil
            notices[pid] = nil
        }
        var removed = Set(owners.filter { !active.contains($0.value) }.keys)
        for id in removed {
            owners[id] = nil
            snapshots[id] = nil
        }
        let work = apps.filter { processes?.contains($0.pid) ?? true }.map { ($0, session($0.pid)) }
        let interval = signposter.beginInterval("Discovery", id: signposter.makeSignpostID())
        let results = await BoundedWorkPool.map(work, limit: 3) { app, worker in
            let started = ContinuousClock.now
            let result = await worker.scan(apps: [app])
            return (app.pid, result, started.duration(to: .now))
        }
        signposter.endInterval("Discovery", interval)
        guard !stopped else { return ScanResult(windows: [], warnings: [], removed: [], focused: nil) }
        for (pid, result, duration) in results where active.contains(pid) {
            discoveryTiming.record(duration)
            warnings[pid] = result.warnings
            notices[pid] = result.notices
            for id in result.removed {
                snapshots[id] = nil
                owners[id] = nil
                removed.insert(id)
            }
            for window in result.windows {
                snapshots[window.id] = window
                owners[window.id] = pid
            }
        }
        let windows = snapshots.values.sorted {
            if $0.appName != $1.appName { return $0.appName.localizedStandardCompare($1.appName) == .orderedAscending }
            if $0.pid != $1.pid { return $0.pid < $1.pid }
            return $0.id.uuidString < $1.id.uuidString
        }
        return ScanResult(
            windows: windows, warnings: Array(Set(warnings.values.flatMap { $0 })).sorted(), removed: removed,
            focused: nil,
            notices: Array(Set(notices.values.flatMap { $0 })).sorted())
    }
    func focusedManagedID() async -> UUID? { await focusedManagedID(timeout: 0.25) }
    func focusedManagedID(timeout: Float) async -> UUID? {
        guard !stopped,
            let pid = await MainActor.run(body: { NSWorkspace.shared.frontmostApplication?.processIdentifier }),
            let worker = sessions[pid]
        else { return nil }
        let focused = await worker.focusedManagedID(timeout: timeout)
        let currentPID = await MainActor.run { NSWorkspace.shared.frontmostApplication?.processIdentifier }
        return currentPID == pid ? focused : nil
    }
    func captureDragCandidate(at point: CGPoint) async -> UUID? { try? await captureRightDrag(at: point).token }
    func captureRightDrag(at point: CGPoint) async throws -> DragCapture {
        guard !stopped else { throw CancellationError() }
        let pid = try await locator.process(at: point)
        let worker = session(pid)
        let capture = try await worker.captureRightDrag(at: point)
        guard !stopped, sessions[pid] === worker else {
            await worker.discardDragCandidate(capture.token)
            throw CancellationError()
        }
        candidates[capture.token] = pid
        return capture
    }

    func dragCandidateMoved(_ token: UUID) async -> Bool {
        guard let pid = candidates[token], let worker = sessions[pid] else { return false }
        return await worker.dragCandidateMoved(token)
    }
    func discardDragCandidate(_ token: UUID) async {
        guard let pid = candidates.removeValue(forKey: token), let worker = sessions[pid] else { return }
        await worker.discardDragCandidate(token)
    }
    func finishDragCandidate(_ token: UUID) async throws -> WindowSnapshot {
        guard !stopped, let pid = candidates.removeValue(forKey: token), let worker = sessions[pid] else {
            throw CancellationError()
        }
        let window = try await worker.finishDragCandidate(token)
        owners[window.id] = pid
        snapshots[window.id] = window
        return window
    }
    func resetAccessibilityRetries() async {
        for worker in sessions.values { await worker.resetAccessibilityRetries() }
    }
    func discoveryDiagnostics() async -> String {
        var details =
            L10n.tr(
                "Full scans: \(fullDiscoveries)\nApp scans: \(scopedDiscoveries)\nCached windows: \(snapshots.count)\nAX sessions per app: \(sessions.count)\nConcurrent discovery scans: at most 3\nTime per app: \(discoveryTiming.summary)"
            )
        for pid in sessions.keys.sorted() {
            if let worker = sessions[pid] {
                details += "\n--- PID \(pid) ---\n" + (await worker.discoveryDiagnostics())
            }
        }
        return details
    }
    private var operations: WindowOperations<WindowManager> { WindowOperations(backend: self) }
    func state(of id: UUID) async throws -> OriginalWindowState { try await operations.snapshot(id) }
    func place(_ id: UUID, frame: CGRect) async throws { try await operations.execute([.place(id, frame)]) }
    func restore(_ id: UUID, state: OriginalWindowState) async throws { try await operations.restore(id, state: state) }
    func move(_ id: UUID, frame: CGRect, sourceReplacement: UUID?, sourceFrame: CGRect) async throws {
        var commands: [WindowCommand] = [.place(id, frame)]
        if let sourceReplacement { commands.append(.place(sourceReplacement, sourceFrame)) }
        try await operations.execute(commands)
        if let sourceReplacement { try await raise(sourceReplacement, focus: false) }
    }
    func applyLayout(frames: [UUID: CGRect], selected: [UUID], raiseSelected: Bool = false) async throws {
        try await WindowLayoutOperations(backend: self).apply(
            frames: frames, selected: selected, raiseSelected: raiseSelected)
    }
    func frame(_ id: UUID) async throws -> CGRect { try await owner(id).frame(id) }
    func minimized(_ id: UUID) async throws -> Bool { try await owner(id).minimized(id) }
    func cachedFrame(_ id: UUID) async -> CGRect? { try? await owner(id).cachedFrame(id) }
    func validatePlacement(_ id: UUID) async throws { try await owner(id).validatePlacement(id) }
    func writeMinimized(_ id: UUID, minimized: Bool) async throws {
        try await owner(id).writeMinimized(id, minimized: minimized)
    }
    func writeFrame(_ id: UUID, frame: CGRect) async throws { try await owner(id).writeFrame(id, frame: frame) }
    func prepareFocus(_ id: UUID) async throws { try await owner(id).prepareFocus(id) }
    func preparePresentation(_ id: UUID) async throws { try await owner(id).preparePresentation(id) }
    func requestActivation(_ id: UUID) async -> Bool { (try? await owner(id).requestActivation(id)) ?? false }
    func applicationIsActive(_ id: UUID) async -> Bool { (try? await owner(id).applicationIsActive(id)) ?? false }
    func windowIsFocused(_ id: UUID) async -> Bool { (try? await owner(id).windowIsFocused(id)) ?? false }
    func raiseAndFocus(_ id: UUID) async throws { try await owner(id).raiseAndFocus(id) }
    func raise(_ id: UUID, focus: Bool = true) async throws { try await owner(id).raise(id, focus: focus) }
    func shutdown() async {
        stopped = true
        for worker in sessions.values { await worker.shutdown() }
        sessions = [:]
        owners = [:]
        candidates = [:]
        snapshots = [:]
    }
}

private actor WindowProcessLocator {
    nonisolated let executor = AXQueueExecutor(label: "dev.spacetabs.ax.hit-test")
    nonisolated var unownedExecutor: UnownedSerialExecutor { executor.asUnownedSerialExecutor() }
    func process(at point: CGPoint) throws -> Int32 {
        guard AXIsProcessTrusted() else { throw WindowError(message: L10n.tr("Accessibility access is missing.")) }
        let system = AXUIElementCreateSystemWide()
        AXUIElementSetMessagingTimeout(system, 0.2)
        var hit: AXUIElement?
        let status = AXUIElementCopyElementAtPosition(system, Float(point.x), Float(point.y), &hit)
        guard status == .success, let hit else {
            throw WindowError(
                message:
                    L10n.tr(
                        "Accessibility could not identify the element under the pointer (AX \(status.rawValue)). Try the title bar of a standard window."
                    )
            )
        }
        var pid: pid_t = 0
        let pidStatus = AXUIElementGetPid(hit, &pid)
        guard pidStatus == .success, pid > 0 else {
            throw WindowError(
                message: L10n.tr("The element under the pointer does not identify an app (AX \(pidStatus.rawValue))."))
        }
        return pid
    }
}
