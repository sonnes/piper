import PiperCore
import SwiftUI

/// The Reader tab of a link capture or of a feed article: the reader page,
/// with Show Web Page over it when the article does not load.
struct ReaderTabPage: View {
    let model: AppModel
    let state: ArticleLoader.State
    let url: URL
    /// The title that the page shows while the article loads.
    let title: String?
    var notes: [ReaderPageNote] = []
    var scroll: ReaderScroll?
    let perform: (ReaderAction) -> Void
    var positioned: (Int, Double) -> Void = { _, _ in }
    var scrolled: (ReaderScroll) -> Void = { _ in }
    let showWebPage: () -> Void
    @Environment(\.attachReaderPage) private var attachReaderPage

    var body: some View {
        ReaderPageView(messages: model.messages, state: state,
                       placeholder: ReaderPlaceholder(site: Site(url)?.key ?? url.absoluteString, title: title),
                       notes: notes, scroll: scroll, perform: perform, positioned: positioned, scrolled: scrolled,
                       attach: attachReaderPage)
            .overlay(alignment: .bottom) {
                if case .failed = state {
                    Button("Show Web Page", action: showWebPage)
                        .padding(.bottom, TabIslandMetrics.clearance + Metrics.webPageButtonMargin)
                }
            }
    }
}

extension EnvironmentValues {
    /// Receives the reader page of a paper, so that the paper can send keys to it and scroll it.
    @Entry var attachReaderPage: (WebPageBridge) -> Void = { _ in }
}

extension ReaderTabPage {
    enum Metrics {
        /// The space between the Show Web Page button and the tabs under it.
        static let webPageButtonMargin: CGFloat = 16
    }
}
