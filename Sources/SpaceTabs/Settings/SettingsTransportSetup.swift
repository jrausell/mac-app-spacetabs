import Foundation

/// Signature inspection and socket connection must not delay AppKit rendering.
enum SettingsTransportSetup {
    private static let queue = DispatchQueue(label: "SpaceTabs.settings.setup", qos: .userInitiated)

    static func perform<Value: Sendable>(_ work: @escaping @Sendable () throws -> Value) async throws -> Value {
        try Task.checkCancellation()
        return try await withCheckedThrowingContinuation { continuation in
            queue.async {
                do { continuation.resume(returning: try work()) } catch { continuation.resume(throwing: error) }
            }
        }
    }
}
