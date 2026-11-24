import Captures
import Feeds
import SwiftUI

/// The articles of one feed, in the list of the feed paper.
///
/// Space goes to the next unread article, as in NetNewsWire. K keeps the
/// article, B opens it in the browser, and Shift-Command-K marks every article as read.
struct FeedArticleList: View {
    @Bindable var model: AppModel
    let feedID: String
    let selectedID: String?
    let select: (Article?) -> Void
    /// Sets the keys of the list on the feed paper.
    var setKeys: ([PaperKey]) -> Void = { _ in }

    @State private var articles: [Article] = []
    @State private var scrollTarget: String?
    @Environment(\.paperDesk) private var desk

    private var feeds: FeedStore { model.feeds }
    private var actions: ArticleActions { model.articleActions }
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
                                    openPaper(article)
                                }
                                .id(article.id)
                                .contextMenu { menu(for: article) }
                            }
                        }
                        .padding(PaperRowMetrics.listPadding)
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
                ProgressView().controlSize(.small).frame(width: PaperRowMetrics.rowActionSize)
            }
            RowAction(symbol: "envelope.open", title: Command.markAllAsRead.title + " · " + (Command.markAllAsRead.key?.name ?? ""),
                      tint: articles.contains { !$0.read } ? PiperTheme.brand : PiperTheme.paperFaint) { feeds.markAllRead(.feed(feedID)) }
                .disabled(!articles.contains { !$0.read })
        }
        .font(PiperTheme.paperUI(.body, weight: .medium))
        .padding(.horizontal, HintStrip.Metrics.footMargin)
        .padding(.top, 8)
    }

    @ViewBuilder
    private func menu(for article: Article) -> some View {
        Button(article.read ? "Mark as Unread" : "Mark as Read") { feeds.setRead(!article.read, ids: [article.id]) }
        Divider()
        Button("Keep") { actions.keep([article]) }.disabled(actions.isKept(article))
        Button("Open in Browser") { actions.openInBrowser(article) }
        Button("Copy Link") { actions.copyLink(article) }
    }

    private func reload(keeping: Bool) {
        articles = feeds.articles(.feed(feedID), keeping: keeping ? Set(articles.map(\.id)) : [])
        if let selectedID, !articles.contains(where: { $0.id == selectedID }) { select(nil) }
    }

    /// Selects the article and opens it as a reader paper, after a click, Return, or Space.
    private func openPaper(_ article: Article) {
        select(article)
        actions.openAsPaper(article, on: desk)
    }

    /// The keys of the list: the arrows move the selection, Return opens the
    /// article as a paper, Space opens the next unread article, and K and B
    /// act on the selected article.
    private var keys: [PaperKey] {
        let selected = selected
        return [
            PaperKey(key: .up, title: "move") { move(-1) },
            PaperKey(key: .down, title: "move") { move(1) },
            PaperKey(key: .enter, title: "open as a paper", isOn: { selected != nil }) {
                if let selected { openPaper(selected) }
            },
            PaperKey(key: .space, title: "next unread") {
                let start = articles.firstIndex { $0.id == selectedID }.map { $0 + 1 } ?? 0
                guard start <= articles.count, let next = articles[start...].first(where: { !$0.read }) else { return }
                openPaper(next)
                scrollTarget = next.id
            }
        ] + PaperKey.articleKeys(actions: actions) { selected }
    }

    private func move(_ delta: Int) {
        guard let id = articles.map(\.id).step(from: selectedID, by: delta),
              let next = articles.first(where: { $0.id == id }) else { return }
        select(next)
        if !next.read { feeds.setRead(true, ids: [next.id]) }
        scrollTarget = next.id
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
