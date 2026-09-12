import Foundation
import CSQLite

struct PiperError: LocalizedError {
    let message: String
    var errorDescription: String? { message }
    init(_ message: String) { self.message = message }
}

final class Database {
    private var handle: OpaquePointer?
    private var savedData: Data?

    init(url: URL) throws {
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        guard sqlite3_open(url.path, &handle) == SQLITE_OK else {
            if let handle { sqlite3_close(handle) }
            handle = nil
            throw PiperError("Cannot open the note database.")
        }
        sqlite3_busy_timeout(handle, 3000)
        try execute("CREATE TABLE IF NOT EXISTS state (id INTEGER PRIMARY KEY CHECK(id=1), version INTEGER NOT NULL, data BLOB NOT NULL)")
    }

    deinit { sqlite3_close(handle) }

    func load() throws -> SavedState {
        var statement: OpaquePointer?
        guard sqlite3_prepare_v2(handle, "SELECT version, data FROM state WHERE id=1", -1, &statement, nil) == SQLITE_OK else { throw failure() }
        defer { sqlite3_finalize(statement) }
        let result = sqlite3_step(statement)
        if result == SQLITE_DONE { savedData = nil; return SavedState() }
        guard result == SQLITE_ROW else { throw failure() }
        guard sqlite3_column_int(statement, 0) == 1 else { throw PiperError("This database needs a newer version of Piper. Notes remain unchanged.") }
        guard let bytes = sqlite3_column_blob(statement, 1) else { throw PiperError("The note database has no readable data.") }
        let data = Data(bytes: bytes, count: Int(sqlite3_column_bytes(statement, 1)))
        let state = try JSONDecoder().decode(SavedState.self, from: data)
        guard !state.sections.isEmpty, Set(state.sections).count == state.sections.count,
              state.sections.contains(state.activeSection), Set(state.notes.map(\.id)).count == state.notes.count,
              state.notes.allSatisfy({ state.sections.contains($0.section) }) else {
            throw PiperError("The note database contains invalid records. Restore a backup before adding notes.")
        }
        savedData = data
        return state
    }

    func save(_ state: SavedState) throws {
        let data = try JSONEncoder().encode(state)
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
        guard sqlite3_changes(handle) == 1 else { throw PiperError("Notes changed in another Piper instance. Restart Piper before saving. Your existing notes remain unchanged.") }
        savedData = data
    }

    private func execute(_ sql: String) throws {
        guard sqlite3_exec(handle, sql, nil, nil, nil) == SQLITE_OK else { throw failure() }
    }

    private func failure() -> PiperError { PiperError("Cannot save or read notes: \(String(cString: sqlite3_errmsg(handle)))") }
}
