import Captures
import Feeds
import SwiftUI

/// The articles of one feed, in the list of the feed paper.
///
/// Space goes to the next unread article, as in NetNewsWire. K keeps the
/// article, B opens it in the browser, and Command-K marks every article as read.
struct FeedArticleList: View {
    @Bindable var model: AppModel
    let feedID: String
    let selectedID: String?
    let select: (Article?) -> Void
    /// Opens an article as a reader paper, after a click, Return, or Space.
    var openPaper: (Article) -> Void = { _ in }

    /// Sets the keys of the list on the feed paper.
    var setKeys: (FeedPaperModel.ListKeys?) -> Void = { _ in }

    @State private var articles: [Article] = []
    @State private var scrollTarget: String?

    private var feeds: FeedStore { model.feeds }
    private var feed: Feed? { feeds.feed(feedID) }
    private var selected: Article? { articles.first { $0.id == selectedID } }

    var body: some View {
        VStack(spacing: 0) {
            header
            if articles.isEmpty {
                PaperEmpty(symbol: "dot.radiowaves.up.forward", title: "No Articles", detail: feed?.error)
            } else {
                ScrollViewReader { proxy in
                    ScrollView {
                        LazyVStack(alignment: .leading, spacing: 0) {
                            ForEach(articles) { article in
                                FeedArticleRow(article: article, feed: feed, favicons: model.favicons,
                                               selected: article.id == selectedID,
                                               toggleRead: { feeds.setRead(!article.read, ids: [article.id]) }) {
                                    open(article)
                                    openPaper(article)
                                }
                                .id(article.id)
                                .contextMenu { menu(for: article) }
                            }
                        }
                        .padding(AppDefaults.Papers.listPadding)
                    }
                    .onChange(of: scrollTarget) { _, id in
                        guard let id else { return }
                        proxy.scrollTo(id)
                    }
                }
            }
        }
        .onAppear {
            reload(keeping: false)
            setKeys(keys)
        }
        .onChange(of: feedID) { _, _ in reload(keeping: false) }
        .onChange(of: feeds.revision) { _, _ in reload(keeping: true) }
        .onChange(of: articles.map(\.id)) { _, _ in setKeys(keys) }
        .onChange(of: selectedID) { _, _ in setKeys(keys) }
    }

    // MARK: - Parts

    private var header: some View {
        HStack(spacing: 14) {
            if let error = feed?.error {
                Image(systemName: "exclamationmark.triangle").foregroundStyle(PiperTheme.warning)
                    .help(error)
            }
            Spacer(minLength: 8)
            if feeds.fetching.isEmpty {
                RowAction(symbol: "arrow.clockwise", title: "Refresh All Feeds") { feeds.refreshAll() }
            } else {
                ProgressView().controlSize(.small).frame(width: AppDefaults.Papers.rowActionSize)
            }
            RowAction(symbol: "envelope.open", title: "Mark All as Read · Command-K",
                      tint: articles.contains { !$0.read } ? PiperTheme.brand : PiperTheme.tertiaryLabel) { feeds.markAllRead(.feed(feedID)) }
                .disabled(!articles.contains { !$0.read })
                .keyboardShortcut("k", modifiers: .command)
        }
        .font(PiperTheme.paperUI(.body, weight: .medium))
        .padding(.horizontal, AppDefaults.Papers.footMargin)
        .padding(.top, 8)
    }

    @ViewBuilder
    private func menu(for article: Article) -> some View {
        Button(article.read ? "Mark as Unread" : "Mark as Read") { feeds.setRead(!article.read, ids: [article.id]) }
        Divider()
        Button("Keep") { model.keep([article]) }.disabled(model.isKept(article))
        Button("Open in Browser") { model.openInBrowser(article) }
        Button("Copy Link") { Clipboard.copy(article.url) }
    }

    // MARK: - Actions

    private func reload(keeping: Bool) {
        articles = feeds.articles(.feed(feedID), keeping: keeping ? Set(articles.map(\.id)) : [])
        if let selectedID, !articles.contains(where: { $0.id == selectedID }) { select(nil) }
    }

    /// Selects the article and marks it as read.
    private func open(_ article: Article?) {
        select(article)
        if let article, !article.read { feeds.setRead(true, ids: [article.id]) }
    }

    /// The keys of the list: the arrows move the selection, Return opens the
    /// article as a paper, Space opens the next unread article, and the
    /// letters act on the selected article.
    private var keys: FeedPaperModel.ListKeys {
        FeedPaperModel.ListKeys(
            move: { delta in
                let current = articles.firstIndex { $0.id == selectedID }
                let next = max(0, min(articles.count - 1, (current ?? (delta > 0 ? -1 : articles.count)) + delta))
                guard articles.indices.contains(next) else { return }
                open(articles[next])
                scrollTarget = articles[next].id
            },
            open: {
                if let selected { openPaper(selected) }
            },
            letter: { key in
                if key == " " {
                    let start = articles.firstIndex { $0.id == selectedID }.map { $0 + 1 } ?? 0
                    guard start <= articles.count, let next = articles[start...].first(where: { !$0.read }) else { return true }
                    open(next)
                    openPaper(next)
                    scrollTarget = next.id
                    return true
                }
                guard let selected else { return false }
                return model.articleKey(key, on: selected)
            })
    }
}

/// One article in the list: the icon of the site with the unread dot, the title, and the host.
private struct FeedArticleRow: View {
    let article: Article
    let feed: Feed?
    let favicons: FaviconStore
    let selected: Bool
    let toggleRead: () -> Void
    let action: () -> Void

    var body: some View {
        PaperRow(item: .article(article.id), selected: selected, time: RowTime.text(article.date), action: action) {
            ZStack(alignment: .topTrailing) {
                SiteIcon(favicons: favicons, host: feed?.host ?? "", title: feed?.title ?? "")
                if !article.read { UnreadDot().offset(x: 3, y: -3) }
            }
        } content: {
            VStack(alignment: .leading, spacing: 0) {
                PaperRowTitle(text: Text(article.title), bold: !article.read)
                PaperRowMeta {
                    Text(feed?.host ?? "")
                }
            }
        } actions: {
            RowAction(symbol: article.read ? "circle.fill" : "circle", title: article.read ? "Mark as Unread" : "Mark as Read",
                      action: toggleRead)
        }
    }
}

extension AppModel {
    /// The links of articles, with the title of each feed as the source.
    func keptLinks(_ articles: [Article]) -> [KeptLink] {
        articles.compactMap { article in
            URL(string: article.url).map { KeptLink(url: $0, title: article.title, source: feeds.feed(article.feedID)?.title) }
        }
    }

    /// Keeps articles as kept link captures, and marks them as read.
    /// Returns false after it reports an error.
    @discardableResult
    func keep(_ articles: [Article]) -> Bool {
        do {
            try store.keep(links: keptLinks(articles))
        } catch {
            messages.report(error)
            return false
        }
        feeds.setRead(true, ids: articles.filter { !$0.read }.map(\.id))
        return true
    }

    /// True when a kept capture holds the link of the article.
    func isKept(_ article: Article) -> Bool {
        PaperItem.keptNote(of: article, in: store)?.isKept == true
    }

    func openInBrowser(_ article: Article) {
        guard let url = URL(string: article.url) else { return }
        NSWorkspace.shared.open(url)
        if !article.read { feeds.setRead(true, ids: [article.id]) }
    }

    /// The letter keys of an article, on its row or on its paper: K keeps it,
    /// and B opens it in the browser.
    ///
    /// - Returns: True when the key is one of these.
    func articleKey(_ key: Character, on article: Article) -> Bool {
        switch key {
        case "k": keep([article])
        case "b": openInBrowser(article)
        default: return false
        }
        return true
    }
}
