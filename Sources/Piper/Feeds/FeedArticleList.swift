import Captures
import Feeds
import SwiftUI

/// The articles of a row of the Feeds group, in the list pane.
///
/// The keys match NetNewsWire: Space goes to the next unread article, R marks
/// as read or unread, S stars, B opens the article in the browser, and
/// Command-K marks every article as read. I keeps the article in Inbox.
struct FeedArticleList: View {
    @Bindable var model: AppModel
    let filter: FeedFilter
    let selectedID: String?
    let select: (Article?) -> Void

    @State private var articles: [Article] = []
    @FocusState private var focused: Bool

    private var feeds: FeedStore { model.feeds }
    private var selected: Article? { articles.first { $0.id == selectedID } }

    var body: some View {
        VStack(spacing: 0) {
            header
            Rule()
            if articles.isEmpty {
                EmptyPane(title: emptyTitle, detail: emptyDetail)
            } else {
                ScrollViewReader { proxy in
                    List(selection: Binding(get: { selectedID }, set: { id in open(articles.first { $0.id == id }) })) {
                        ForEach(articles) { article in
                            FeedArticleRow(article: article, feed: feeds.feed(article.feedID),
                                           showsFeed: !isOneFeed, favicons: model.favicons,
                                           index: feeds.feeds.firstIndex { $0.id == article.feedID } ?? 0)
                                .tag(article.id)
                                .contextMenu { menu(for: article) }
                        }
                    }
                    .listStyle(.plain)
                    .scrollContentBackground(.hidden)
                    .focused($focused)
                    .onKeyPress(phases: .down) { press in handle(press, proxy: proxy) }
                }
            }
        }
        .background(PiperTheme.page)
        .onAppear { reload(keeping: false) }
        .onChange(of: filter) { _, _ in reload(keeping: false) }
        .onChange(of: feeds.revision) { _, _ in reload(keeping: true) }
    }

    // MARK: - Parts

    private var header: some View {
        HStack(spacing: 8) {
            Text(title).font(PiperTheme.ui(.body, weight: .semibold)).lineLimit(1)
            if let error = oneFeed?.error {
                Image(systemName: "exclamationmark.triangle").foregroundStyle(PiperTheme.warning)
                    .help(error)
            }
            Spacer(minLength: 8)
            if feeds.fetching.isEmpty {
                Button { feeds.refreshAll() } label: { Image(systemName: "arrow.clockwise") }
                    .buttonStyle(.plain).foregroundStyle(PiperTheme.secondary)
                    .help("Refresh All Feeds")
            } else {
                ProgressView().controlSize(.small)
            }
            Button("Mark All as Read") { feeds.markAllRead(filter) }
                .buttonStyle(.text)
                .disabled(!articles.contains { !$0.read })
                .keyboardShortcut("k", modifiers: .command)
        }
        .font(PiperTheme.ui(.secondary))
        .padding(.horizontal, 12)
        .frame(height: AppDefaults.Feeds.headerHeight)
    }

    @ViewBuilder
    private func menu(for article: Article) -> some View {
        Button(article.read ? "Mark as Unread" : "Mark as Read") { feeds.setRead(!article.read, [article]) }
        Button(article.starred ? "Remove Star" : "Star") { feeds.setStarred(!article.starred, article) }
        Divider()
        Button("Keep in Inbox") { keep(article) }
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
        case .discover: return "Discover"
        case .allUnread: return "All Unread"
        case .starred: return "Starred"
        case .feed: return oneFeed?.title ?? "Feed"
        }
    }

    private var emptyTitle: String {
        switch filter {
        case .starred: return "No Starred Articles"
        case .feed: return "No Articles"
        default: return feeds.feeds.isEmpty ? "No Feeds" : "All Read"
        }
    }

    private var emptyDetail: String? {
        if feeds.feeds.isEmpty { return "Select + next to Feeds to add a feed." }
        if case .starred = filter { return "Press S to star the selected article." }
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

    private func keep(_ article: Article) {
        guard let url = URL(string: article.url) else { return }
        model.store.saveArticle(url, title: article.title, source: feeds.feed(article.feedID)?.title)
        feeds.setRead(true, [article])
    }

    private func openInBrowser(_ article: Article) {
        guard let url = URL(string: article.url) else { return }
        NSWorkspace.shared.open(url)
        feeds.setRead(true, [article])
    }

    private func handle(_ press: KeyPress, proxy: ScrollViewProxy) -> KeyPress.Result {
        guard press.modifiers.isEmpty || press.modifiers == .shift else { return .ignored }
        switch press.characters.lowercased() {
        case " ":
            let start = articles.firstIndex { $0.id == selectedID }.map { $0 + 1 } ?? 0
            guard let next = articles[start...].first(where: { !$0.read }) else { return .handled }
            open(next)
            proxy.scrollTo(next.id)
        case "r":
            guard let selected else { return .ignored }
            feeds.setRead(!selected.read, [selected])
        case "s":
            guard let selected else { return .ignored }
            feeds.setStarred(!selected.starred, selected)
        case "b":
            guard let selected else { return .ignored }
            openInBrowser(selected)
        case "i":
            guard let selected else { return .ignored }
            keep(selected)
        default:
            return .ignored
        }
        return .handled
    }
}

/// One article in the list: the feed and the time, the title, and the start of the summary.
private struct FeedArticleRow: View {
    let article: Article
    let feed: Feed?
    let showsFeed: Bool
    let favicons: FaviconStore
    /// The place of the feed in the sidebar, for the color of its letter tile.
    let index: Int

    var body: some View {
        HStack(alignment: .top, spacing: 8) {
            Circle()
                .fill(article.read ? Color.clear : PiperTheme.accent)
                .frame(width: AppDefaults.Feeds.unreadDot, height: AppDefaults.Feeds.unreadDot)
                .padding(.top, 5)
                .accessibilityLabel(article.read ? "" : "Unread")
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 5) {
                    if showsFeed, let feed {
                        SiteIcon(favicons: favicons, host: feed.host, title: feed.title, index: index,
                                 side: AppDefaults.Feeds.articleIconSize)
                        Text(feed.title).lineLimit(1)
                    }
                    Text(RowTime.text(article.date)).monospacedDigit()
                    if article.starred {
                        Image(systemName: "star.fill").foregroundStyle(PiperTheme.star)
                            .accessibilityLabel("Starred")
                    }
                }
                .font(PiperTheme.ui(.caption))
                .foregroundStyle(PiperTheme.secondary)
                Text(article.title)
                    .font(PiperTheme.ui(.body, weight: article.read ? .regular : .semibold))
                    .foregroundStyle(article.read ? PiperTheme.secondary : PiperTheme.ink)
                    .lineLimit(2)
                if !article.summary.isEmpty {
                    Text(article.summary)
                        .font(PiperTheme.ui(.secondary))
                        .foregroundStyle(PiperTheme.secondary)
                        .lineLimit(2)
                }
            }
        }
        .padding(.vertical, 4)
    }
}
