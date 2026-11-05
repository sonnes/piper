import Foundation

/// One unread or starred article of a NetNewsWire feed.
public struct FeedArticle: Equatable, Sendable {
    public let feed: String
    public let title: String
    public let url: String
    public let summary: String
    public let starred: Bool
    public let publishedAt: Date?

    public init(feed: String, title: String, url: String, summary: String, starred: Bool, publishedAt: Date?) {
        self.feed = feed
        self.title = title
        self.url = url
        self.summary = summary
        self.starred = starred
        self.publishedAt = publishedAt
    }
}

/// Reads recent articles from a NetNewsWire account. It reads a copy, so read
/// marks do not change.
public enum NetNewsWireReader {

    public static let articleLimit = 40
    static let summaryLimit = 500

    /// NetNewsWire stores each date as seconds from 1970.
    private static let sql = """
    SELECT a.feedID, a.title, COALESCE(NULLIF(a.url, ''), a.externalURL),
           COALESCE(NULLIF(a.summary, ''), a.contentText, ''), s.starred, a.datePublished
    FROM articles a JOIN statuses s ON a.articleID = s.articleID
    WHERE (s.read = 0 OR s.starred = 1) AND s.dateArrived >= :since
    ORDER BY s.starred DESC, a.datePublished DESC
    LIMIT :limit
    """

    public static func read(_ source: BriefSource, since: Date, blocked: [String]) throws -> [FeedArticle] {
        guard let database = source.database, source.format == .netNewsWire else { return [] }
        let names = feedNames(in: database.deletingLastPathComponent().appendingPathComponent("Subscriptions.opml"))
        return try DatabaseCopy.rows(of: database, sql: sql, since: since, limit: articleLimit).compactMap { row in
            guard let url = row[2], let title = row[1], BlockedSites.allows(url, list: blocked) else { return nil }
            let feedID = row[0] ?? ""
            return FeedArticle(feed: names[feedID] ?? URL(string: url)?.host ?? feedID, title: title, url: url,
                               summary: String((row[3] ?? "").prefix(summaryLimit)), starred: row[4] == "1",
                               publishedAt: row[5].flatMap(Double.init).map(Date.init(timeIntervalSince1970:)))
        }
    }

    /// The name of each feed, by its feed URL.
    static func feedNames(in opml: URL) -> [String: String] {
        guard let parser = XMLParser(contentsOf: opml) else { return [:] }
        let reader = OutlineReader()
        parser.delegate = reader
        parser.parse()
        return reader.names
    }
}

private final class OutlineReader: NSObject, XMLParserDelegate {
    var names: [String: String] = [:]

    func parser(_ parser: XMLParser, didStartElement elementName: String, namespaceURI: String?,
                qualifiedName qName: String?, attributes: [String: String] = [:]) {
        guard elementName == "outline", let url = attributes["xmlUrl"],
              let name = attributes["title"] ?? attributes["text"] else { return }
        names[url] = name
    }
}
