import Foundation

/// One subscription.
public struct Feed: Equatable, Hashable, Identifiable, Sendable {
    /// The feed URL.
    public let id: String
    public var title: String
    /// The URL of the site, if the feed names one.
    public var home: String?
    public var etag: String?
    public var lastModified: String?
    /// The count of failed fetches in a row.
    public var failures: Int
    public var nextFetch: Date
    /// The reason of the last failure, for the sidebar row.
    public var error: String?

    public init(id: String, title: String, home: String? = nil, etag: String? = nil, lastModified: String? = nil,
                failures: Int = 0, nextFetch: Date = .distantPast, error: String? = nil) {
        self.id = id
        self.title = title
        self.home = home
        self.etag = etag
        self.lastModified = lastModified
        self.failures = failures
        self.nextFetch = nextFetch
        self.error = error
    }

    /// The host of the site, or of the feed if the feed names no site.
    public var host: String {
        let value = URL(string: home ?? id)?.host ?? id
        return value.hasPrefix("www.") ? String(value.dropFirst(4)) : value
    }
}

/// One article of a feed.
public struct Article: Equatable, Hashable, Identifiable, Sendable {
    /// The feed ID and the guid of the article, or a hash of its link.
    public let id: String
    public let feedID: String
    public let url: String
    public let title: String
    /// Plain text, at most `FeedDatabase.summaryLimit` characters.
    public let summary: String
    public let published: Date?
    public let arrived: Date
    public var read: Bool
    public var starred: Bool

    public init(id: String, feedID: String, url: String, title: String, summary: String, published: Date?,
                arrived: Date, read: Bool = false, starred: Bool = false) {
        self.id = id
        self.feedID = feedID
        self.url = url
        self.title = title
        self.summary = summary
        self.published = published
        self.arrived = arrived
        self.read = read
        self.starred = starred
    }

    /// The date that the list shows and sorts by.
    public var date: Date { published ?? arrived }
}

/// A row of the Feeds group in the sidebar.
public enum FeedFilter: Codable, Equatable, Hashable, Sendable {
    case discover
    case allUnread
    case starred
    case feed(String)
}

/// A site from browser history, with the feed that Piper found on it.
public struct Suggestion: Equatable, Hashable, Identifiable, Sendable {
    public let host: String
    /// Nil if Piper found no feed on the site.
    public let feedURL: String?
    public let title: String?
    public let visits: Int
    public let score: Double
    public var ignored: Bool

    public var id: String { host }

    public init(host: String, feedURL: String?, title: String?, visits: Int, score: Double, ignored: Bool = false) {
        self.host = host
        self.feedURL = feedURL
        self.title = title
        self.visits = visits
        self.score = score
        self.ignored = ignored
    }
}
