import CSQLite
import Foundation

/// A single-row store for the capture state.
///
/// The database keeps one versioned blob. It does not read the blob, so the
/// caller chooses the encoding. Every save compares the stored blob against the
/// blob that the last load or save returned. A different blob means another
/// Piper instance wrote first, and the save fails instead of overwriting.
public final class Database {

    // MARK: - Properties

    private var handle: OpaquePointer?
    private var savedData: Data?

    // MARK: - Initialization

    public init(url: URL) throws {
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        guard sqlite3_open(url.path, &handle) == SQLITE_OK else {
            if let handle { sqlite3_close(handle) }
            handle = nil
            throw DatabaseError("Cannot open the note database.")
        }
        sqlite3_busy_timeout(handle, 3000)
        try execute("CREATE TABLE IF NOT EXISTS state (id INTEGER PRIMARY KEY CHECK(id=1), version INTEGER NOT NULL, data BLOB NOT NULL)")
    }

    deinit { sqlite3_close(handle) }

    // MARK: - Reading And Writing

    /// Returns the stored blob, or nil when the database holds no record yet.
    public func load() throws -> Data? {
        var statement: OpaquePointer?
        guard sqlite3_prepare_v2(handle, "SELECT version, data FROM state WHERE id=1", -1, &statement, nil) == SQLITE_OK else { throw failure() }
        defer { sqlite3_finalize(statement) }
        let result = sqlite3_step(statement)
        if result == SQLITE_DONE { savedData = nil; return nil }
        guard result == SQLITE_ROW else { throw failure() }
        guard sqlite3_column_int(statement, 0) == 1 else { throw DatabaseError("This database needs a newer version of Piper. Notes remain unchanged.") }
        guard let bytes = sqlite3_column_blob(statement, 1) else { throw DatabaseError("The note database has no readable data.") }
        let data = Data(bytes: bytes, count: Int(sqlite3_column_bytes(statement, 1)))
        savedData = data
        return data
    }

    public func save(_ data: Data) throws {
        var statement: OpaquePointer?
        let sql = savedData == nil
            ? "INSERT INTO state VALUES(1,1,?) ON CONFLICT(id) DO NOTHING"
            : "UPDATE state SET data=? WHERE id=1 AND version=1 AND data=?"
        guard sqlite3_prepare_v2(handle, sql, -1, &statement, nil) == SQLITE_OK else { throw failure() }
        defer { sqlite3_finalize(statement) }
        let result = data.withUnsafeBytes { bytes in
            sqlite3_bind_blob(statement, 1, bytes.baseAddress, Int32(bytes.count), unsafeBitCast(-1, to: sqlite3_destructor_type.self))
        }
        if let savedData {
            let bound = savedData.withUnsafeBytes { bytes in
                sqlite3_bind_blob(statement, 2, bytes.baseAddress, Int32(bytes.count), unsafeBitCast(-1, to: sqlite3_destructor_type.self))
            }
            guard bound == SQLITE_OK else { throw failure() }
        }
        guard result == SQLITE_OK, sqlite3_step(statement) == SQLITE_DONE else { throw failure() }
        guard sqlite3_changes(handle) == 1 else { throw DatabaseError("Notes changed in another Piper instance. Restart Piper before saving. Your existing notes remain unchanged.") }
        savedData = data
    }
}

// MARK: - Private

private extension Database {

    func execute(_ sql: String) throws {
        guard sqlite3_exec(handle, sql, nil, nil, nil) == SQLITE_OK else { throw failure() }
    }

    func failure() -> DatabaseError { DatabaseError("Cannot save or read notes: \(String(cString: sqlite3_errmsg(handle)))") }
}
