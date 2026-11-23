import Captures
import Feeds
import PiperCore
import SwiftUI

/// A feed article in a reader paper, in the same reader as a link capture.
///
/// After Keep, the article is a link capture, and the pane shows that capture
/// with its Reader, Web, and Notes tabs. Before Keep, the pane shows the
/// Reader and Web tabs. A highlight or a question keeps the article first,
/// because a note needs a link capture to hold it.
struct FeedArticleDetail: View {
    @Bindable var model: AppModel
    let article: Article

    @State private var loader = ArticleLoader()
    @State private var tab = ArticleTab.reader

    private var url: URL? { URL(string: article.url) }
    private var kept: Note? { url.flatMap(model.store.article(for:)) }

    var body: some View {
        if let kept {
            NoteDetail(model: model, note: kept)
                .id(kept.id)
        } else if let url {
            Group {
                switch tab {
                case .web:
                    NoteWebReader(url: url) { text, title, url in
                        model.store.add(text, source: title, sourceURL: url.absoluteString,
                                        to: Note.inbox, interpretSection: false)
                    }
                case .reader, .notes:
                    reader(url)
                }
            }
            .background(PiperTheme.paper)
            .overlay(alignment: .bottom) {
                TabIsland(selection: $tab, cardPresented: model.sessionPresentation == .card, showsNotes: false)
            }
        } else {
            EmptyPane(title: "Cannot Read Article", detail: "The article has no valid link.")
        }
    }

    private func reader(_ url: URL) -> some View {
        ReaderPageView(state: loader.state,
                       placeholder: ReaderPlaceholder(site: Site(url)?.key ?? url.absoluteString, title: article.title),
                       notes: [], scroll: nil, perform: perform, scrolled: { _ in },
                       attach: { model.readerPages.add($0) })
            .overlay(alignment: .bottom) {
                if case .failed = loader.state {
                    Button("Show Web Page") { tab = .web }
                        .padding(.bottom, AppDefaults.TabIsland.clearance + AppDefaults.ArticleReader.webPageButtonMargin)
                }
            }
            .background(PiperTheme.paper)
            .onAppear { loader.load(url, title: article.title, pageText: nil) }
    }

    /// Runs an action of the reader page. A highlight or a question keeps the
    /// article in Inbox first. The pane then shows the capture.
    private func perform(_ message: [String: Any]) {
        guard case .loaded(let page) = loader.state, let url else { return }
        ReaderMarks.perform(message, store: model.store, reader: model.reader, article: page,
                            open: { model.showNote?($0) }) {
            model.store.saveArticle(url, title: article.title, source: model.feeds.feed(article.feedID)?.title)?.id
        }
    }
}
