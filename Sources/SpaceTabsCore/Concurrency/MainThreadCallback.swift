import Foundation

/// Bridge synchronous Objective-C callbacks that may arrive on any thread to
/// AppKit's main executor. Never synchronously redispatch an existing main call.
public enum MainThreadCallback {
    public static func call<Result: Sendable>(_ body: @MainActor @Sendable () -> Result) -> Result {
        if Thread.isMainThread { return MainActor.assumeIsolated { body() } }
        return DispatchQueue.main.sync { MainActor.assumeIsolated { body() } }
    }
}
