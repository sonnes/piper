import Captures
import Feeds
import Foundation
import PiperCore

/// One row of Today: a note, a link, a feed article, a digest of one feed,
/// or a clipboard text.
///
/// The item is a view of the stores. It owns no data.
public struct StreamItem: Identifiable, Equatable {

    /// What the row shows.
    public enum Kind: Equatable, Sendable {
        /// A capture that is not a link.
        case note
        /// A link capture.
        case link
        /// A feed article that no capture holds.
        case article
        /// The new articles of one feed on one day.
        case digest
        /// A clipboard text that the reader did not keep.
        case clip
    }

    /// Where the item is in its life.
    ///
    /// A feed article starts as new and becomes reading when the reader
    /// opens it. Keep makes any item kept. Done ends it.
    public enum State: Equatable, Sendable {
        case new
        case reading
        case kept
        case done
    }

    /// The identity of a row, which names the store that holds the item.
    public enum Ref: Hashable, Sendable {
        case note(UUID)
        case article(String)
        /// The feed ID and the start of the day.
        case digest(String, Date)
        case clip(UUID)
    }

    // MARK: - Properties

    public let id: Ref
    public let kind: Kind
    public let state: State
    /// The note text, the page title, the article title, or the feed title.
    public let title: String
    /// The feed title, the app name, or the host.
    public let source: String?
    public let url: URL?
    /// The time that sorts the row: the creation time, the date of the
    /// article, the date of the newest article of a digest, or the copy time.
    public let date: Date
    /// The capture of a note or a link.
    public let note: Note?
    /// The highlights, notes, and questions under a link capture.
    public let children: [Note]
    /// The article of an article row, or the articles of a digest, best first.
    public let articles: [Article]
    public let clip: ClipboardEntry?
    /// The relevance of an article, from 0 to 1. Zero for every other kind.
    public let score: Double

    // MARK: - Initialization

    public static func capture(_ note: Note, children: [Note]) -> StreamItem {
        StreamItem(id: .note(note.id), kind: note.isArticle ? .link : .note, state: state(of: note, children: children),
                   title: note.isArticle ? (note.reading?.title ?? note.text) : note.text,
                   source: note.isArticle ? note.articleURL.flatMap(Site.init)?.key : note.sources.first,
                   url: note.isArticle ? note.articleURL : nil, date: note.createdAt, note: note, children: children,
                   articles: [], clip: nil, score: 0)
    }

    public static func article(_ article: Article, feed: Feed?, score: Double) -> StreamItem {
        StreamItem(id: .article(article.id), kind: .article, state: state(of: article), title: article.title,
                   source: feed?.title, url: URL(string: article.url), date: article.date, note: nil, children: [],
                   articles: [article], clip: nil, score: score)
    }

    public static func digest(_ articles: [Article], feed: Feed, day: Date) -> StreamItem {
        StreamItem(id: .digest(feed.id, day), kind: .digest,
                   state: articles.allSatisfy(\.read) ? .reading : .new, title: feed.title, source: feed.host,
                   url: feed.home.flatMap(URL.init(string:)), date: articles.map(\.date).max() ?? day, note: nil,
                   children: [], articles: articles, clip: nil, score: 0)
    }

    public static func clip(_ entry: ClipboardEntry) -> StreamItem {
        StreamItem(id: .clip(entry.id), kind: .clip, state: .new, title: entry.text, source: entry.source,
                   url: CaptureLinks(entry.text).standaloneURL, date: entry.copiedAt, note: nil, children: [],
                   articles: [], clip: entry, score: 0)
    }

    // MARK: - State

    /// The state of a capture. A capture that the reader kept, highlighted,
    /// or noted is kept. An opened link with no notes is reading.
    public static func state(of note: Note, children: [Note]) -> State {
        if note.isDone || note.reading?.finishedAt != nil { return .done }
        if note.isKept || !children.isEmpty { return .kept }
        if note.reading?.openedAt != nil { return .reading }
        return .new
    }

    /// The state of a feed article that no capture holds.
    public static func state(of article: Article) -> State {
        article.read ? .reading : .new
    }
}
