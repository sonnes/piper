import CSQLite
import Foundation

/// The subscriptions, their articles, and the Discover suggestions, in one
/// SQLite file. Each call runs on the thread of the caller. `FeedStore` calls
/// it on the main thread.
public final class FeedDatabase {

    // MARK: - Properties

    public static let summaryLimit = 500

    private var handle: OpaquePointer?

    // MARK: - Initialization

    public init(url: URL) throws {
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        guard sqlite3_open(url.path, &handle) == SQLITE_OK else {
            if let handle { sqlite3_close(handle) }
            handle = nil
            throw FeedError("Cannot open the feed database.")
        }
        sqlite3_busy_timeout(handle, 3000)
        try execute("PRAGMA foreign_keys = ON")
        try execute("""
        CREATE TABLE IF NOT EXISTS feeds (
          id TEXT PRIMARY KEY, title TEXT NOT NULL, home TEXT, etag TEXT, last_modified TEXT,
          failures INTEGER NOT NULL DEFAULT 0, next_fetch REAL NOT NULL, error TEXT)
        """)
        try execute("""
        CREATE TABLE IF NOT EXISTS articles (
          id TEXT PRIMARY KEY, feed_id TEXT NOT NULL REFERENCES feeds(id) ON DELETE CASCADE,
          url TEXT NOT NULL, title TEXT NOT NULL, summary TEXT NOT NULL, published REAL, arrived REAL NOT NULL,
          read INTEGER NOT NULL DEFAULT 0, starred INTEGER NOT NULL DEFAULT 0)
        """)
        try execute("CREATE INDEX IF NOT EXISTS articles_feed ON articles(feed_id, read)")
        try execute("""
        CREATE TABLE IF NOT EXISTS suggestions (
          host TEXT PRIMARY KEY, feed_url TEXT, title TEXT, visits INTEGER NOT NULL, score REAL NOT NULL,
          ignored INTEGER NOT NULL DEFAULT 0)
        """)
    }

    deinit { sqlite3_close(handle) }

    // MARK: - Feeds

    public func feeds() throws -> [Feed] {
        let statement = try prepare("SELECT id, title, home, etag, last_modified, failures, next_fetch, error FROM feeds ORDER BY title COLLATE NOCASE")
        defer { sqlite3_finalize(statement) }
        var feeds: [Feed] = []
        while sqlite3_step(statement) == SQLITE_ROW {
            feeds.append(Feed(id: text(statement, 0), title: text(statement, 1), home: optionalText(statement, 2),
                              etag: optionalText(statement, 3), lastModified: optionalText(statement, 4),
                              failures: Int(sqlite3_column_int(statement, 5)),
                              nextFetch: Date(timeIntervalSince1970: sqlite3_column_double(statement, 6)),
                              error: optionalText(statement, 7)))
        }
        return feeds
    }

    /// Adds the feed, or replaces the stored fields of a feed with the same URL.
    public func save(_ feed: Feed) throws {
        let statement = try prepare("""
        INSERT INTO feeds (id, title, home, etag, last_modified, failures, next_fetch, error) VALUES (?, ?, ?, ?, ?, ?, ?, ?)
        ON CONFLICT(id) DO UPDATE SET title = excluded.title, home = excluded.home, etag = excluded.etag,
          last_modified = excluded.last_modified, failures = excluded.failures, next_fetch = excluded.next_fetch,
          error = excluded.error
        """)
        defer { sqlite3_finalize(statement) }
        bind(feed.id, at: 1, in: statement)
        bind(feed.title, at: 2, in: statement)
        bind(feed.home, at: 3, in: statement)
        bind(feed.etag, at: 4, in: statement)
        bind(feed.lastModified, at: 5, in: statement)
        sqlite3_bind_int(statement, 6, Int32(feed.failures))
        sqlite3_bind_double(statement, 7, feed.nextFetch.timeIntervalSince1970)
        bind(feed.error, at: 8, in: statement)
        try step(statement)
    }

    /// Removes the feed and each of its articles.
    public func delete(feed id: String) throws {
        try run("DELETE FROM feeds WHERE id = ?", id)
    }

    // MARK: - Articles

    /// Adds each article that the database does not hold. The read and
    /// starred marks of a known article stay. Returns the count of new articles.
    @discardableResult
    public func insert(_ articles: [Article]) throws -> Int {
        try execute("BEGIN")
        do {
            let statement = try prepare("""
            INSERT OR IGNORE INTO articles (id, feed_id, url, title, summary, published, arrived, read, starred)
            VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?)
            """)
            defer { sqlite3_finalize(statement) }
            var added = 0
            for article in articles {
                sqlite3_reset(statement)
                bind(article.id, at: 1, in: statement)
                bind(article.feedID, at: 2, in: statement)
                bind(article.url, at: 3, in: statement)
                bind(article.title, at: 4, in: statement)
                bind(String(article.summary.prefix(Self.summaryLimit)), at: 5, in: statement)
                if let published = article.published {
                    sqlite3_bind_double(statement, 6, published.timeIntervalSince1970)
                } else {
                    sqlite3_bind_null(statement, 6)
                }
                sqlite3_bind_double(statement, 7, article.arrived.timeIntervalSince1970)
                sqlite3_bind_int(statement, 8, article.read ? 1 : 0)
                sqlite3_bind_int(statement, 9, article.starred ? 1 : 0)
                try step(statement)
                added += Int(sqlite3_changes(handle))
            }
            try execute("COMMIT")
            return added
        } catch {
            try? execute("ROLLBACK")
            throw error
        }
    }

    /// The articles of a row of the sidebar, the newest first.
    public func articles(_ filter: FeedFilter, limit: Int = 500) throws -> [Article] {
        let condition: String
        var argument: String?
        switch filter {
        case .discover: return []
        case .allUnread: condition = "read = 0"
        case .starred: condition = "starred = 1"
        case .feed(let id):
            condition = "feed_id = ?"
            argument = id
        }
        let statement = try prepare("""
        SELECT id, feed_id, url, title, summary, published, arrived, read, starred FROM articles
        WHERE \(condition) ORDER BY COALESCE(published, arrived) DESC LIMIT \(limit)
        """)
        defer { sqlite3_finalize(statement) }
        if let argument { bind(argument, at: 1, in: statement) }
        var articles: [Article] = []
        while sqlite3_step(statement) == SQLITE_ROW {
            articles.append(Article(id: text(statement, 0), feedID: text(statement, 1), url: text(statement, 2),
                                    title: text(statement, 3), summary: text(statement, 4),
                                    published: sqlite3_column_type(statement, 5) == SQLITE_NULL
                                        ? nil : Date(timeIntervalSince1970: sqlite3_column_double(statement, 5)),
                                    arrived: Date(timeIntervalSince1970: sqlite3_column_double(statement, 6)),
                                    read: sqlite3_column_int(statement, 7) == 1,
                                    starred: sqlite3_column_int(statement, 8) == 1))
        }
        return articles
    }

    /// The count of unread articles of each feed, by feed ID.
    public func unreadCounts() throws -> [String: Int] {
        let statement = try prepare("SELECT feed_id, COUNT(*) FROM articles WHERE read = 0 GROUP BY feed_id")
        defer { sqlite3_finalize(statement) }
        var counts: [String: Int] = [:]
        while sqlite3_step(statement) == SQLITE_ROW {
            counts[text(statement, 0)] = Int(sqlite3_column_int(statement, 1))
        }
        return counts
    }

    public func starredCount() throws -> Int {
        let statement = try prepare("SELECT COUNT(*) FROM articles WHERE starred = 1")
        defer { sqlite3_finalize(statement) }
        return sqlite3_step(statement) == SQLITE_ROW ? Int(sqlite3_column_int(statement, 0)) : 0
    }

    public func setRead(_ read: Bool, ids: [String]) throws {
        try execute("BEGIN")
        do {
            for id in ids { try run("UPDATE articles SET read = \(read ? 1 : 0) WHERE id = ?", id) }
            try execute("COMMIT")
        } catch {
            try? execute("ROLLBACK")
            throw error
        }
    }

    public func setStarred(_ starred: Bool, id: String) throws {
        try run("UPDATE articles SET starred = \(starred ? 1 : 0) WHERE id = ?", id)
    }

    /// Removes the read articles that arrived before the date. Starred articles stay.
    public func prune(before date: Date) throws {
        let statement = try prepare("DELETE FROM articles WHERE read = 1 AND starred = 0 AND arrived < ?")
        defer { sqlite3_finalize(statement) }
        sqlite3_bind_double(statement, 1, date.timeIntervalSince1970)
        try step(statement)
    }

    // MARK: - Suggestions

    public func suggestions() throws -> [Suggestion] {
        let statement = try prepare("SELECT host, feed_url, title, visits, score, ignored FROM suggestions ORDER BY score DESC")
        defer { sqlite3_finalize(statement) }
        var suggestions: [Suggestion] = []
        while sqlite3_step(statement) == SQLITE_ROW {
            suggestions.append(Suggestion(host: text(statement, 0), feedURL: optionalText(statement, 1),
                                          title: optionalText(statement, 2), visits: Int(sqlite3_column_int(statement, 3)),
                                          score: sqlite3_column_double(statement, 4), ignored: sqlite3_column_int(statement, 5) == 1))
        }
        return suggestions
    }

    /// Replaces the suggestions that are not ignored. An ignored host stays ignored.
    public func replaceSuggestions(_ suggestions: [Suggestion]) throws {
        try execute("BEGIN")
        do {
            try execute("DELETE FROM suggestions WHERE ignored = 0")
            let statement = try prepare("""
            INSERT OR IGNORE INTO suggestions (host, feed_url, title, visits, score, ignored) VALUES (?, ?, ?, ?, ?, 0)
            """)
            defer { sqlite3_finalize(statement) }
            for suggestion in suggestions {
                sqlite3_reset(statement)
                bind(suggestion.host, at: 1, in: statement)
                bind(suggestion.feedURL, at: 2, in: statement)
                bind(suggestion.title, at: 3, in: statement)
                sqlite3_bind_int(statement, 4, Int32(suggestion.visits))
                sqlite3_bind_double(statement, 5, suggestion.score)
                try step(statement)
            }
            try execute("COMMIT")
        } catch {
            try? execute("ROLLBACK")
            throw error
        }
    }

    public func ignore(host: String) throws {
        try run("UPDATE suggestions SET ignored = 1 WHERE host = ?", host)
    }
}

// MARK: - SQLite

private extension FeedDatabase {

    func prepare(_ sql: String) throws -> OpaquePointer? {
        var statement: OpaquePointer?
        guard sqlite3_prepare_v2(handle, sql, -1, &statement, nil) == SQLITE_OK else { throw failure() }
        return statement
    }

    func step(_ statement: OpaquePointer?) throws {
        guard sqlite3_step(statement) == SQLITE_DONE else { throw failure() }
    }

    func run(_ sql: String, _ argument: String) throws {
        let statement = try prepare(sql)
        defer { sqlite3_finalize(statement) }
        bind(argument, at: 1, in: statement)
        try step(statement)
    }

    func text(_ statement: OpaquePointer?, _ column: Int32) -> String {
        optionalText(statement, column) ?? ""
    }

    func optionalText(_ statement: OpaquePointer?, _ column: Int32) -> String? {
        sqlite3_column_text(statement, column).map { String(cString: $0) }
    }

    func bind(_ text: String?, at index: Int32, in statement: OpaquePointer?) {
        guard let text else {
            sqlite3_bind_null(statement, index)
            return
        }
        sqlite3_bind_text(statement, index, text, Int32(text.utf8.count), unsafeBitCast(-1, to: sqlite3_destructor_type.self))
    }

    func execute(_ sql: String) throws {
        guard sqlite3_exec(handle, sql, nil, nil, nil) == SQLITE_OK else { throw failure() }
    }

    func failure() -> FeedError { FeedError("Cannot save or read feeds: \(String(cString: sqlite3_errmsg(handle)))") }
}

/// An error with a message that Piper can show.
public struct FeedError: LocalizedError, Equatable {
    public let message: String
    public init(_ message: String) { self.message = message }
    public var errorDescription: String? { message }
}
