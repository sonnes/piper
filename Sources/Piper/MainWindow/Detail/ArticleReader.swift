import AppKit
import Captures
import Observation
import PiperCore
import SwiftUI
import WebKit

/// The Reader tab of a link capture: the article as clean text, with the
/// highlights and questions of the capture in place.
struct ArticleReader: View {

    // MARK: - Properties

    @Bindable var model: AppModel
    let note: Note
    let url: URL
    let showWebPage: () -> Void
    @State private var loader = ArticleLoader()
    /// The line over the article that says where it opened.
    @State private var resume: String?
    @State private var pendingPosition: Task<Void, Never>?
    /// The place that waits for the save delay.
    @State private var position: (block: Int, progress: Double)?
    @State private var places = NotePlaces()

    private var children: [Note] { model.store.children(of: note.id) }
    private var reading: Reading { note.reading ?? Reading() }
    /// The scroll request for this article. A request for another article waits.
    private var scroll: ReaderScroll? { model.readerScroll.flatMap { $0.article == note.id ? $0 : nil } }

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 8) {
                Text(url.host() ?? url.absoluteString).foregroundStyle(PiperTheme.ink)
                Text(url.path()).foregroundStyle(PiperTheme.secondary)
                    .lineLimit(1).truncationMode(.middle)
                Spacer(minLength: 8)
                Text(reading.minutesLeft.map { "\($0) min left" }
                     ?? "Captured " + note.createdAt.formatted(date: .omitted, time: .shortened))
                    .foregroundStyle(PiperTheme.secondary)
                    .monospacedDigit()
            }
            .font(PiperTheme.ui(AppDefaults.ArticleReader.addressFontSize))
            .lineLimit(1)
            .padding(.horizontal, AppDefaults.ArticleReader.horizontalInset)
            .frame(height: AppDefaults.ArticleReader.addressHeight)
            ZStack(alignment: .leading) {
                Rule()
                GeometryReader { proxy in
                    Rectangle().fill(PiperTheme.accent)
                        .frame(width: proxy.size.width * min(max(reading.progress, 0), 1), height: AppDefaults.ArticleReader.progressHeight)
                }
                .frame(height: AppDefaults.ArticleReader.progressHeight)
            }
            .frame(height: AppDefaults.ArticleReader.progressHeight)
            .accessibilityHidden(true)
            if let resume {
                HStack(spacing: 10) {
                    Image(systemName: "book").foregroundStyle(PiperTheme.accent)
                    Text(resume)
                    Spacer(minLength: 8)
                    Button("Start from the top") {
                        model.readerScroll = ReaderScroll(block: 0, in: note.id)
                        self.resume = nil
                    }
                    .buttonStyle(.text)
                    Button { self.resume = nil } label: { Image(systemName: "xmark") }
                        .buttonStyle(.plain).foregroundStyle(PiperTheme.faint)
                        .accessibilityLabel("Close")
                }
                .font(PiperTheme.ui(AppDefaults.ArticleReader.resumeFontSize))
                .padding(.horizontal, AppDefaults.ArticleReader.horizontalInset)
                .padding(.vertical, AppDefaults.ArticleReader.resumeVerticalPadding)
                .background(PiperTheme.resumeFill)
                .overlay(alignment: .bottom) { Rule() }
            }
            ReaderPageView(state: loader.state, placeholder: ReaderPlaceholder(site: ArticleBadge.host(url), title: reading.title),
                           notes: payload, scroll: scroll, perform: perform, scrolled: scrolled)
                .overlay(alignment: .bottom) {
                    if case .failed = loader.state {
                        Button("Show Web Page", action: showWebPage)
                            .padding(.bottom, AppDefaults.TabIsland.clearance + AppDefaults.ArticleReader.webPageButtonMargin)
                    }
                }
        }
        .background(PiperTheme.reader)
        .onAppear { load(url) }
        .onChange(of: url) { _, url in load(url) }
        .onChange(of: loader.state) { _, state in
            if case .loaded(let article) = state { opened(article) }
        }
        .onDisappear(perform: flushPosition)
    }

    // MARK: - Reading

    private func load(_ url: URL) {
        loader.load(url, title: reading.title, pageText: model.store.pageText(for: url))
    }

    /// Records the article and picks the place where it opens: a requested
    /// highlight, the place where the reader stopped, or the newest highlight
    /// from a browser.
    private func opened(_ article: ReaderArticle) {
        let words = article.blocks.reduce(0) { $0 + $1.text.split(whereSeparator: \.isWhitespace).count }
        let minutes = max(1, Int((Double(words) / AppDefaults.ArticleReader.wordsPerMinute).rounded()))
        let start = reading
        model.store.updateReading(note.id) { reading in
            reading.title = article.title.isEmpty ? reading.title : article.title
            reading.minutes = minutes
            reading.openedAt = Date()
        }
        let children = children
        let highlights = ReadingList.highlights(in: children)
        if let scroll, let id = scroll.note, let target = children.first(where: { $0.id == id }) {
            resume = target.sources.first.flatMap { $0 == ReaderAssistant.source ? nil : "Continued from \($0), at your highlight" }
        } else if let block = start.block, block > 0 {
            model.readerScroll = ReaderScroll(block: block, in: note.id)
            resume = "Continued where you stopped"
        } else if start.block == nil, let last = highlights.max(by: { $0.createdAt < $1.createdAt }),
                  let source = last.sources.first, source != ReaderAssistant.source {
            model.readerScroll = ReaderScroll(note: last.id, in: note.id)
            resume = "Continued from \(source), at your latest highlight"
        }
    }

    /// Ends a scroll request after the page ran it, so the next drawing of the
    /// tab opens at the saved place and not at the old request.
    private func scrolled(_ request: ReaderScroll) {
        DispatchQueue.main.async {
            if model.readerScroll == request { model.readerScroll = nil }
        }
    }

    /// Saves the place in the article shortly after the scroll stops.
    private func savePosition(block: Int, progress: Double) {
        pendingPosition?.cancel()
        position = (block, progress)
        pendingPosition = Task { @MainActor in
            try? await Task.sleep(for: AppDefaults.Reading.positionSaveDelay)
            guard !Task.isCancelled else { return }
            flushPosition()
        }
    }

    /// Saves the place that waits, at once. A capture that the reader leaves
    /// keeps its last place.
    private func flushPosition() {
        pendingPosition?.cancel()
        guard let position else { return }
        self.position = nil
        model.store.updateReading(note.id) { reading in
            reading.block = position.block
            reading.progress = position.progress
            if position.progress >= AppDefaults.Reading.finishedProgress, reading.finishedAt == nil { reading.finishedAt = Date() }
        }
    }

    // MARK: - Notes

    /// The child notes, as the reader page draws them.
    private var payload: [ReaderPageNote] {
        guard case .loaded(let article) = loader.state else { return [] }
        let children = children
        let found = places.places(in: article, for: children)
        return children.compactMap { child -> ReaderPageNote? in
            let isQuestion = child.tags.contains(ReaderAssistant.questionTag)
            guard isQuestion || child.tags.contains(ReaderAssistant.highlightTag) else { return nil }
            let place = found[child.id]
            let quote = child.anchor?.quote ?? ""
            let thread = NoteThread(child.text)
            let label = thread.title.split(separator: ":", maxSplits: 1).first.map(String.init) ?? "Ask"
            let comment = isQuestion ? "" : HighlightText.comment(of: child.text, quote: child.anchor?.quote)
            let origin = [child.sources.first, child.createdAt.formatted(date: .omitted, time: .shortened)]
                .compactMap { $0 }.joined(separator: " · ")
            return ReaderPageNote(
                id: child.id.uuidString,
                kind: isQuestion ? "question" : comment.isEmpty ? "highlight" : "note",
                color: child.tags.first(where: ReaderAssistant.colors.contains) ?? ReaderAssistant.colors[0],
                block: place?.block ?? -1,
                offset: place?.offset ?? 0,
                length: ((place?.quote ?? quote) as NSString).length,
                quote: quote,
                comment: comment,
                origin: origin,
                label: label,
                tags: child.tags,
                turns: thread.turns.map { ReaderPageNote.Turn(question: $0.question, answer: $0.answer) },
                pending: model.reader.waitingNotes.contains(child.id),
                failure: model.reader.failures[child.id],
                agent: isQuestion ? model.reader.answererName(for: note.id) : "",
                tools: model.reader.toolLines[child.id] ?? ""
            )
        }
    }

    // MARK: - Actions

    private func perform(_ message: [String: Any]) {
        guard case .loaded(let article) = loader.state, let action = message["action"] as? String else { return }
        switch action {
        case "highlight":
            guard let anchor = Self.anchor(message["anchor"]) else { return }
            model.reader.highlight(anchor, color: message["color"] as? String ?? "", in: note.id)
        case "note":
            guard let anchor = Self.anchor(message["anchor"]), let text = message["text"] as? String,
                  !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }
            model.reader.highlight(anchor, color: ReaderAssistant.colors[0], in: note.id, comment: text)
        case "position":
            guard let block = message["block"] as? Int, let progress = message["progress"] as? Double else { return }
            savePosition(block: block, progress: progress)
        case "explain", "define":
            guard let anchor = Self.anchor(message["anchor"]) else { return }
            model.reader.ask(action == "explain" ? .explain : .define, about: anchor, in: note.id, article: article)
        case "ask":
            guard let anchor = Self.anchor(message["anchor"]), let question = message["question"] as? String,
                  !question.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }
            model.reader.ask(.ask(question), about: anchor, in: note.id, article: article)
        case "followup":
            guard let id = (message["id"] as? String).flatMap(UUID.init(uuidString:)),
                  let question = message["question"] as? String else { return }
            model.reader.followUp(question, on: id, in: note.id, article: article)
        case "continue":
            guard let id = (message["id"] as? String).flatMap(UUID.init(uuidString:)) else { return }
            model.reader.continueInSession(id, article: article)
        case "capture":
            guard let text = message["text"] as? String else { return }
            model.store.add(text, source: article.title, sourceURL: article.url.absoluteString, to: "Inbox", interpretSection: false)
        case "open":
            guard let id = (message["id"] as? String).flatMap(UUID.init(uuidString:)) else { return }
            model.showNote?(id)
        case "copy":
            guard let id = (message["id"] as? String).flatMap(UUID.init(uuidString:)) else { return }
            model.store.copy(id)
        default:
            break
        }
    }

    private static func anchor(_ value: Any?) -> NoteAnchor? {
        guard let value = value as? [String: Any], let quote = value["quote"] as? String,
              let block = value["block"] as? Int, let offset = value["offset"] as? Int, !quote.isEmpty else { return nil }
        return NoteAnchor(quote: quote, block: block, offset: offset)
    }
}

/// The places of the child notes in an article.
///
/// Finding a place searches the article text. The places stay until the
/// article or the anchor of a note changes.
@MainActor
final class NotePlaces {
    private var article: ReaderArticle?
    private var anchors: [UUID: NoteAnchor] = [:]
    private var found: [UUID: NoteAnchor] = [:]
    /// The number of times the places were found again. Tests read it.
    private(set) var searches = 0

    func places(in article: ReaderArticle, for children: [Note]) -> [UUID: NoteAnchor] {
        var anchors: [UUID: NoteAnchor] = [:]
        for child in children { anchors[child.id] = child.anchor }
        guard article != self.article || anchors != self.anchors else { return found }
        let texts = article.texts
        found = anchors.compactMapValues { $0.locate(in: texts) }
        self.article = article
        self.anchors = anchors
        searches += 1
        return found
    }
}

/// What the reader page shows while the article loads: the site, and the
/// title when a browser capture already gave it.
struct ReaderPlaceholder: Codable, Equatable {
    let site: String
    let title: String?
}

/// One child note as the reader page draws it: a mark, and a card for a question.
struct ReaderPageNote: Codable, Equatable {
    struct Turn: Codable, Equatable {
        let question: String?
        let answer: String
    }

    let id: String
    /// `highlight`, `note` for a highlight with a note of the reader, or `question`.
    let kind: String
    let color: String
    /// The block of the mark. -1 means that the article no longer holds the quote.
    let block: Int
    let offset: Int
    let length: Int
    let quote: String
    /// The note of the reader after the quote of a highlight.
    let comment: String
    /// Where and when the reader made the note, such as "Safari · 9:41 AM".
    let origin: String
    let label: String
    let tags: [String]
    let turns: [Turn]
    let pending: Bool
    let failure: String?
    /// The model and the agent that answer a question, such as "Haiku · Claude Code".
    let agent: String
    /// The tools that the last answer used, in one line. Empty when it used none.
    let tools: String
}

// MARK: - Loading

/// Loads a page out of sight and reads its article text.
@MainActor @Observable
final class ArticleLoader: NSObject {

    enum State: Equatable {
        case loading
        case loaded(ReaderArticle)
        case failed(String)
    }

    // MARK: - Properties

    private(set) var state = State.loading
    @ObservationIgnored private var webView: WKWebView?
    @ObservationIgnored private var requested: URL?
    @ObservationIgnored private var timeout: Task<Void, Never>?
    @ObservationIgnored private var extracting = false
    @ObservationIgnored private var fallback: ReaderArticle?
    /// Articles read in this launch, so a second visit opens at once.
    private static var cache: [URL: ReaderArticle] = [:]

    // MARK: - Loading

    /// Loads the article of a page. The page text that a browser showed is
    /// the article when the page does not load, or when the load gives much
    /// less text, as a page behind a login does.
    func load(_ url: URL, title: String? = nil, pageText: String? = nil) {
        guard requested != url else { return }
        requested = url
        fallback = pageText.flatMap { ReaderArticle(url: url, title: title, pageText: $0) }
        if let article = Self.cache[url] {
            state = .loaded(article)
            return
        }
        guard CaptureLinks.isWebURL(url) else {
            state = .failed("Piper can read only web pages.")
            return
        }
        state = .loading
        extracting = false
        let view = WKWebView(frame: NSRect(origin: .zero, size: AppDefaults.ArticleReader.loaderSize))
        view.navigationDelegate = self
        webView = view
        view.load(URLRequest(url: url))
        timeout?.cancel()
        timeout = Task { [weak self] in
            try? await Task.sleep(for: .seconds(AppDefaults.ArticleReader.loadTimeout))
            guard !Task.isCancelled, let self, self.state == .loading else { return }
            await self.extract()
        }
    }

    private func extract() async {
        guard !extracting, let view = webView, let url = requested else { return }
        extracting = true
        timeout?.cancel()
        // Some pages draw their text with a script after the load ends.
        try? await Task.sleep(for: .milliseconds(AppDefaults.ArticleReader.settleMilliseconds))
        do {
            let result = try await view.evaluateJavaScript(Self.script, in: nil, contentWorld: .defaultClient)
            guard let json = result as? String else { throw PiperError("Cannot read this page.") }
            let raw = try JSONDecoder().decode(RawArticle.self, from: Data(json.utf8))
            let blocks = raw.blocks.filter { !$0.text.isEmpty }
            guard blocks.count >= 2 || blocks.contains(where: { $0.text.count > 200 }) else {
                throw PiperError("Piper cannot find the article text on this page.")
            }
            var article = ReaderArticle(url: url, site: raw.site, title: raw.title, author: raw.author, blocks: blocks)
            if let fallback, fallback.words > article.words * 5 / 2 { article = fallback }
            Self.cache[url] = article
            if requested == url { state = .loaded(article) }
        } catch {
            if requested == url { state = fallback.map(State.loaded) ?? .failed(error.localizedDescription) }
        }
        webView?.navigationDelegate = nil
        webView?.stopLoading()
        webView = nil
    }

    private func failed(_ error: Error) {
        let error = error as NSError
        guard error.domain != NSURLErrorDomain || error.code != NSURLErrorCancelled else { return }
        timeout?.cancel()
        state = fallback.map(State.loaded) ?? .failed(error.localizedDescription)
        webView = nil
    }

    private struct RawArticle: Decodable {
        let site: String
        let title: String
        let author: String
        let blocks: [ReaderArticle.Block]
    }

    /// Reads an article container before broader page containers.
    /// It runs in an isolated world, so the page scripts cannot see it.
    static let script = """
    (() => {
      const text = el => (el.innerText || '').replace(/\\s+/g, ' ').trim();
      const excluded = 'nav, header, footer, aside, form, figure, [role=navigation], [hidden], [aria-hidden=true]';
      const length = el => [...el.querySelectorAll('p')].filter(p => !p.closest(excluded)).reduce((n, p) => n + text(p).length, 0);
      let root = null, best = 0;
      for (const el of document.querySelectorAll('article, [itemprop=articleBody], .post-content, .entry-content, .article-body, .markdown-body')) {
        if (el.closest(excluded)) continue;
        const n = length(el);
        if (n > best) { root = el; best = n; }
      }
      if (!root) {
        for (const el of document.querySelectorAll('main, [role=main], #content')) {
          const n = length(el);
          if (n > best) { root = el; best = n; }
        }
        const parents = new Map();
        for (const p of document.querySelectorAll('p')) {
          if (p.closest(excluded)) continue;
          const parent = p.parentElement;
          if (parent) parents.set(parent, (parents.get(parent) || 0) + text(p).length);
        }
        for (const [el, n] of parents) if (n > best * 1.5) { root = el; best = n; }
      }
      root = root || document.body;
      const meta = name => document.querySelector(`meta[property="${name}"], meta[name="${name}"]`)?.content?.trim() || '';
      // The first heading is the title when the document title names it, as in "Title | Site".
      const heading = text(document.querySelector('h1') || document.createElement('i'));
      const title = meta('og:title') || (heading && document.title.includes(heading) ? heading : document.title.trim()) || heading;
      const kinds = { H1: 'heading', H2: 'heading', H3: 'subheading', H4: 'subheading', LI: 'item', BLOCKQUOTE: 'quote', PRE: 'code' };
      const blocks = [];
      for (const el of root.querySelectorAll('h1, h2, h3, h4, p, li, blockquote, pre')) {
        if (el.closest(excluded)) continue;
        if (el.parentElement?.closest('p, li, blockquote, pre')) continue;
        const value = el.tagName === 'PRE' ? (el.innerText || '').trim() : text(el);
        if (!value || (el.tagName === 'H1' && value === title)) continue;
        blocks.push({ kind: kinds[el.tagName] || 'paragraph', text: value });
      }
      // An old page breaks its text with <br> in place of paragraphs.
      if (blocks.length === 0) {
        const copy = root.cloneNode(true);
        copy.querySelectorAll(excluded + ', script, style').forEach(el => el.remove());
        copy.querySelectorAll('br').forEach(el => el.replaceWith('\\n\\n'));
        copy.querySelectorAll('div, section').forEach(el => el.append('\\n\\n'));
        for (const chunk of (copy.textContent || '').split(/\\n\\s*\\n/)) {
          const value = chunk.replace(/\\s+/g, ' ').trim();
          if (value.length >= 40 && value !== title) blocks.push({ kind: 'paragraph', text: value });
        }
      }
      return JSON.stringify({
        site: meta('og:site_name') || location.hostname.replace(/^www\\./, ''),
        title, author: meta('author'), blocks
      });
    })()
    """
}

extension ArticleLoader: WKNavigationDelegate {
    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        Task { await extract() }
    }

    func webView(_ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!, withError error: Error) {
        failed(error)
    }

    func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) {
        failed(error)
    }
}

// MARK: - Page

/// The reader page in a web view. Piper draws the article and the notes, and
/// the page reports each action of the reader.
private struct ReaderPageView: NSViewRepresentable {
    let state: ArticleLoader.State
    let placeholder: ReaderPlaceholder
    let notes: [ReaderPageNote]
    let scroll: ReaderScroll?
    let perform: ([String: Any]) -> Void
    /// Reports a scroll request that the page ran.
    let scrolled: (ReaderScroll) -> Void

    func makeCoordinator() -> Coordinator { Coordinator() }

    func makeNSView(context: Context) -> WKWebView {
        let configuration = WKWebViewConfiguration()
        configuration.userContentController.add(context.coordinator, name: "piper")
        configuration.websiteDataStore = .nonPersistent()
        let view = WKWebView(frame: .zero, configuration: configuration)
        view.navigationDelegate = context.coordinator
        view.underPageBackgroundColor = PiperTheme.readerNS
        view.setAccessibilityLabel("Article")
        context.coordinator.view = view
        if let page = PiperTheme.resources.url(forResource: "reader", withExtension: "html") {
            context.coordinator.page = page
            view.loadFileURL(page, allowingReadAccessTo: page.deletingLastPathComponent())
        }
        return view
    }

    func updateNSView(_ view: WKWebView, context: Context) {
        context.coordinator.perform = perform
        context.coordinator.scrolled = scrolled
        context.coordinator.placeholder = placeholder
        context.coordinator.show(state, notes: notes, scroll: scroll)
    }

    static func dismantleNSView(_ view: WKWebView, coordinator: Coordinator) {
        view.configuration.userContentController.removeScriptMessageHandler(forName: "piper")
        view.navigationDelegate = nil
    }

    @MainActor
    final class Coordinator: NSObject, WKScriptMessageHandler, WKNavigationDelegate {
        weak var view: WKWebView?
        var page: URL?
        var perform: ([String: Any]) -> Void = { _ in }
        var scrolled: (ReaderScroll) -> Void = { _ in }
        var placeholder = ReaderPlaceholder(site: "", title: nil)
        private var ready = false
        private var shownState: ArticleLoader.State?
        private var shownNotes: [ReaderPageNote]?
        private var shownScroll: ReaderScroll?
        private var wanted: (ArticleLoader.State, [ReaderPageNote], ReaderScroll?)?

        func show(_ state: ArticleLoader.State, notes: [ReaderPageNote], scroll: ReaderScroll?) {
            wanted = (state, notes, scroll)
            guard ready, let view else { return }
            if state != shownState {
                shownState = state
                shownNotes = nil
                switch state {
                case .loading:
                    call(view, "loading", placeholder)
                case .failed(let reason):
                    call(view, "message", [String(localized: "Cannot Read Article"), reason])
                case .loaded(let article):
                    call(view, "render", article)
                }
            }
            guard case .loaded = state else { return }
            if notes != shownNotes {
                shownNotes = notes
                call(view, "setNotes", notes)
            }
            if let scroll, scroll != shownScroll {
                shownScroll = scroll
                if let note = scroll.note { call(view, "scrollTo", note.uuidString) }
                else { call(view, "scrollToBlock", scroll.block ?? 0) }
                scrolled(scroll)
            }
        }

        private func call(_ view: WKWebView, _ function: String, _ value: some Encodable) {
            guard let data = try? JSONEncoder().encode(value) else { return }
            let argument = String(decoding: data, as: UTF8.self)
            let script = function == "message"
                ? "window.piper.message(...\(argument))"
                : "window.piper.\(function)(\(argument))"
            view.evaluateJavaScript(script)
        }

        func userContentController(_ controller: WKUserContentController, didReceive message: WKScriptMessage) {
            guard message.frameInfo.isMainFrame, message.frameInfo.request.url == page,
                  let body = message.body as? [String: Any] else { return }
            if body["action"] as? String == "ready" {
                ready = true
                shownState = nil
                if let wanted { show(wanted.0, notes: wanted.1, scroll: wanted.2) }
            } else {
                perform(body)
            }
        }

        /// A crash of the web content process leaves a blank view. The page
        /// loads again and draws the article when it reports that it is ready.
        func webViewWebContentProcessDidTerminate(_ webView: WKWebView) {
            ready = false
            shownState = nil
            shownNotes = nil
            shownScroll = nil
            guard let page else { return }
            webView.loadFileURL(page, allowingReadAccessTo: page.deletingLastPathComponent())
        }

        /// The page is local. Nothing navigates away from it.
        func webView(_ webView: WKWebView, decidePolicyFor navigationAction: WKNavigationAction,
                     decisionHandler: @escaping (WKNavigationActionPolicy) -> Void) {
            decisionHandler(navigationAction.request.url == page ? .allow : .cancel)
        }
    }
}
