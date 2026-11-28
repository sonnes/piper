import AppKit
import Captures
import Feeds
import PiperCore
import Vault

/// The verbs of a feed article: mark as read, keep, open in the browser, copy
/// the link, and open as a paper, and Save as File for a link capture. Today,
/// the feed list, and the reader paper call them.
///
/// An article becomes a link capture only through `capture(_:to:)`. A read
/// mark changes only through `setRead(_:ids:undoable:)`. A file gets text
/// only through `saveAsFile` and `append`, which record the file of each
/// link capture and scan the folders again.
@MainActor
final class ArticleActions {

    // MARK: - Properties

    /// Opens a web link in the browser. A test replaces it, so that no browser opens.
    var openURL: (URL) -> Void = { NSWorkspace.shared.open($0) }

    private let store: CaptureStore
    private let feeds: FeedStore
    private let messages: Messages
    private let library: Library
    private let open: (PaperItem) -> Void

    init(store: CaptureStore, feeds: FeedStore, messages: Messages, library: Library, open: @escaping (PaperItem) -> Void) {
        self.store = store
        self.feeds = feeds
        self.messages = messages
        self.library = library
        self.open = open
    }

    // MARK: - Read

    /// Marks the articles as read or unread. A mark that the reader chose,
    /// such as Mark as Read or Done, is undoable. The read mark of an article
    /// that the reader opens is not.
    func setRead(_ read: Bool, ids: [String], undoable: Bool) {
        guard !ids.isEmpty else { return }
        feeds.setRead(read, ids: ids)
        guard undoable else { return }
        let undoManager = store.undoManager
        undoManager.beginUndoGrouping()
        undoManager.registerUndo(withTarget: self) { actions in actions.setRead(!read, ids: ids, undoable: true) }
        undoManager.endUndoGrouping()
    }

    /// Marks every unread article of the feed as read, with an undo step.
    func markAllRead(feed: String) {
        setRead(true, ids: feeds.articles(.feed(feed)).filter { !$0.read }.map(\.id), undoable: true)
    }

    // MARK: - Keep

    /// True when a kept capture holds the link of the article.
    func isKept(_ article: Article) -> Bool {
        PaperItem.keptNote(of: article, in: store)?.isKept == true
    }

    /// The title of the feed of the article: a saved feed, or Hacker News for a story of the Hacker News tab.
    func source(of article: Article) -> String? {
        article.feedID == HackerNews.feedID ? HackerNews.title : feeds.feed(article.feedID)?.title
    }

    /// Adds a kept link capture for each article, with the title of its feed
    /// as the source. Returns the captures, in the order of the articles.
    @discardableResult
    func capture(_ articles: [Article], to section: String? = nil) throws -> [Note] {
        let links = articles.compactMap { article in
            URL(string: article.url).map { KeptLink(url: $0, title: article.title, source: source(of: article)) }
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
    func openAsPaper(_ article: Article) {
        open(.article(article.id))
        markRead([article])
    }

    /// Opens the page of a story and its comments on Hacker News in the browser.
    func openOnHackerNews(_ story: HackerNews.Story) {
        guard let url = URL(string: story.itemURL) else { return }
        openURL(url)
    }

    func copyLink(_ article: Article) {
        messages.copy(article.url)
    }

    // MARK: - Save as File

    /// Writes the text as a new file in a folder of a root. A file with the
    /// same name stays, and the new file gets a number. Returns the path of
    /// the new file.
    @discardableResult
    func saveAsFile(_ text: String, named name: String, root: String, folder: String, for notes: [Note]) throws -> String {
        let vault = Vault(path: root)
        let path = vault.freeName((name as NSString).deletingPathExtension, ext: (name as NSString).pathExtension, in: folder)
        try vault.write(text, to: path)
        let file = vault.root.appendingPathComponent(path).path
        try recordFile(file, for: notes)
        return file
    }

    /// Adds the text to the end of the file at a full path. See `Vault.append(_:to:)`.
    func append(_ text: String, toFile file: String, for notes: [Note]) throws {
        try Vault(path: (file as NSString).deletingLastPathComponent).append(text, to: (file as NSString).lastPathComponent)
        try recordFile(file, for: notes)
    }

    private func recordFile(_ file: String, for notes: [Note]) throws {
        let now = Date()
        for note in notes where note.isArticle {
            try store.updateReading(note.id) { $0.savedFile = file; $0.savedAt = now }
        }
        library.reload()
    }

    private func markRead(_ articles: [Article]) {
        setRead(true, ids: articles.filter { !$0.read }.map(\.id), undoable: false)
    }
}
