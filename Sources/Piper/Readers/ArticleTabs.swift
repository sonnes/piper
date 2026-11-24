import Captures
import Foundation
import Observation
import PiperCore

/// The tab that each link capture shows, the tab that each site opens in,
/// and the place that the Reader tab scrolls to.
///
/// Each reader paper has its own tab. A capture keeps its tab after its paper
/// closes, until Piper quits. Preferences keep the tab of each site.
@MainActor @Observable
final class ArticleTabs {

    // MARK: - Properties

    /// The place that the Reader tab scrolls to.
    private(set) var scroll: ReaderScroll?
    /// The tab of each open link capture, by the id of the capture.
    private var tabs: [UUID: ArticleTab] = [:]
    /// The tab, Reader or Web, that the reader last chose for each site, by `Site.key`.
    private var siteTabs: [String: ArticleTab]
    @ObservationIgnored private let preferences: UserDefaults

    init(preferences: UserDefaults) {
        self.preferences = preferences
        siteTabs = (preferences.dictionary(forKey: AppDefaults.Key.siteTabs) as? [String: Int] ?? [:])
            .compactMapValues { ArticleTab(rawValue: $0) }
    }

    // MARK: - API

    /// The tab of a link capture as it opens. A request to show one of its
    /// highlights opens the Reader tab. Each other link opens in the tab that
    /// the reader last chose for its site. A new site opens in the Web tab.
    func openingTab(for note: Note) -> ArticleTab {
        if let scroll, scroll.article == note.id, scroll.note != nil { return .reader }
        return note.articleURL.flatMap(Site.init).flatMap { siteTabs[$0.key] } ?? .web
    }

    /// The tab that a link capture shows: the tab that the reader chose for
    /// it, or else its opening tab.
    func tab(for note: Note) -> ArticleTab {
        tabs[note.id] ?? openingTab(for: note)
    }

    /// Keeps the tab of a link capture as it opens, so that a later change of
    /// the opening tab of its site does not change it.
    func keep(for note: Note) {
        tabs[note.id] = tab(for: note)
    }

    /// Shows a tab of a link capture that the reader chose. A choice of Reader
    /// or Web becomes the opening tab of the site of the link.
    func choose(_ tab: ArticleTab, for note: Note) {
        tabs[note.id] = tab
        guard tab != .notes, let url = note.articleURL, let site = Site(url)?.key, siteTabs[site] != tab else { return }
        siteTabs[site] = tab
        preferences.set(siteTabs.mapValues(\.rawValue), forKey: AppDefaults.Key.siteTabs)
    }

    /// Shows a highlight or a question of a link capture in the Reader tab.
    func showHighlight(_ note: UUID, in article: UUID) {
        tabs[article] = .reader
        scrollToNote(note, in: article)
    }

    /// Scrolls the Reader tab of a link capture to a block. Zero is the top.
    func scrollToBlock(_ block: Int, in article: UUID) {
        scroll = ReaderScroll(block: block, in: article)
    }

    /// Scrolls the Reader tab of a link capture to a child note.
    func scrollToNote(_ note: UUID, in article: UUID) {
        scroll = ReaderScroll(note: note, in: article)
    }

    /// Ends a scroll request after the page ran it. A newer request stays.
    func clearScroll(_ request: ReaderScroll) {
        if scroll == request { scroll = nil }
    }

    /// Shows the place that a paper of a link capture opens at.
    func show(_ target: ReaderTarget, for note: Note) {
        switch target {
        case .openingTab: tabs[note.id] = openingTab(for: note)
        case .highlight(let id): showHighlight(id, in: note.id)
        }
    }
}

/// The tabs of a link capture in its reader paper.
enum ArticleTab: Int {
    case reader
    case web
    case notes
}

/// The place where the paper of a link capture opens.
enum ReaderTarget: Hashable {
    /// The opening tab of the site, in place of the tab that the reader last chose for the capture.
    case openingTab
    /// A highlight or a question of the capture, in the Reader tab.
    case highlight(UUID)
}

/// A request to scroll the Reader tab to a child note. Each request is new, so
/// a second click on the same note scrolls again.
struct ReaderScroll: Equatable {
    /// The link capture that the request is for. Another article ignores it.
    let article: UUID
    /// The child note to show. Nil scrolls to the block.
    let note: UUID?
    /// The block to show when no note is given. Zero is the top.
    let block: Int?
    let request = UUID()

    init(note: UUID, in article: UUID) {
        self.article = article
        self.note = note
        block = nil
    }

    init(block: Int, in article: UUID) {
        self.article = article
        note = nil
        self.block = block
    }
}
