import Captures
import Feeds
import Foundation
import PiperCore

/// How often the reader keeps the posts of a feed, and how often the feed posts.
public struct FeedStats: Equatable, Sendable {

    // MARK: - Properties

    /// The days that the counts cover.
    public static let days = 28

    public let postsPerWeek: Double
    /// The part of the recent posts that the reader kept, from 0 to 1.
    public let keepRate: Double
    /// The count of link captures from the site of the feed.
    public let kept: Int

    public init(postsPerWeek: Double, keepRate: Double, kept: Int) {
        self.postsPerWeek = postsPerWeek
        self.keepRate = keepRate
        self.kept = kept
    }

    /// The stats of each feed, by feed ID.
    ///
    /// - Parameters:
    ///   - counts: The articles of each feed in the last `days` days.
    ///   - notes: Every capture. A link capture from the host of a feed counts as one kept post.
    public static func compute(feeds: [Feed], counts: [String: Int], notes: [Note]) -> [String: FeedStats] {
        var keptByHost: [String: Int] = [:]
        for note in notes where note.parent == nil && note.isArticle {
            guard let site = note.articleURL.flatMap(Site.init) else { continue }
            keptByHost[site.key, default: 0] += 1
        }
        var stats: [String: FeedStats] = [:]
        for feed in feeds {
            let posts = counts[feed.id] ?? 0
            let kept = keptByHost[feed.host] ?? 0
            stats[feed.id] = FeedStats(postsPerWeek: Double(posts) * 7 / Double(days),
                                       keepRate: min(1, Double(kept) / Double(max(posts, 3))), kept: kept)
        }
        return stats
    }

    /// The stats of each feed of the store, by feed ID, from its counts of the last `days` days.
    @MainActor
    public static func compute(_ feeds: FeedStore, notes: [Note]) -> [String: FeedStats] {
        compute(feeds: feeds.feeds, counts: feeds.articleCounts(days: days), notes: notes)
    }
}

/// A score from 0 to 1 that tells how relevant an article is to the reader.
///
/// Every signal is local: how often the reader keeps posts of the feed, how
/// often the browser history visits the site, and the words that the file
/// names of the folders share with the title. Piper sends nothing off the Mac.
public struct Relevance: Equatable, Sendable {

    // MARK: - Properties

    /// An article with this score or more can have its own row in Best mode.
    public static let bar = 0.25
    static let keepWeight = 3.0
    static let siteWeight = 2.0
    static let topicWeight = 3.0
    /// The count of shared words that gives the full topic signal.
    static let topicWords = 2.0
    static let minimumWordLength = 4

    /// The keep rate of each feed, by feed ID.
    public var keepRates: [String: Double]
    /// The history score of each host, from 0 to 1.
    public var sites: [String: Double]
    /// The words of the file names of the folders, in lowercase.
    public var terms: Set<String>

    public init(keepRates: [String: Double] = [:], sites: [String: Double] = [:], terms: Set<String> = []) {
        self.keepRates = keepRates
        self.sites = sites
        self.terms = terms
    }

    /// The relevance from the stats of the feeds, the history score of each
    /// host, and the file names of the folders.
    public init(stats: [String: FeedStats], history: [String: Double], fileNames: [String]) {
        let top = history.values.max() ?? 0
        self.init(keepRates: stats.mapValues(\.keepRate),
                  sites: top > 0 ? Dictionary(uniqueKeysWithValues: history.map { (Site(host: $0.key).key, $0.value / top) }) : [:],
                  terms: fileNames.reduce(into: Set<String>()) { $0.formUnion(Self.words(in: Self.stem($1))) })
    }

    /// The relevance from the feeds of the store, its browser history
    /// suggestions, the captures, and the file names of the folders.
    @MainActor
    public init(feeds: FeedStore, notes: [Note], fileNames: [String]) {
        self.init(stats: FeedStats.compute(feeds, notes: notes),
                  history: Dictionary(feeds.suggestions.map { ($0.host, $0.score) }, uniquingKeysWith: max),
                  fileNames: fileNames)
    }

    // MARK: - API

    public func score(_ article: Article) -> Double {
        let keep = keepRates[article.feedID] ?? 0
        let site = URL(string: article.url).flatMap(Site.init).map { sites[$0.key] ?? 0 } ?? 0
        let shared = Self.words(in: article.title).intersection(terms).count
        let topic = min(1, Double(shared) / Self.topicWords)
        return (Self.keepWeight * keep + Self.siteWeight * site + Self.topicWeight * topic)
            / (Self.keepWeight + Self.siteWeight + Self.topicWeight)
    }

    /// The articles, the highest score first. Equal scores keep the newest first.
    public func ranked(_ articles: [Article]) -> [Article] {
        articles.map { ($0, score($0)) }
            .sorted { $0.1 != $1.1 ? $0.1 > $1.1 : $0.0.date > $1.0.date }
            .map(\.0)
    }

    /// The words of a text in lowercase, with at least four letters.
    static func words(in text: String) -> Set<String> {
        Set(text.lowercased().split { !$0.isLetter && !$0.isNumber }.map(String.init)
            .filter { $0.count >= minimumWordLength })
    }

    /// The name of a file without its folder and its extension.
    static func stem(_ path: String) -> String {
        ((path as NSString).lastPathComponent as NSString).deletingPathExtension
    }
}
