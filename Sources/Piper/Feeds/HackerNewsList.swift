import Feeds
import PiperCore
import SwiftUI

/// The Hacker News tab: the stories of the front page of Hacker News.
///
/// Return opens the selected story on a paper, C shows its comments, K keeps
/// it, and B opens it in the browser. Piper saves nothing until the reader keeps a story.
struct HackerNewsList: View {
    @Bindable var hackerNews: HackerNewsModel
    @Bindable var model: AppModel
    /// Sets the keys of the list on the feed paper.
    var setKeys: ([PaperKey]) -> Void = { _ in }

    @State private var scrollTarget: Int?
    @Environment(\.paperDesk) private var desk

    private var actions: ArticleActions { model.articleActions }

    var body: some View {
        VStack(spacing: 0) {
            header
            if let error = hackerNews.error {
                Text(error).font(PiperTheme.paperUI(.body)).foregroundStyle(PiperTheme.paperMuted)
                    .fixedSize(horizontal: false, vertical: true)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, HintStrip.Metrics.footMargin)
                    .padding(.top, Metrics.messageTop)
            }
            if hackerNews.stories.isEmpty {
                PaperEmpty(symbol: "newspaper", title: hackerNews.loading ? "Loading Hacker News" : "No Stories")
            } else {
                list
            }
        }
        .onAppear {
            hackerNews.loadIfEmpty()
            setKeys(keys)
        }
        .onChange(of: hackerNews.stories.map(\.id)) { _, _ in setKeys(keys) }
        .onChange(of: hackerNews.selectedID) { _, _ in setKeys(keys) }
    }

    // MARK: - Parts

    private var header: some View {
        HStack(spacing: Metrics.headerSpacing) {
            Text("Top stories").foregroundStyle(PiperTheme.paperFaint)
            Spacer(minLength: Metrics.headerSpacerMin)
            if hackerNews.loading {
                ProgressView().controlSize(.small).frame(width: PaperRowMetrics.rowActionSize)
            } else {
                RowAction(symbol: "arrow.clockwise", title: "Refresh", action: hackerNews.refresh)
            }
        }
        .font(PiperTheme.paperUI(.body, weight: .medium))
        .padding(.horizontal, HintStrip.Metrics.footMargin)
        .padding(.top, Metrics.headerTop)
    }

    private var list: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 0) {
                    ForEach(hackerNews.stories) { story in
                        StoryRow(story: story, favicons: model.favicons, selected: story.id == hackerNews.selectedID,
                                 kept: actions.isKept(story.article), keep: { actions.keep([story.article]) },
                                 showComments: { showComments(story) }) {
                            open(story)
                        }
                        .id(story.id)
                        .contextMenu { menu(for: story) }
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

    @ViewBuilder
    private func menu(for story: HackerNews.Story) -> some View {
        Button("Open as Paper") { open(story) }
        Button("Show Comments") { showComments(story) }
        Divider()
        Button("Keep") { actions.keep([story.article]) }.disabled(actions.isKept(story.article))
        Button("Open in Browser") { actions.openInBrowser(story.article) }
        Button("Open on Hacker News") { actions.openOnHackerNews(story) }
        Button("Copy Link") { actions.copyLink(story.article) }
    }

    // MARK: - Actions

    /// Selects the story and opens it on a reader paper. An Ask HN post has
    /// no link, so its comments open in place of the story.
    private func open(_ story: HackerNews.Story) {
        hackerNews.selectedID = story.id
        desk?.open(story.url == nil ? .comments(story) : .story(story))
    }

    private func showComments(_ story: HackerNews.Story) {
        hackerNews.selectedID = story.id
        desk?.open(.comments(story))
    }

    /// The keys of the list: the arrows move the selection, Return opens the
    /// story as a paper, C shows its comments, and K and B act on the selected story.
    private var keys: [PaperKey] {
        let hackerNews = hackerNews
        return [
            PaperKey(key: .up, title: "move") { move(-1) },
            PaperKey(key: .down, title: "move") { move(1) },
            PaperKey(key: .enter, title: "open as a paper", isOn: { hackerNews.selected != nil }) {
                if let selected = hackerNews.selected { open(selected) }
            },
            PaperKey(key: CommandKey("c", []), title: "comments", isOn: { hackerNews.selected != nil }) {
                if let selected = hackerNews.selected { showComments(selected) }
            }
        ] + PaperKey.articleKeys(actions: actions) { hackerNews.selected?.article }
    }

    private func move(_ delta: Int) {
        guard let id = hackerNews.stories.map(\.id).step(from: hackerNews.selectedID, by: delta) else { return }
        hackerNews.selectedID = id
        scrollTarget = id
    }
}

extension HackerNewsList {
    enum Metrics {
        static let messageTop: CGFloat = 8
        static let headerTop: CGFloat = 8
        /// The space between the label of the list and its buttons.
        static let headerSpacing: CGFloat = 14
        static let headerSpacerMin: CGFloat = 8
    }
}

/// One story: the icon of the site of its link, the title, and the points,
/// the author, and the host. Its comment button shows the count of comments.
private struct StoryRow: View {
    let story: HackerNews.Story
    let favicons: FaviconStore
    let selected: Bool
    let kept: Bool
    let keep: () -> Void
    let showComments: () -> Void
    let action: () -> Void

    private var host: String { story.url.flatMap(URL.init(string:)).flatMap(Site.init)?.key ?? "news.ycombinator.com" }

    var body: some View {
        PaperRow(item: story.url == nil ? .comments(story) : .story(story), selected: selected,
                 time: RowTime.text(story.time), action: action) {
            SiteIcon(favicons: favicons, host: host, title: story.title)
        } content: {
            VStack(alignment: .leading, spacing: 0) {
                PaperRowTitle(text: Text(story.title), bold: false)
                PaperRowMeta {
                    Text(["\(story.points) points", story.author, host].joined(separator: " · "))
                }
            }
        } actions: {
            Button(action: showComments) {
                Label("\(story.comments)", systemImage: "bubble.left")
                    .labelStyle(.titleAndIcon)
                    .font(PiperTheme.paperUI(.body, weight: .medium))
                    .foregroundStyle(PiperTheme.paperMuted)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .help("Show the comments · C")
            .accessibilityLabel("\(story.comments) comments")
            RowAction(symbol: kept ? "star.fill" : "star", title: kept ? "Kept" : "Keep · K",
                      tint: PiperTheme.star, action: keep)
                .disabled(kept)
        }
    }
}
