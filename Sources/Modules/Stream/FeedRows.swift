import Feeds
import Foundation

/// The rows that the articles of the feeds get in Today.
///
/// Each feed has a mode. Every post gives each article a row. Digest gives
/// one row for each day. Best gives a row to the articles that score high, and
/// puts a busy day of a feed into one digest row. Off gives no row.
public enum FeedRows {

    // MARK: - Properties

    /// A feed with more new articles than this on one day is busy.
    public static let busyDay = 3
    /// The count of articles of a busy day that keep their own row in Best mode.
    public static let bestOnBusyDay = 2

    // MARK: - API

    /// The rows of the articles, in no order. The caller sorts them by date.
    public static func rows(articles: [Article], feeds: [Feed], relevance: Relevance,
                            calendar: Calendar = .current) -> [StreamItem] {
        let byID = Dictionary(feeds.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
        var rows: [StreamItem] = []
        let groups = Dictionary(grouping: articles) { DayKey(feed: $0.feedID, day: calendar.startOfDay(for: $0.date)) }
        for (key, group) in groups {
            guard let feed = byID[key.feed] else { continue }
            let ranked = relevance.ranked(group)
            func row(_ article: Article) -> StreamItem { .article(article, feed: feed, score: relevance.score(article)) }
            switch feed.mode {
            case .off:
                continue
            case .every:
                rows += ranked.map(row)
            case .digest:
                rows += ranked.count == 1 ? ranked.map(row) : [.digest(ranked, feed: feed, day: key.day)]
            case .best:
                if ranked.count <= busyDay {
                    rows += ranked.map(row)
                    continue
                }
                let own = ranked.prefix(bestOnBusyDay).filter { relevance.score($0) >= Relevance.bar }
                let ownIDs = Set(own.map(\.id))
                rows += own.map(row)
                rows.append(.digest(ranked.filter { !ownIDs.contains($0.id) }, feed: feed, day: key.day))
            }
        }
        return rows
    }

    private struct DayKey: Hashable {
        let feed: String
        let day: Date
    }
}
