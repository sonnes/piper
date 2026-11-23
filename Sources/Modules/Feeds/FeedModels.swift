import Foundation
import PiperCore

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
    /// The reason of the last failure, for the row of the feed.
    public var error: String?
    /// How the posts of the feed reach Today.
    public var mode: FeedMode

    public init(id: String, title: String, home: String? = nil, etag: String? = nil, lastModified: String? = nil,
                failures: Int = 0, nextFetch: Date = .distantPast, error: String? = nil, mode: FeedMode = .best) {
        self.id = id
        self.title = title
        self.home = home
        self.etag = etag
        self.lastModified = lastModified
        self.failures = failures
        self.nextFetch = nextFetch
        self.error = error
        self.mode = mode
    }

    /// The host of the site, or of the feed if the feed names no site.
    public var host: String {
        URL(string: home ?? id).flatMap(Site.init)?.key ?? id
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

    public init(id: String, feedID: String, url: String, title: String, summary: String, published: Date?,
                arrived: Date, read: Bool = false) {
        self.id = id
        self.feedID = feedID
        self.url = url
        self.title = title
        self.summary = summary
        self.published = published
        self.arrived = arrived
        self.read = read
    }

    /// The date that the list shows and sorts by.
    public var date: Date { published ?? arrived }
}

/// The articles that a list reads: the unread articles of every feed, or each article of one feed.
public enum FeedFilter: Equatable, Hashable, Sendable {
    case allUnread
    case feed(String)
}

/// How the posts of a feed reach Today. The reader sets it on the Sources paper.
public enum FeedMode: String, Codable, CaseIterable, Sendable {
    /// Each post has its own row.
    case every
    /// Posts that score high have their own row. A busy day goes into a digest row.
    case best
    /// One digest row for each day.
    case digest
    /// No row in Today. The posts show only in the list of the feed.
    case off

    public var title: String {
        switch self {
        case .every: return "Every post"
        case .best: return "Best"
        case .digest: return "Digest"
        case .off: return "Off"
        }
    }
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
