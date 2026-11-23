import Foundation

/// The store that keeps the sessions of a `SessionRunner`. Each session is a
/// blob that the runner encodes.
public protocol SessionStorage {
    /// Returns the stored sessions, the most recently changed first.
    func loadSessions() throws -> [Data]
    /// Writes one session, replacing the stored session with the same id.
    func saveSession(id: UUID, folder: String, updatedAt: Date, data: Data) throws
    func deleteSession(id: UUID) throws
    /// Removes every session except the `count` most recently changed.
    func keepNewestSessions(_ count: Int) throws
}
