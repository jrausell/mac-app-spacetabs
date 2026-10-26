import AppKit
import ApplicationServices
import Foundation
import SpaceTabsCore

/// AX references never leave this actor. Commands are serialized by AppModel;
/// asynchronous settlement waits release the executor instead of blocking it.
actor WindowProcessSession: WindowAccess, WindowPresentationAccess {
    nonisolated let executor: AXQueueExecutor
    nonisolated var unownedExecutor: UnownedSerialExecutor { executor.asUnownedSerialExecutor() }
    let processID: Int32
    init(processID: Int32) {
        self.processID = processID
        executor = AXQueueExecutor(label: "dev.spacetabs.ax.\(processID)")
    }

    private struct Entry {
        let element: AXUIElement
        let pid: Int32
        var snapshot: WindowSnapshot
    }
    private var entries: [UUID: Entry] = [:]
    private struct DragCandidate {
        let element: AXUIElement
        let pid: Int32
        let initial: CGRect
    }
    private var dragCandidates: [UUID: DragCandidate] = [:]
    private var observers: [Int32: AXObserver] = [:]
    private var applicationNotifications: [Int32: Set<String>] = [:]
    private var windowNotifications: [UUID: Set<String>] = [:]
    private var subscriptionWarnings: [Int32: String] = [:]
    private var discoveryWarnings: [Int32: String] = [:]
    private var discoveryRetry = AccessibilityRetryPolicy()
    private var notificationRetry = AccessibilityRetryPolicy()
    private var observerRetry = AccessibilityRetryPolicy()

    // MARK: - Retry state and diagnostics

    func resetAccessibilityRetries() {
        discoveryRetry.reset()
        notificationRetry.reset()
        observerRetry.reset()
    }
    private var fullDiscoveries = 0
    private var scopedDiscoveries = 0
    private var lastScanMilliseconds: Double = 0
    private var focusRaises = 0
    private var backgroundRaises = 0
    private var focusTrace: [String] = []

    func discoveryDiagnostics() -> String {
        L10n.tr(
            "Full scans: \(fullDiscoveries)\nApp scans: \(scopedDiscoveries)\nCached windows: \(entries.count)\nApp observers: \(observers.count)\nLast scan (ms): \(Int(lastScanMilliseconds))\nRaises with focus: \(focusRaises)\nRaises without focus: \(backgroundRaises)\nRecent AX selections:\n\(focusTrace.joined(separator: "\n"))"
        )
    }

    private func sortedSnapshots() -> [WindowSnapshot] {
        // Notification badges in a browser title must not reorder the picker.
        entries.values.map(\.snapshot).sorted {
            if $0.appName != $1.appName { return $0.appName.localizedStandardCompare($1.appName) == .orderedAscending }
            if $0.pid != $1.pid { return $0.pid < $1.pid }
            return $0.id.uuidString < $1.id.uuidString
        }
    }
    // MARK: - Window backend

    private var operations: WindowOperations<WindowProcessSession> { WindowOperations(backend: self) }

    func frame(_ id: UUID) throws -> CGRect {
        let result = try readFrame(element(for: id))
        cache(id, state: OriginalWindowState(frame: result, minimized: entries[id]?.snapshot.state.minimized ?? false))
        return result
    }

    func minimized(_ id: UUID) throws -> Bool {
        let result = try readMinimized(element(for: id))
        if let frame = entries[id]?.snapshot.state.frame {
            cache(id, state: OriginalWindowState(frame: frame, minimized: result))
        }
        return result
    }

    func cachedFrame(_ id: UUID) -> CGRect? { entries[id]?.snapshot.state.frame }

    func validatePlacement(_ id: UUID) throws {
        let element = try element(for: id)
        if (value(element, "AXFullScreen" as CFString) as? Bool) == true {
            throw WindowError(message: L10n.tr("Leave native full screen before assigning this window."))
        }
        for attribute in [kAXPositionAttribute, kAXSizeAttribute, kAXMinimizedAttribute] {
            var settable: DarwinBoolean = false
            let status = AXUIElementIsAttributeSettable(element, attribute as CFString, &settable)
            guard status == .success else {
                throw accessError(status, attribute: attribute, operation: L10n.tr("inspect"))
            }
            guard settable.boolValue else {
                throw WindowAccessError(
                    .unsupported, attribute: attribute,
                    detail: L10n.tr("The app does not allow this attribute to be changed."))
            }
        }
        if let children = value(element, kAXChildrenAttribute as CFString) as? [AXUIElement],
            children.contains(where: { string($0, kAXRoleAttribute) == kAXSheetRole })
        {
            throw WindowError(message: L10n.tr("Close this window's dialog before arranging it."))
        }
    }

    func writeMinimized(_ id: UUID, minimized: Bool) throws {
        let status = AXUIElementSetAttributeValue(
            try element(for: id), kAXMinimizedAttribute as CFString,
            minimized ? kCFBooleanTrue : kCFBooleanFalse)
        guard status == .success else {
            throw accessError(status, attribute: kAXMinimizedAttribute, operation: L10n.tr("write"))
        }
    }

    func writeFrame(_ id: UUID, frame: CGRect) throws {
        guard frame.width > 0, frame.height > 0,
            [frame.minX, frame.minY, frame.width, frame.height].allSatisfy(\.isFinite)
        else {
            throw WindowError(message: L10n.tr("The target area is invalid."))
        }
        let element = try element(for: id)
        var size = frame.size
        var position = frame.origin
        guard let sizeValue = AXValueCreate(.cgSize, &size), let positionValue = AXValueCreate(.cgPoint, &position)
        else {
            throw WindowError(message: L10n.tr("Could not prepare the window frame."))
        }
        for (attribute, value) in [
            (kAXSizeAttribute, sizeValue), (kAXPositionAttribute, positionValue), (kAXSizeAttribute, sizeValue),
        ] {
            let status = AXUIElementSetAttributeValue(element, attribute as CFString, value)
            guard status == .success else {
                throw accessError(status, attribute: attribute, operation: L10n.tr("write"))
            }
        }
    }

    private func cache(_ id: UUID, state: OriginalWindowState) {
        guard var entry = entries[id] else { return }
        let old = entry.snapshot
        entry.snapshot = WindowSnapshot(
            id: old.id, pid: old.pid, appName: old.appName, identity: old.identity,
            state: state, incompatibility: old.incompatibility)
        entries[id] = entry
    }

    // MARK: - Pointer capture

    /// Hit-test only after the user starts a modified drag; AX handles stay in
    /// this actor and the preview never writes external window attributes.
    func captureDragCandidate(at point: CGPoint) -> UUID? { try? captureRightDrag(at: point).token }

    func captureRightDrag(at point: CGPoint) throws -> DragCapture {
        try Task.checkCancellation()
        guard AXIsProcessTrusted() else { throw WindowError(message: L10n.tr("Accessibility access is missing.")) }
        let system = AXUIElementCreateSystemWide()
        AXUIElementSetMessagingTimeout(system, 0.2)
        var hit: AXUIElement?
        let hitStatus = AXUIElementCopyElementAtPosition(system, Float(point.x), Float(point.y), &hit)
        guard hitStatus == .success, let hit else {
            throw WindowError(
                message: L10n.tr("Could not read the window under the pointer (AX \(hitStatus.rawValue))."))
        }
        var candidate = hit
        for _ in 0..<16 {
            try Task.checkCancellation()
            AXUIElementSetMessagingTimeout(candidate, 0.2)
            if string(candidate, kAXRoleAttribute) == kAXWindowRole as String { break }
            if let window = value(candidate, kAXWindowAttribute as CFString),
                CFGetTypeID(window) == AXUIElementGetTypeID()
            {
                candidate = window as! AXUIElement
                break
            }
            guard let parent = value(candidate, kAXParentAttribute as CFString),
                CFGetTypeID(parent) == AXUIElementGetTypeID()
            else {
                throw WindowError(
                    message: L10n.tr("The element under the pointer does not expose its window through Accessibility."))
            }
            candidate = parent as! AXUIElement
        }
        defer { AXUIElementSetMessagingTimeout(candidate, 0.75) }
        var pid: pid_t = 0
        guard AXUIElementGetPid(candidate, &pid) == .success, pid == processID else {
            throw WindowError(message: L10n.tr("The window under the pointer changed during capture."))
        }
        guard let app = NSRunningApplication(processIdentifier: pid), !app.isTerminated,
            let bundleID = app.bundleIdentifier, !bundleID.isEmpty,
            pid != ProcessInfo.processInfo.processIdentifier, bundleID != SpaceTabsIdentity.appBundleID,
            bundleID != SpaceTabsIdentity.settingsBundleID
        else {
            throw WindowError(
                message: L10n.tr("Use the gesture on another app's window, outside SpaceTabs settings and tab bars."))
        }
        guard string(candidate, kAXRoleAttribute) == kAXWindowRole as String,
            string(candidate, kAXSubroleAttribute) == kAXStandardWindowSubrole as String
        else {
            throw WindowError(
                message: L10n.tr(
                    "The gesture requires a standard window. Menus, panels, and dialogs are not supported."))
        }
        let frame = try readFrame(candidate)
        if let reason = incompatibility(candidate) { throw WindowError(message: reason) }
        let token = UUID()
        dragCandidates[token] = DragCandidate(element: candidate, pid: pid, initial: frame)
        let title = string(candidate, kAXTitleAttribute) ?? app.localizedName ?? L10n.tr("Window")
        return DragCapture(token: token, initialFrame: frame, title: title)
    }

    func dragCandidateMoved(_ token: UUID) -> Bool {
        guard !Task.isCancelled, let candidate = dragCandidates[token] else { return false }
        AXUIElementSetMessagingTimeout(candidate.element, 0.2)
        defer { AXUIElementSetMessagingTimeout(candidate.element, 0.75) }
        guard let frame = try? readFrame(candidate.element) else { return false }
        return ZoneDragState.isWindowMove(from: candidate.initial, to: frame)
    }

    func discardDragCandidate(_ token: UUID) { dragCandidates[token] = nil }

    func finishDragCandidate(_ token: UUID) throws -> WindowSnapshot {
        if Task.isCancelled {
            dragCandidates[token] = nil
            throw CancellationError()
        }
        guard let candidate = dragCandidates.removeValue(forKey: token),
            let app = NSRunningApplication(processIdentifier: candidate.pid), !app.isTerminated,
            candidate.pid != ProcessInfo.processInfo.processIdentifier,
            let bundleID = app.bundleIdentifier, !bundleID.isEmpty, bundleID != SpaceTabsIdentity.appBundleID,
            bundleID != SpaceTabsIdentity.settingsBundleID
        else {
            throw WindowError(message: L10n.tr("The dragged window is no longer available."))
        }
        AXUIElementSetMessagingTimeout(candidate.element, 0.2)
        defer { AXUIElementSetMessagingTimeout(candidate.element, 0.75) }
        let state = try readState(candidate.element)
        // Movement was confirmed before showing targets. Native edge tiling
        // may resize a dragged window on mouse-up; that is still a valid drop.
        if let reason = incompatibility(candidate.element) { throw WindowError(message: reason) }
        let id =
            entries.first { $0.value.pid == candidate.pid && CFEqual($0.value.element, candidate.element) }?.key
            ?? UUID()
        let snapshot = WindowSnapshot(
            id: id, pid: candidate.pid, appName: app.localizedName ?? L10n.tr("App"),
            identity: WindowIdentity(
                bundleID: bundleID, title: string(candidate.element, kAXTitleAttribute) ?? "",
                document: string(candidate.element, kAXDocumentAttribute)), state: state)
        entries[id] = Entry(element: candidate.element, pid: candidate.pid, snapshot: snapshot)
        let root = AXUIElementCreateApplication(candidate.pid)
        AXUIElementSetMessagingTimeout(root, 0.2)
        observeApplication(root, pid: candidate.pid)
        observeWindow(candidate.element, pid: candidate.pid, id: id)
        return snapshot
    }

    // MARK: - Focus and presentation

    func focusedManagedID(timeout: Float = 0.25) -> UUID? {
        let system = AXUIElementCreateSystemWide()
        AXUIElementSetMessagingTimeout(system, timeout)
        guard let app = value(system, kAXFocusedApplicationAttribute as CFString),
            CFGetTypeID(app) == AXUIElementGetTypeID()
        else { return nil }
        let application = app as! AXUIElement
        AXUIElementSetMessagingTimeout(application, timeout)
        guard let window = value(application, kAXFocusedWindowAttribute as CFString),
            CFGetTypeID(window) == AXUIElementGetTypeID()
        else { return nil }
        return entries.first { CFEqual($0.value.element, window) }?.key
    }

    func preparePresentation(_ id: UUID) async throws {
        let element = try element(for: id)
        guard let pid = entries[id]?.pid else { return }
        await MainActor.run {
            if let app = NSRunningApplication(processIdentifier: pid), app.isHidden { app.unhide() }
        }
        try Task.checkCancellation()
        if try readMinimized(element) { try await operations.execute([.minimize(id, false)]) }
    }

    func prepareFocus(_ id: UUID) async throws {
        let element = try element(for: id)
        trace(id, L10n.tr("Selection started"))
        if try readMinimized(element) {
            trace(id, L10n.tr("Restore minimized window"))
            try await operations.execute([.minimize(id, false)])
        }
        setOptional(element, attribute: kAXMainAttribute, id: id)
    }

    func requestActivation(_ id: UUID) async -> Bool {
        guard let pid = entries[id]?.pid else { return false }
        let application = AXUIElementCreateApplication(pid)
        AXUIElementSetMessagingTimeout(application, 0.25)
        // Our tab panels intentionally do not activate SpaceTabs. AppKit's
        // cooperative activation can be refused to an inactive caller. Use the
        // public Accessibility activation request authorized by the user.
        let status = AXUIElementSetAttributeValue(application, kAXFrontmostAttribute as CFString, kCFBooleanTrue)
        trace(id, L10n.tr("AXFrontmost=true: \(status.rawValue)"))
        if status == .success { return true }
        let accepted = await MainActor.run {
            guard let app = NSRunningApplication(processIdentifier: pid), !app.isTerminated else { return false }
            if app.isActive { return true }
            if NSApp.isActive { NSApp.yieldActivation(to: app) }
            return app.activate(options: [])
        }
        trace(id, L10n.tr("AppKit fallback accepted: \(accepted)"))
        return accepted
    }

    func applicationIsActive(_ id: UUID) async -> Bool {
        guard let pid = entries[id]?.pid else { return false }
        let root = AXUIElementCreateApplication(pid)
        AXUIElementSetMessagingTimeout(root, 0.2)
        if let active = value(root, kAXFrontmostAttribute as CFString) as? Bool {
            trace(id, L10n.tr("AXFrontmost read: \(active)"))
            return active
        }
        return await MainActor.run { NSWorkspace.shared.frontmostApplication?.processIdentifier == pid }
    }

    func raiseAndFocus(_ id: UUID) throws { try raise(id) }
    func windowIsFocused(_ id: UUID) async -> Bool {
        guard let entry = entries[id], await applicationIsActive(id) else { return false }
        let root = AXUIElementCreateApplication(entry.pid)
        AXUIElementSetMessagingTimeout(root, 0.2)
        guard let focused = value(root, kAXFocusedWindowAttribute as CFString),
            CFGetTypeID(focused) == AXUIElementGetTypeID()
        else {
            trace(id, L10n.tr("AXFocusedWindow unavailable"))
            return false
        }
        let matches = CFEqual(entry.element, focused)
        trace(id, L10n.tr("AXFocusedWindow matches: \(matches)"))
        return matches
    }

    private func trace(_ id: UUID, _ event: String) {
        let owner = entries[id]?.snapshot.identity.bundleID ?? id.uuidString
        focusTrace.append("\(owner): \(event)")
        if focusTrace.count > 32 { focusTrace.removeFirst(focusTrace.count - 32) }
    }

    private func setOptional(_ element: AXUIElement, attribute: String, id: UUID) {
        var settable: DarwinBoolean = false
        let status = AXUIElementIsAttributeSettable(element, attribute as CFString, &settable)
        guard status == .success, settable.boolValue else {
            trace(id, L10n.tr("\(attribute) not writable (\(status.rawValue))"))
            return
        }
        let result = AXUIElementSetAttributeValue(element, attribute as CFString, kCFBooleanTrue)
        trace(id, L10n.tr("\(attribute)=true: \(result.rawValue)"))
    }

    func raise(_ id: UUID, focus: Bool = true) throws {
        let element = try element(for: id)
        if focus {
            setOptional(element, attribute: kAXMainAttribute, id: id)
            setOptional(element, attribute: kAXFocusedAttribute, id: id)
        }
        if focus { focusRaises += 1 } else { backgroundRaises += 1 }
        let error = AXUIElementPerformAction(element, kAXRaiseAction as CFString)
        trace(id, L10n.tr("AXRaise focus=\(focus): \(error.rawValue)"))
        guard error == .success else { throw WindowError(message: describe(error)) }
    }

    private func element(for id: UUID) throws -> AXUIElement {
        guard AXIsProcessTrusted() else {
            throw WindowError(
                message: L10n.tr("Accessibility access is not granted. Check SpaceTabs in System Settings."))
        }
        guard let entry = entries[id] else {
            throw WindowError(message: L10n.tr("The window is no longer available. Refresh the list."))
        }
        return entry.element
    }

    // MARK: - Discovery

    func scan(apps: [ApplicationDescriptor], only processes: Set<Int32>? = nil) -> ScanResult {
        let started = Date()
        defer { lastScanMilliseconds = Date().timeIntervalSince(started) * 1000 }
        guard AXIsProcessTrusted() else {
            return ScanResult(
                windows: [], warnings: [L10n.tr("Accessibility access is missing.")], removed: [], focused: nil)
        }
        let apps = apps.filter {
            $0.pid == processID && $0.pid != ProcessInfo.processInfo.processIdentifier
                && $0.bundleID != SpaceTabsIdentity.settingsBundleID
        }
        if processes == nil { fullDiscoveries += 1 } else { scopedDiscoveries += 1 }
        var found = Set(entries.filter { entry in processes.map { !$0.contains(entry.value.pid) } ?? false }.keys)
        var warnings: [String] = []
        let pids = Set(apps.map(\.pid))
        for app in apps where processes?.contains(app.pid) ?? true {
            let retryKey = "\(app.pid):windows"
            let now = ProcessInfo.processInfo.systemUptime
            guard discoveryRetry.canAttempt(retryKey, now: now) else {
                found.formUnion(entries.filter { $0.value.pid == app.pid }.keys)
                continue
            }
            let root = AXUIElementCreateApplication(app.pid)
            AXUIElementSetMessagingTimeout(root, 0.25)
            var raw: CFTypeRef?
            let error = AXUIElementCopyAttributeValue(root, kAXWindowsAttribute as CFString, &raw)
            guard error == .success, let raw, CFGetTypeID(raw) == CFArrayGetTypeID(), let list = raw as? [AXUIElement]
            else {
                // A temporary AX failure is not evidence that existing windows closed.
                found.formUnion(entries.filter { $0.value.pid == app.pid }.keys)
                if error != .attributeUnsupported && error != .noValue {
                    discoveryWarnings[app.pid] =
                        L10n.tr(
                            "\(app.name): \(describe(error)) (\(error.rawValue)). Known windows are kept. Retries are limited to new events."
                        )
                    discoveryRetry.failed(retryKey, now: ProcessInfo.processInfo.systemUptime)
                } else {
                    discoveryWarnings[app.pid] = nil
                    discoveryRetry.succeeded(retryKey)
                }
                continue
            }
            discoveryRetry.succeeded(retryKey)
            discoveryWarnings[app.pid] = nil
            observeApplication(root, pid: app.pid)
            let deadline = ProcessInfo.processInfo.systemUptime + 1.0
            for element in list {
                if Task.isCancelled || ProcessInfo.processInfo.systemUptime >= deadline {
                    found.formUnion(entries.keys)
                    discoveryRetry.failed(retryKey, now: ProcessInfo.processInfo.systemUptime)
                    warnings.append(
                        L10n.tr(
                            "\(app.name): scan limit reached. Known windows are kept. Use Refresh if a window is missing."
                        ))
                    break
                }
                AXUIElementSetMessagingTimeout(element, 0.2)
                defer { AXUIElementSetMessagingTimeout(element, 0.75) }
                let existing = entries.first { $0.value.pid == app.pid && CFEqual($0.value.element, element) }?.key
                guard string(element, kAXRoleAttribute) == kAXWindowRole as String,
                    string(element, kAXSubroleAttribute) == kAXStandardWindowSubrole as String
                else {
                    if let existing { found.insert(existing) }
                    continue
                }
                let state: OriginalWindowState
                do {
                    let minimized = try readMinimized(element)
                    if minimized, let existing, let cached = entries[existing]?.snapshot.state.frame {
                        state = OriginalWindowState(frame: cached, minimized: true)
                    } else {
                        state = try readState(element)
                    }
                } catch {
                    if let existing { found.insert(existing) }
                    warnings.append("\(app.name): \(error.localizedDescription)")
                    continue
                }
                let id = existing ?? UUID()
                let reason = incompatibility(element)
                let identity = WindowIdentity(
                    bundleID: app.bundleID, title: string(element, kAXTitleAttribute) ?? "",
                    document: string(element, kAXDocumentAttribute))
                let snapshot = WindowSnapshot(
                    id: id, pid: app.pid, appName: app.name, identity: identity,
                    state: state, incompatibility: reason)
                entries[id] = Entry(element: element, pid: app.pid, snapshot: snapshot)
                found.insert(id)
                observeWindow(element, pid: app.pid, id: id)
            }
        }
        // AXWindows is not a reliable Space-membership API. An omitted window
        // is only removed after its process exits or AX confirms it is invalid.
        found = found.filter { id in entries[id].map { pids.contains($0.pid) } ?? false }
        for (id, entry) in entries where !found.contains(id) && pids.contains(entry.pid) {
            var role: CFTypeRef?
            let status = AXUIElementCopyAttributeValue(entry.element, kAXRoleAttribute as CFString, &role)
            if status != .invalidUIElement { found.insert(id) }
        }
        let removed = Set(entries.keys).subtracting(found)
        for id in removed {
            if let pid = entries[id]?.pid { notificationRetry.reset(prefix: "\(pid):window:\(id):") }
            entries[id] = nil
            windowNotifications[id] = nil
        }
        let knownProcesses = Set(observers.keys).union(subscriptionWarnings.keys).union(discoveryWarnings.keys)
        for pid in knownProcesses where !pids.contains(pid) {
            if let observer = observers.removeValue(forKey: pid) {
                CFRunLoopRemoveSource(CFRunLoopGetMain(), AXObserverGetRunLoopSource(observer), .commonModes)
            }
            applicationNotifications[pid] = nil
            subscriptionWarnings[pid] = nil
            discoveryWarnings[pid] = nil
            discoveryRetry.reset(prefix: "\(pid):")
            notificationRetry.reset(prefix: "\(pid):")
            observerRetry.reset(prefix: "\(pid):")
        }
        let notices = subscriptionWarnings.map { pid, warning in
            "\(apps.first(where: { $0.pid == pid })?.name ?? L10n.tr("App")): \(warning)"
        }.sorted()
        let snapshots = sortedSnapshots()
        let currentWarnings = Array(Set(warnings + discoveryWarnings.values)).sorted()
        return ScanResult(
            windows: snapshots, warnings: currentWarnings, removed: removed, focused: nil, notices: notices)
    }

    // MARK: - Observer lifecycle

    private func observeApplication(_ root: AXUIElement, pid: Int32) {
        let now = ProcessInfo.processInfo.systemUptime
        let processKey = "\(pid):observer"
        guard observerRetry.canAttempt(processKey, now: now) else { return }
        AXUIElementSetMessagingTimeout(root, 0.2)
        if observers[pid] == nil {
            var result: AXObserver?
            let error = AXObserverCreate(
                pid,
                { _, _, notification, context in
                    guard let context else { return }
                    let processID = Int32(Int(bitPattern: context))
                    NotificationCenter.default.post(
                        name: .spaceTabsAXChanged, object: nil,
                        userInfo: ["pid": processID, "notification": notification as String])
                }, &result)
            guard error == .success, let result else {
                subscriptionWarnings[pid] =
                    L10n.tr(
                        "Automatic AX notifications are temporarily unavailable (\(error.rawValue)). This does not mean global access was lost. Use Refresh to retry."
                    )
                observerRetry.failed(processKey, now: now)
                return
            }
            observers[pid] = result
            CFRunLoopAddSource(CFRunLoopGetMain(), AXObserverGetRunLoopSource(result), .commonModes)
        }
        guard let observer = observers[pid] else { return }
        for name in [kAXWindowCreatedNotification, kAXFocusedWindowChangedNotification]
        where !applicationNotifications[pid, default: []].contains(name) {
            let key = "\(pid):app:\(name)"
            guard notificationRetry.canAttempt(key, now: now) else { continue }
            let status = AXObserverAddNotification(
                observer, root, name as CFString, UnsafeMutableRawPointer(bitPattern: Int(pid)))
            if status == .success || status == .notificationAlreadyRegistered {
                applicationNotifications[pid, default: []].insert(name)
                notificationRetry.succeeded(key)
            } else {
                subscriptionWarnings[pid] =
                    L10n.tr(
                        "Partial AX notification support: \(name) unsupported (\(status.rawValue)). This does not pause the manager. Use Refresh to detect changes."
                    )
                notificationRetry.failed(
                    key, now: now, unsupported: status == .notificationUnsupported || status == .notImplemented)
                if status == .cannotComplete || status == .apiDisabled {
                    observerRetry.failed(processKey, now: now)
                    return
                }
            }
        }
        if applicationNotifications[pid, default: []].count == 2 { subscriptionWarnings[pid] = nil }
    }

    private func observeWindow(_ element: AXUIElement, pid: Int32, id: UUID) {
        let now = ProcessInfo.processInfo.systemUptime
        let processKey = "\(pid):observer"
        guard observerRetry.canAttempt(processKey, now: now), let observer = observers[pid] else { return }
        AXUIElementSetMessagingTimeout(element, 0.2)
        defer { AXUIElementSetMessagingTimeout(element, 0.75) }
        for name in [
            kAXUIElementDestroyedNotification,
            kAXWindowMiniaturizedNotification, kAXWindowDeminiaturizedNotification,
        ] where !windowNotifications[id, default: []].contains(name) {
            let key = "\(pid):window:\(id):\(name)"
            guard notificationRetry.canAttempt(key, now: now) else { continue }
            let status = AXObserverAddNotification(
                observer, element, name as CFString, UnsafeMutableRawPointer(bitPattern: Int(pid)))
            if status == .success || status == .notificationAlreadyRegistered {
                windowNotifications[id, default: []].insert(name)
                notificationRetry.succeeded(key)
            } else {
                notificationRetry.failed(
                    key, now: now, unsupported: status == .notificationUnsupported || status == .notImplemented)
                if status == .cannotComplete || status == .apiDisabled {
                    observerRetry.failed(processKey, now: now)
                    return
                }
            }
        }
    }

    func shutdown() {
        for observer in observers.values {
            CFRunLoopRemoveSource(CFRunLoopGetMain(), AXObserverGetRunLoopSource(observer), .commonModes)
        }
        observers.removeAll()
        applicationNotifications.removeAll()
        windowNotifications.removeAll()
        subscriptionWarnings.removeAll()
        discoveryWarnings.removeAll()
        resetAccessibilityRetries()
        entries.removeAll()
        dragCandidates.removeAll()
    }

    // MARK: - AX attribute access and validation

    private func incompatibility(_ element: AXUIElement) -> String? {
        // Query only attributes advertised by the application through the public AX API.
        var rawNames: CFArray?
        AXUIElementCopyAttributeNames(element, &rawNames)
        if let names = rawNames as? [String], names.contains("AXFullScreen"),
            (value(element, "AXFullScreen" as CFString) as? Bool) == true
        {
            return L10n.tr("Leave native full screen before assigning this window.")
        }
        let minimized = value(element, kAXMinimizedAttribute as CFString) as? Bool ?? false
        let attributes =
            minimized
            ? [(kAXMinimizedAttribute, L10n.tr("minimize/restore"))]
            : [
                (kAXPositionAttribute, L10n.tr("move")), (kAXSizeAttribute, L10n.tr("resize")),
                (kAXMinimizedAttribute, L10n.tr("minimize/restore")),
            ]
        for (attribute, description) in attributes {
            var settable: DarwinBoolean = false
            let error = AXUIElementIsAttributeSettable(element, attribute as CFString, &settable)
            if error != .success || !settable.boolValue {
                return L10n.tr("This app cannot \(description) the window through Accessibility.")
            }
        }
        return nil
    }

    private func value(_ element: AXUIElement, _ name: CFString) -> CFTypeRef? {
        var result: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, name, &result) == .success else { return nil }
        return result
    }

    private func string(_ element: AXUIElement, _ name: String) -> String? {
        value(element, name as CFString) as? String
    }

    private func checkedValue(_ element: AXUIElement, _ attribute: String) throws -> CFTypeRef {
        var raw: CFTypeRef?
        let status = AXUIElementCopyAttributeValue(element, attribute as CFString, &raw)
        guard status == .success else { throw accessError(status, attribute: attribute, operation: L10n.tr("read")) }
        guard let raw else {
            throw WindowAccessError(
                .noValue, attribute: attribute, detail: L10n.tr("The app has not returned a value yet."))
        }
        return raw
    }

    private func readFrame(_ element: AXUIElement) throws -> CGRect {
        let position = try checkedValue(element, kAXPositionAttribute)
        let size = try checkedValue(element, kAXSizeAttribute)
        guard CFGetTypeID(position) == AXValueGetTypeID(), CFGetTypeID(size) == AXValueGetTypeID() else {
            throw WindowAccessError(
                .invalidValue, attribute: "AXPosition/AXSize",
                detail: L10n.tr("The app returned an unsupported frame type."))
        }
        let pointValue = position as! AXValue
        let sizeValue = size as! AXValue
        var point = CGPoint.zero
        var dimensions = CGSize.zero
        guard AXValueGetType(pointValue) == .cgPoint, AXValueGetType(sizeValue) == .cgSize,
            AXValueGetValue(pointValue, .cgPoint, &point), AXValueGetValue(sizeValue, .cgSize, &dimensions),
            [point.x, point.y, dimensions.width, dimensions.height].allSatisfy(\.isFinite),
            dimensions.width > 0, dimensions.height > 0
        else {
            throw WindowAccessError(
                .invalidValue, attribute: "AXPosition/AXSize", detail: L10n.tr("The app returned an invalid frame."))
        }
        return CGRect(origin: point, size: dimensions)
    }

    private func readMinimized(_ element: AXUIElement) throws -> Bool {
        guard let result = try checkedValue(element, kAXMinimizedAttribute) as? Bool else {
            throw WindowAccessError(
                .invalidValue, attribute: kAXMinimizedAttribute,
                detail: L10n.tr("The app returned an invalid minimized state."))
        }
        return result
    }

    private func readState(_ element: AXUIElement) throws -> OriginalWindowState {
        try OriginalWindowState(frame: readFrame(element), minimized: readMinimized(element))
    }

    private func accessError(_ error: AXError, attribute: String, operation: String) -> WindowAccessError {
        let kind: WindowAccessError.Kind =
            switch error {
            case .cannotComplete: .transient
            case .noValue: .noValue
            case .invalidUIElement: .invalidWindow
            case .apiDisabled: AXIsProcessTrusted() ? .transient : .permission
            case .attributeUnsupported, .notImplemented, .actionUnsupported: .unsupported
            case .illegalArgument: .invalidValue
            default: .other
            }
        return WindowAccessError(
            kind, attribute: attribute, code: error.rawValue,
            detail: L10n.tr("Could not \(operation). \(describe(error))"))
    }

    private func describe(_ error: AXError) -> String {
        switch error {
        case .cannotComplete: L10n.tr("The app did not respond to Accessibility in time.")
        case .invalidUIElement: L10n.tr("The window no longer exists.")
        case .attributeUnsupported, .notImplemented: L10n.tr("This Accessibility operation is not supported.")
        case .apiDisabled: L10n.tr("Accessibility is temporarily unavailable for this app.")
        default: L10n.tr("Accessibility error (\(error.rawValue)).")
        }
    }
}
