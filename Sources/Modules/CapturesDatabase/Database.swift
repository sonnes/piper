import CSQLite
import Foundation

/// A single-row store for the capture state, and a table of clipboard texts.
///
/// The database keeps one versioned blob for the notes. It does not read the blob, so the
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
    ///
    /// A load of a supported version also adds the clipboard table. A database
    /// from a newer version of Piper stays unchanged.
    public func load() throws -> Data? {
        var statement: OpaquePointer?
        guard sqlite3_prepare_v2(handle, "SELECT version, data FROM state WHERE id=1", -1, &statement, nil) == SQLITE_OK else { throw failure() }
        defer { sqlite3_finalize(statement) }
        let result = sqlite3_step(statement)
        if result == SQLITE_DONE { savedData = nil; try createClipboardTable(); return nil }
        guard result == SQLITE_ROW else { throw failure() }
        guard sqlite3_column_int(statement, 0) == 1 else { throw DatabaseError("This database needs a newer version of Piper. Notes remain unchanged.") }
        try createClipboardTable()
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

// MARK: - Clipboard

/// One clipboard text as the database stores it.
public struct ClipboardRecord: Equatable {
    public let id: UUID
    public let text: String
    public let copiedAt: Date
    public let source: String?

    public init(id: UUID, text: String, copiedAt: Date, source: String?) {
        self.id = id
        self.text = text
        self.copiedAt = copiedAt
        self.source = source
    }
}

public extension Database {

    /// Returns the clipboard texts, newest first.
    func loadClipboard() throws -> [ClipboardRecord] {
        let statement = try prepare("SELECT id, text, copied_at, source FROM clipboard ORDER BY copied_at DESC")
        defer { sqlite3_finalize(statement) }
        var records: [ClipboardRecord] = []
        while true {
            let result = sqlite3_step(statement)
            if result == SQLITE_DONE { return records }
            guard result == SQLITE_ROW else { throw failure() }
            // A row with an unreadable id is skipped. The next trim or clear removes it.
            guard let id = UUID(uuidString: text(statement, 0)) else { continue }
            records.append(ClipboardRecord(
                id: id,
                text: text(statement, 1),
                copiedAt: Date(timeIntervalSince1970: sqlite3_column_double(statement, 2)),
                source: sqlite3_column_type(statement, 3) == SQLITE_NULL ? nil : text(statement, 3)
            ))
        }
    }

    /// Writes the changed records and removes the ids that left the history, in one transaction.
    func saveClipboard(_ records: [ClipboardRecord], removing removed: [UUID]) throws {
        guard !records.isEmpty || !removed.isEmpty else { return }
        try execute("BEGIN IMMEDIATE")
        do {
            for record in records {
                let statement = try prepare("INSERT OR REPLACE INTO clipboard VALUES(?,?,?,?)")
                defer { sqlite3_finalize(statement) }
                bind(record.id.uuidString, at: 1, in: statement)
                bind(record.text, at: 2, in: statement)
                sqlite3_bind_double(statement, 3, record.copiedAt.timeIntervalSince1970)
                if let source = record.source { bind(source, at: 4, in: statement) } else { sqlite3_bind_null(statement, 4) }
                guard sqlite3_step(statement) == SQLITE_DONE else { throw failure() }
            }
            for id in removed {
                let statement = try prepare("DELETE FROM clipboard WHERE id=?")
                defer { sqlite3_finalize(statement) }
                bind(id.uuidString, at: 1, in: statement)
                guard sqlite3_step(statement) == SQLITE_DONE else { throw failure() }
            }
            try execute("COMMIT")
        } catch {
            try? execute("ROLLBACK")
            throw error
        }
    }

    /// Removes the clipboard texts copied before the date.
    func removeClipboard(before date: Date) throws {
        let statement = try prepare("DELETE FROM clipboard WHERE copied_at < ?")
        defer { sqlite3_finalize(statement) }
        sqlite3_bind_double(statement, 1, date.timeIntervalSince1970)
        guard sqlite3_step(statement) == SQLITE_DONE else { throw failure() }
    }

    func removeAllClipboard() throws {
        try execute("DELETE FROM clipboard")
    }
}

// MARK: - Sessions

public extension Database {

    /// Returns the stored Claude sessions, the most recently changed first.
    /// Each session is a blob that the caller encodes.
    func loadSessions() throws -> [Data] {
        try createSessionsTable()
        let statement = try prepare("SELECT data FROM sessions ORDER BY updated_at DESC")
        defer { sqlite3_finalize(statement) }
        var sessions: [Data] = []
        while true {
            let result = sqlite3_step(statement)
            if result == SQLITE_DONE { return sessions }
            guard result == SQLITE_ROW else { throw failure() }
            guard let bytes = sqlite3_column_blob(statement, 0) else { continue }
            sessions.append(Data(bytes: bytes, count: Int(sqlite3_column_bytes(statement, 0))))
        }
    }

    /// Writes one session, replacing the stored session with the same id.
    func saveSession(id: UUID, folder: String, updatedAt: Date, data: Data) throws {
        try createSessionsTable()
        let statement = try prepare("INSERT OR REPLACE INTO sessions VALUES(?,?,?,?)")
        defer { sqlite3_finalize(statement) }
        bind(id.uuidString, at: 1, in: statement)
        bind(folder, at: 2, in: statement)
        sqlite3_bind_double(statement, 3, updatedAt.timeIntervalSince1970)
        let result = data.withUnsafeBytes { bytes in
            sqlite3_bind_blob(statement, 4, bytes.baseAddress, Int32(bytes.count), unsafeBitCast(-1, to: sqlite3_destructor_type.self))
        }
        guard result == SQLITE_OK, sqlite3_step(statement) == SQLITE_DONE else { throw failure() }
    }

    func deleteSession(id: UUID) throws {
        try createSessionsTable()
        let statement = try prepare("DELETE FROM sessions WHERE id=?")
        defer { sqlite3_finalize(statement) }
        bind(id.uuidString, at: 1, in: statement)
        guard sqlite3_step(statement) == SQLITE_DONE else { throw failure() }
    }

    /// Removes every session except the `count` most recently changed.
    func keepNewestSessions(_ count: Int) throws {
        try createSessionsTable()
        let statement = try prepare("DELETE FROM sessions WHERE id NOT IN (SELECT id FROM sessions ORDER BY updated_at DESC LIMIT ?)")
        defer { sqlite3_finalize(statement) }
        sqlite3_bind_int(statement, 1, Int32(count))
        guard sqlite3_step(statement) == SQLITE_DONE else { throw failure() }
    }
}

// MARK: - Private

private extension Database {

    func createSessionsTable() throws {
        try execute("CREATE TABLE IF NOT EXISTS sessions (id TEXT PRIMARY KEY, folder TEXT NOT NULL, updated_at REAL NOT NULL, data BLOB NOT NULL)")
    }

    func createClipboardTable() throws {
        try execute("CREATE TABLE IF NOT EXISTS clipboard (id TEXT PRIMARY KEY, text TEXT NOT NULL, copied_at REAL NOT NULL, source TEXT)")
    }

    func prepare(_ sql: String) throws -> OpaquePointer? {
        var statement: OpaquePointer?
        guard sqlite3_prepare_v2(handle, sql, -1, &statement, nil) == SQLITE_OK else { throw failure() }
        return statement
    }

    func text(_ statement: OpaquePointer?, _ column: Int32) -> String {
        guard let bytes = sqlite3_column_blob(statement, column) else { return "" }
        return String(decoding: Data(bytes: bytes, count: Int(sqlite3_column_bytes(statement, column))), as: UTF8.self)
    }

    func bind(_ text: String, at index: Int32, in statement: OpaquePointer?) {
        sqlite3_bind_text(statement, index, text, Int32(text.utf8.count), unsafeBitCast(-1, to: sqlite3_destructor_type.self))
    }

    func execute(_ sql: String) throws {
        guard sqlite3_exec(handle, sql, nil, nil, nil) == SQLITE_OK else { throw failure() }
    }

    func failure() -> DatabaseError { DatabaseError("Cannot save or read notes: \(String(cString: sqlite3_errmsg(handle)))") }
}
