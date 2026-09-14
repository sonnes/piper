import Foundation

/// An error with a message that is safe to show to a reader.
public struct PiperError: LocalizedError {
    public let message: String
    public var errorDescription: String? { message }
    public init(_ message: String) { self.message = message }
}
