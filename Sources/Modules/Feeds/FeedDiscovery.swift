import Foundation

/// Finds the feeds of a site, or reads a feed address as it is.
public enum FeedDiscovery {

    /// One feed that a page offers.
    public struct Found: Equatable, Hashable, Identifiable, Sendable {
        public let url: String
        public let title: String?
        /// "RSS", "Atom", or "JSON Feed", if Piper read the feed.
        public let format: String?
        /// The count of articles, if Piper read the feed.
        public let articles: Int?

        public var id: String { url }
    }

    /// The most feeds that `find` reads to confirm them.
    static let confirmLimit = 3

    /// Gets the address. If it is a feed, returns it. If it is a page, returns the
    /// feeds that the page names, the best first, and confirms the best few.
    public static func find(_ address: String, session: URLSession = .shared) async throws -> [Found] {
        guard let url = URL(string: address.normalizedURL) else { throw FeedError("The address is not valid.") }
        let data = try await get(url, session: session)
        let parserData = ParserData(url: url.absoluteString, data: data)
        if FeedParser.canParse(parserData) {
            guard let parsed = try await FeedParser.parse(parserData) else { throw FeedError("Piper cannot read this feed.") }
            return [found(url.absoluteString, parsed)]
        }
        let candidates = HTMLFeedFinder(parserData: parserData).feedSpecifiers.sorted { $0.score > $1.score }
        var results: [Found] = []
        for candidate in candidates.prefix(confirmLimit) {
            guard let feedURL = URL(string: candidate.urlString),
                  let feedData = try? await get(feedURL, session: session),
                  let parsed = try? await FeedParser.parse(ParserData(url: candidate.urlString, data: feedData)) else { continue }
            results.append(found(candidate.urlString, parsed, title: candidate.title))
        }
        return results
    }

    // MARK: - Parts

    private static func get(_ url: URL, session: URLSession) async throws -> Data {
        let (data, response) = try await session.data(for: URLRequest(url: url, timeoutInterval: FeedFetch.timeout))
        if let status = (response as? HTTPURLResponse)?.statusCode, !(200..<300).contains(status) {
            throw FeedError("The server answered \(status).")
        }
        return data
    }

    private static func found(_ url: String, _ parsed: ParsedFeed, title: String? = nil) -> Found {
        Found(url: url, title: parsed.title?.nilIfEmptyOrWhitespace ?? title, format: format(parsed.type),
              articles: parsed.items.count)
    }

    static func format(_ type: FeedType) -> String? {
        switch type {
        case .rss: return "RSS"
        case .atom: return "Atom"
        case .jsonFeed, .rssInJSON: return "JSON Feed"
        default: return nil
        }
    }
}
