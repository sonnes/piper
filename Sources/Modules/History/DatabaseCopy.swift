import CSQLite
import Foundation
import PiperCore

/// Reads a database of another app through a private copy, because the app can
/// lock the file. The original never changes, and the copy never outlives the read.
enum DatabaseCopy {

    static func rows(of database: URL, sql: String, since: Date, limit: Int? = nil) throws -> [[String?]] {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent("piper-history-" + UUID().uuidString)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
        defer { try? FileManager.default.removeItem(at: folder) }
        let copy = folder.appendingPathComponent("copy.sqlite")
        try FileManager.default.copyItem(at: database, to: copy)
        let log = URL(fileURLWithPath: database.path + "-wal")
        if FileManager.default.fileExists(atPath: log.path) {
            try FileManager.default.copyItem(at: log, to: URL(fileURLWithPath: copy.path + "-wal"))
        }

        var handle: OpaquePointer?
        defer { sqlite3_close(handle) }
        guard sqlite3_open_v2(copy.path, &handle, SQLITE_OPEN_READWRITE, nil) == SQLITE_OK else {
            throw PiperError("Cannot open a copy of \(database.lastPathComponent).")
        }
        var statement: OpaquePointer?
        defer { sqlite3_finalize(statement) }
        guard sqlite3_prepare_v2(handle, sql, -1, &statement, nil) == SQLITE_OK else {
            throw PiperError("Cannot read \(database.lastPathComponent): \(String(cString: sqlite3_errmsg(handle)))")
        }
        sqlite3_bind_double(statement, sqlite3_bind_parameter_index(statement, ":since"), since.timeIntervalSince1970)
        if let limit { sqlite3_bind_int(statement, sqlite3_bind_parameter_index(statement, ":limit"), Int32(limit)) }

        var rows: [[String?]] = []
        while sqlite3_step(statement) == SQLITE_ROW {
            rows.append((0..<sqlite3_column_count(statement)).map { column in
                sqlite3_column_text(statement, column).map { String(cString: $0) }
            })
        }
        return rows
    }
}
