import Foundation

/// One fetch of a feed with a conditional GET, and the parse of the answer.
public enum FeedFetch {

    // MARK: - Properties

    /// The wait before the next fetch, by the count of failures in a row.
    static let waitHours: [Double] = [0.5, 0.5, 2, 8, 24]
    static let timeout: TimeInterval = 30

    public enum Result: Sendable {
        /// The server answered 304. The feed did not change.
        case notModified
        case fetched(ParsedFeed, etag: String?, lastModified: String?)
    }

    // MARK: - Fetching

    /// Gets the feed. Runs away from the main thread.
    public static func get(_ feed: Feed, session: URLSession = .shared) async throws -> Result {
        guard let url = URL(string: feed.id) else { throw FeedError("The feed address is not valid.") }
        var request = URLRequest(url: url, timeoutInterval: timeout)
        if let etag = feed.etag { request.setValue(etag, forHTTPHeaderField: "If-None-Match") }
        if let lastModified = feed.lastModified { request.setValue(lastModified, forHTTPHeaderField: "If-Modified-Since") }
        let (data, response) = try await session.data(for: request)
        let http = response as? HTTPURLResponse
        if http?.statusCode == 304 { return .notModified }
        if let status = http?.statusCode, !(200..<300).contains(status) {
            throw FeedError("The server answered \(status).")
        }
        guard let parsed = try await FeedParser.parse(ParserData(url: feed.id, data: data)) else {
            throw FeedError("The address does not give a feed.")
        }
        return .fetched(parsed, etag: http?.value(forHTTPHeaderField: "ETag"),
                        lastModified: http?.value(forHTTPHeaderField: "Last-Modified"))
    }

    /// The time of the next fetch: 30 minutes, then 2, 8, and 24 hours after each failure in a row.
    public static func nextFetch(after failures: Int, now: Date) -> Date {
        now.addingTimeInterval(waitHours[min(failures, waitHours.count - 1)] * 3600)
    }

    // MARK: - Conversion

    /// The articles of a parsed feed. An item with no link is skipped.
    public static func articles(of parsed: ParsedFeed, feedID: String, now: Date) -> [Article] {
        parsed.items.compactMap { item in
            guard let url = (item.url ?? item.externalURL)?.nilIfEmptyOrWhitespace else { return nil }
            let summary = plainText(item.summary ?? item.contentText ?? item.contentHTML ?? "")
            let title = item.title.map(plainText)?.nilIfEmptyOrWhitespace ?? String(summary.prefix(80))
            return Article(id: (feedID + "\n" + item.uniqueID).md5String, feedID: feedID, url: url, title: title,
                           summary: String(summary.prefix(FeedDatabase.summaryLimit)),
                           published: item.datePublished ?? item.dateModified, arrived: now)
        }
    }

    /// The text of an HTML fragment on one line, with no tags and no entities.
    static func plainText(_ html: String) -> String {
        let noTags = html.replacingOccurrences(of: "<[^>]*>", with: " ", options: .regularExpression)
        return noTags.decodingHTMLEntities()
            .replacingOccurrences(of: "\\s+", with: " ", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
