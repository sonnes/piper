import Captures
import Feeds
import SwiftUI

/// A feed article in the detail pane: its actions, and the article as clean
/// text in the reader page of a link capture.
struct FeedArticleDetail: View {
    @Bindable var model: AppModel
    let article: Article

    @State private var loader = ArticleLoader()

    private var feeds: FeedStore { model.feeds }
    /// The current marks of the article. The list can change them.
    private var current: Article {
        _ = feeds.revision
        return feeds.article(article.id) ?? article
    }
    private var url: URL? { URL(string: article.url) }
    private var kept: Bool { url.flatMap(model.store.article(for:)) != nil }

    var body: some View {
        VStack(spacing: 0) {
            toolbar
            Rule()
            if let url {
                ReaderPageView(state: loader.state,
                               placeholder: ReaderPlaceholder(site: ArticleBadge.host(url), title: article.title),
                               notes: [], scroll: nil, perform: perform, scrolled: { _ in }, attach: { _ in })
                    .overlay(alignment: .bottom) {
                        if case .failed = loader.state {
                            Button("Open in Browser") { NSWorkspace.shared.open(url) }
                                .padding(.bottom, AppDefaults.Feeds.detailButtonMargin)
                        }
                    }
                    .onAppear { loader.load(url, title: article.title, pageText: nil) }
                    .onChange(of: article.id) { _, _ in loader.load(url, title: article.title, pageText: nil) }
            } else {
                EmptyPane(title: "Cannot Read Article", detail: "The article has no valid link.")
            }
        }
        .background(PiperTheme.reader)
    }

    private var toolbar: some View {
        let article = current
        return HStack(spacing: 14) {
            Text(feeds.feed(article.feedID)?.title ?? "")
                .foregroundStyle(PiperTheme.secondary)
                .lineLimit(1)
            Spacer(minLength: 8)
            Button(kept ? "Kept" : "Keep") { keep() }
                .buttonStyle(.text)
                .disabled(kept)
                .help("Save the article to Inbox (I)")
            Button { feeds.setStarred(!article.starred, article) } label: {
                Label(article.starred ? "Starred" : "Star", systemImage: article.starred ? "star.fill" : "star")
            }
            .buttonStyle(.plain)
            .foregroundStyle(article.starred ? PiperTheme.star : PiperTheme.secondary)
            .help("Star (S)")
            Button { feeds.setRead(!article.read, [article]) } label: {
                Label(article.read ? "Mark as Unread" : "Mark as Read", systemImage: article.read ? "circle" : "circle.fill")
            }
            .buttonStyle(.plain)
            .foregroundStyle(PiperTheme.secondary)
            .help("Mark as Read or Unread (R)")
            Button { if let url { NSWorkspace.shared.open(url) } } label: {
                Label("Open in Browser", systemImage: "safari")
            }
            .buttonStyle(.plain)
            .foregroundStyle(PiperTheme.secondary)
            .help("Open in Browser (B)")
        }
        .labelStyle(.iconOnly)
        .font(PiperTheme.ui(.secondary))
        .padding(.horizontal, 16)
        .frame(height: AppDefaults.Feeds.headerHeight)
        .background(PiperTheme.page)
    }

    @discardableResult
    private func keep() -> Note? {
        guard let url else { return nil }
        return model.store.saveArticle(url, title: article.title, source: feeds.feed(article.feedID)?.title)
    }

    /// Runs an action of the reader page. A highlight or a question keeps the
    /// article in Inbox first, because a note needs a link capture to hold it.
    private func perform(_ message: [String: Any]) {
        guard case .loaded(let page) = loader.state else { return }
        ReaderMarks.perform(message, model: model, article: page) { keep()?.id }
    }
}
