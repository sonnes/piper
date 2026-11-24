import AppKit
import Captures
import Feeds
import PiperCore

/// The verbs of a feed article: keep, open in the browser, copy the link, and
/// open as a paper. Today, the feed list, and the reader paper call them.
///
/// An article becomes a link capture only through `capture(_:to:)`.
@MainActor
final class ArticleActions {

    // MARK: - Properties

    /// Opens a web link in the browser. A test replaces it, so that no browser opens.
    var openURL: (URL) -> Void = { NSWorkspace.shared.open($0) }

    private let store: CaptureStore
    private let feeds: FeedStore
    private let messages: Messages

    init(store: CaptureStore, feeds: FeedStore, messages: Messages) {
        self.store = store
        self.feeds = feeds
        self.messages = messages
    }

    // MARK: - Keep

    /// True when a kept capture holds the link of the article.
    func isKept(_ article: Article) -> Bool {
        PaperItem.keptNote(of: article, in: store)?.isKept == true
    }

    /// Adds a kept link capture for each article, with the title of its feed
    /// as the source. Returns the captures, in the order of the articles.
    @discardableResult
    func capture(_ articles: [Article], to section: String? = nil) throws -> [Note] {
        let links = articles.compactMap { article in
            URL(string: article.url).map { KeptLink(url: $0, title: article.title, source: feeds.feed(article.feedID)?.title) }
        }
        return try store.keep(links: links, to: section)
    }

    /// Keeps the articles as link captures, and marks them as read.
    /// Returns false after it reports an error.
    @discardableResult
    func keep(_ articles: [Article]) -> Bool {
        do {
            try capture(articles)
        } catch {
            messages.report(error)
            return false
        }
        markRead(articles)
        return true
    }

    // MARK: - Open

    /// Opens the article in the browser, and marks it as read.
    func openInBrowser(_ article: Article) {
        guard let url = URL(string: article.url) else { return }
        openURL(url)
        markRead([article])
    }

    /// Opens the article on a reader paper, and marks it as read.
    func openAsPaper(_ article: Article, on desk: PaperDesk?) {
        desk?.open(.article(article.id))
        markRead([article])
    }

    func copyLink(_ article: Article) {
        Clipboard.copy(article.url)
    }

    private func markRead(_ articles: [Article]) {
        feeds.setRead(true, ids: articles.filter { !$0.read }.map(\.id))
    }
}
