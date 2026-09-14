import Foundation

// This module links CSQLite only, so it cannot use PiperError from PiperCore.
// DatabaseError carries the same shape: one reader-safe message that
// localizedDescription returns. Callers in Captures report it unchanged.
public struct DatabaseError: LocalizedError {
    public let message: String
    public var errorDescription: String? { message }

    public init(_ message: String) { self.message = message }
}
