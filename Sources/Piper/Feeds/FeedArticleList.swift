import Captures
import Feeds
import SwiftUI

/// The articles of a row of the Feeds index, in the list of the feed paper.
///
/// The keys match NetNewsWire: Space goes to the next unread article, R marks
/// as read or unread, B opens the article in the browser, and
/// Command-K marks every article as read. I keeps the article in Inbox.
struct FeedArticleList: View {
    @Bindable var model: AppModel
    let filter: FeedFilter
    let selectedID: String?
    let select: (Article?) -> Void
    /// Opens an article as a reader paper, after a click, Return, or Space.
    var openPaper: (Article) -> Void = { _ in }

    /// Sets the keys of the list on the feed paper.
    var setKeys: (FeedPaperModel.ListKeys?) -> Void = { _ in }

    @State private var articles: [Article] = []
    @State private var scrollTarget: String?

    private var feeds: FeedStore { model.feeds }
    private var selected: Article? { articles.first { $0.id == selectedID } }

    var body: some View {
        VStack(spacing: 0) {
            header
            if articles.isEmpty {
                PaperEmpty(symbol: "dot.radiowaves.up.forward", title: emptyTitle, detail: emptyDetail)
            } else {
                ScrollViewReader { proxy in
                    ScrollView {
                        LazyVStack(alignment: .leading, spacing: 0) {
                            ForEach(articles) { article in
                                FeedArticleRow(article: article, feed: feeds.feed(article.feedID), favicons: model.favicons,
                                               showsFeed: !isOneFeed, selected: article.id == selectedID,
                                               toggleRead: { feeds.setRead(!article.read, [article]) }) {
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
        .onChange(of: filter) { _, _ in reload(keeping: false) }
        .onChange(of: feeds.revision) { _, _ in reload(keeping: true) }
        .onChange(of: articles.map(\.id)) { _, _ in setKeys(keys) }
        .onChange(of: selectedID) { _, _ in setKeys(keys) }
    }

    // MARK: - Parts

    private var header: some View {
        HStack(spacing: 14) {
            if let error = oneFeed?.error {
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
                      tint: articles.contains { !$0.read } ? PiperTheme.brand : PiperTheme.tertiaryLabel) { feeds.markAllRead(filter) }
                .disabled(!articles.contains { !$0.read })
                .keyboardShortcut("k", modifiers: .command)
        }
        .font(PiperTheme.paperUI(.body, weight: .medium))
        .padding(.horizontal, AppDefaults.Papers.footMargin)
        .padding(.top, 8)
    }

    @ViewBuilder
    private func menu(for article: Article) -> some View {
        Button(article.read ? "Mark as Unread" : "Mark as Read") { feeds.setRead(!article.read, [article]) }
        Divider()
        Button("Keep") { model.keep([article]) }.disabled(model.isKept(article))
        Button("Open in Browser") { openInBrowser(article) }
        Button("Copy Link") {
            NSPasteboard.general.clearContents()
            NSPasteboard.general.setString(article.url, forType: .string)
        }
    }

    // MARK: - Text

    private var isOneFeed: Bool {
        if case .feed = filter { return true }
        return false
    }

    private var oneFeed: Feed? {
        if case .feed(let id) = filter { return feeds.feed(id) }
        return nil
    }

    private var title: String {
        switch filter {
        case .allUnread: return "All Unread"
        case .feed: return oneFeed?.title ?? "Feed"
        }
    }

    private var emptyTitle: String {
        switch filter {
        case .feed: return "No Articles"
        default: return feeds.feeds.isEmpty ? "No Feeds" : "All Read"
        }
    }

    private var emptyDetail: String? {
        if feeds.feeds.isEmpty { return "Choose Sources in the More menu to add a feed." }
        if let error = oneFeed?.error { return error }
        return nil
    }

    // MARK: - Actions

    private func reload(keeping: Bool) {
        articles = feeds.articles(filter, keeping: keeping ? Set(articles.map(\.id)) : [])
        if let selectedID, !articles.contains(where: { $0.id == selectedID }) { select(nil) }
    }

    /// Selects the article and marks it as read.
    private func open(_ article: Article?) {
        select(article)
        if let article, !article.read { feeds.setRead(true, [article]) }
    }


    private func openInBrowser(_ article: Article) { model.openInBrowser(article) }

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

/// One article in the list: the icon of the site with the unread dot, the title, and the feed.
private struct FeedArticleRow: View {
    let article: Article
    let feed: Feed?
    let favicons: FaviconStore
    let showsFeed: Bool
    let selected: Bool
    let toggleRead: () -> Void
    let action: () -> Void

    var body: some View {
        PaperRow(item: .article(article.id), selected: selected, time: RowTime.text(article.date), action: action) {
            ZStack(alignment: .topTrailing) {
                SiteIcon(favicons: favicons, host: feed?.host ?? "", title: feed?.title ?? "", index: 0)
                if !article.read { UnreadDot(unread: true).offset(x: 3, y: -3) }
            }
        } content: {
            VStack(alignment: .leading, spacing: 0) {
                PaperRowTitle(text: Text(article.title), bold: !article.read)
                PaperRowMeta {
                    Text(showsFeed ? feed?.title ?? "" : feed?.host ?? "")
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
    func keep(_ articles: [Article]) {
        store.keep(links: keptLinks(articles))
        feeds.setRead(true, articles)
    }

    /// True when a kept capture holds the link of the article.
    func isKept(_ article: Article) -> Bool {
        URL(string: article.url).flatMap(store.article(for:))?.isKept == true
    }

    func openInBrowser(_ article: Article) {
        guard let url = URL(string: article.url) else { return }
        NSWorkspace.shared.open(url)
        feeds.setRead(true, [article])
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
