import Foundation

public struct ConfigurationError: LocalizedError {
    public let errorDescription: String?
    public init(_ message: String) { errorDescription = message }
}
