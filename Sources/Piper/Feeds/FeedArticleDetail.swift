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
    @Environment(\.paperDesk) private var desk

    private var url: URL? { URL(string: article.url) }
    private var kept: Note? { PaperItem.keptNote(of: article, in: model.store) }

    var body: some View {
        if let kept {
            NoteDetail(model: model, note: kept)
                .id(kept.id)
        } else if let url {
            Group {
                switch tab {
                case .web:
                    NoteWebReader(url: url, store: model.store)
                case .reader, .notes:
                    ReaderTabPage(model: model, state: loader.state, url: url, title: article.title,
                                  perform: perform, showWebPage: { tab = .web })
                        .onAppear { loader.load(url, title: article.title, pageText: nil) }
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

    /// Runs an action of the reader page. A highlight or a question keeps the
    /// article first. The pane then shows the capture.
    private func perform(_ action: ReaderAction) {
        guard case .loaded(let page) = loader.state else { return }
        ReaderMarks.perform(action, store: model.store, reader: model.reader, messages: model.messages, article: page,
                            open: { desk?.open($0) }) {
            guard let note = try model.articleActions.capture([article]).first else {
                throw PiperError("Piper can save only web pages.")
            }
            return note.id
        }
    }
}
