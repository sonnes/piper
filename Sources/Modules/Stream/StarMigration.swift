import Captures
import Feeds
import Foundation

/// Copies each starred feed article of an older version of Piper to a kept
/// link capture, one time.
///
/// Keep replaced Star. A link that a capture holds already gets no second
/// capture. The stars go only after the copy saves, so a failed copy runs
/// again at the next launch, and a second run adds nothing.
public enum StarMigration {

    /// Returns the count of new link captures.
    @MainActor @discardableResult
    public static func run(feeds: FeedStore, captures: CaptureStore, section: String = "Inbox") -> Int {
        let starred = feeds.starredArticles()
        guard !starred.isEmpty else { return 0 }
        let titles = Dictionary(feeds.feeds.map { ($0.id, $0.title) }, uniquingKeysWith: { first, _ in first })
        let links = starred.compactMap { article -> KeptLink? in
            guard let url = URL(string: article.url), CaptureLinks.isWebURL(url), captures.article(for: url) == nil else { return nil }
            return KeptLink(url: url, title: article.title, source: titles[article.feedID])
        }
        let before = captures.notes.count
        if !links.isEmpty {
            guard !captures.keep(links: links, to: section, recordUndo: false).isEmpty else { return 0 }
        }
        feeds.clearStars()
        return captures.notes.count - before
    }
}
