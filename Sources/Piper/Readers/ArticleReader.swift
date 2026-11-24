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
    @Environment(\.paperDesk) private var desk

    private var children: [Note] { model.store.children(of: note.id) }
    private var reading: Reading { note.reading ?? Reading() }
    /// The scroll request for this article. A request for another article waits.
    private var scroll: ReaderScroll? { model.readerScroll.flatMap { $0.article == note.id ? $0 : nil } }

    var body: some View {
        VStack(spacing: 0) {
            if let resume {
                HStack(spacing: 12) {
                    Text(resume).foregroundStyle(PiperTheme.paperMuted)
                    Spacer(minLength: 8)
                    Button("Start from the top") {
                        model.readerScroll = ReaderScroll(block: 0, in: note.id)
                        self.resume = nil
                    }
                    .buttonStyle(.plain).fontWeight(.medium).foregroundStyle(PiperTheme.brand)
                    Button { self.resume = nil } label: { Image(systemName: "xmark") }
                        .buttonStyle(.plain).foregroundStyle(PiperTheme.paperFaint)
                        .accessibilityLabel("Close")
                }
                .font(PiperTheme.paperUI(.body))
                .padding(.horizontal, Metrics.horizontalInset)
                .padding(.vertical, Metrics.resumeVerticalPadding)
                .background(PiperTheme.paperTint, in: RoundedRectangle(cornerRadius: PaperRowMetrics.rowRadius, style: .continuous))
                .padding(.horizontal, Metrics.resumeMargin)
            }
            ReaderTabPage(model: model, state: loader.state, url: url, title: reading.title, notes: payload, scroll: scroll,
                          perform: perform, positioned: { savePosition(block: $0, progress: $1) }, scrolled: scrolled,
                          showWebPage: showWebPage)
        }
        .background(PiperTheme.paper)
        .onAppear { load(url) }
        .onChange(of: url) { _, url in load(url) }
        .onChange(of: loader.state) { _, state in
            if case .loaded(let article) = state { opened(article) }
        }
        .onDisappear(perform: flushPosition)
    }

    // MARK: - Reading

    private func load(_ url: URL) {
        do {
            loader.load(url, title: reading.title, pageText: try model.store.pageText(for: url))
        } catch {
            model.messages.report(error)
            loader.load(url, title: reading.title, pageText: nil)
        }
    }

    /// Records the article and picks the place where it opens: a requested
    /// highlight, the place where the reader stopped, or the newest highlight
    /// from a browser.
    private func opened(_ article: ReaderArticle) {
        let minutes = ReadingTime.minutes(words: article.words)
        let start = reading
        do {
            try model.store.updateReading(note.id) { reading in
                reading.title = article.title.isEmpty ? reading.title : article.title
                reading.minutes = minutes
                reading.openedAt = Date()
            }
        } catch { model.messages.report(error) }
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
            try? await Task.sleep(for: Metrics.positionSaveDelay)
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
        do {
            try model.store.updateReading(note.id) { reading in
                reading.block = position.block
                reading.progress = position.progress
                if position.progress >= Metrics.finishedProgress, reading.finishedAt == nil { reading.finishedAt = Date() }
            }
        } catch { model.messages.report(error) }
    }

    // MARK: - Notes

    /// The child notes, as the reader page draws them.
    private var payload: [ReaderPageNote] {
        guard case .loaded(let article) = loader.state else { return [] }
        return ReaderMarks.payload(store: model.store, reader: model.reader, parent: note.id, article: article, places: places)
    }

    // MARK: - Actions

    private func perform(_ action: ReaderAction) {
        guard case .loaded(let article) = loader.state else { return }
        ReaderMarks.perform(action, store: model.store, reader: model.reader, messages: model.messages, article: article,
                            open: { desk?.open($0) }) { note.id }
    }
}

/// The Reader tab of a link capture.
extension ArticleReader {
    enum Metrics {
        /// The distance that Up Arrow or Down Arrow scrolls the Reader tab.
        static let arrowScrollStep: CGFloat = 40
        /// Seconds before Piper reads a page that has not finished loading.
        static let loadTimeout: Double = 20
        /// The wait after a load, for a page that draws its text with a script.
        static let settleMilliseconds = 300
        /// The size of the hidden web view that loads a page.
        static let loaderSize = NSSize(width: 1024, height: 768)
        static let horizontalInset: CGFloat = 16
        /// The line over the article that says where it opened.
        static let resumeVerticalPadding: CGFloat = 10
        static let resumeMargin: CGFloat = 40
        /// The wait after the last scroll before Piper saves the position.
        static let positionSaveDelay = Duration.milliseconds(800)
        /// The part of the article above the screen that counts as finished.
        static let finishedProgress = 0.97
    }
}

/// The marks and the actions of a reader page.
@MainActor
enum ReaderMarks {

    /// The child notes of the parent, as the reader page draws them.
    static func payload(store: CaptureStore, reader: ReaderAssistant, parent: UUID, article: ReaderArticle,
                        places: NotePlaces) -> [ReaderPageNote] {
        let children = store.children(of: parent)
        let found = places.places(in: article, for: children)
        return children.compactMap { child -> ReaderPageNote? in
            let isQuestion = child.has(.question)
            guard isQuestion || child.has(.highlight) else { return nil }
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
                turns: thread.turns.map { ReaderPageNote.Turn(question: $0.question, answer: $0.answer) },
                pending: reader.waitingNotes.contains(child.id),
                failure: reader.failures[child.id],
                agent: isQuestion ? reader.answererName(for: parent) : "",
                tools: reader.toolLines[child.id] ?? ""
            )
        }
    }

    /// Runs an action of the reader, and shows its error. The open function
    /// opens a paper. The parent function adds the parent note when a page has
    /// none yet.
    static func perform(_ action: ReaderAction, store: CaptureStore, reader: ReaderAssistant, messages: Messages,
                        article: ReaderArticle, open: (PaperItem) -> Void, parent: () throws -> UUID) {
        do {
            switch action {
            case .highlight(let anchor, let color):
                guard !anchor.quote.isEmpty else { return }
                try reader.highlight(anchor, color: color, in: parent())
            case .note(let anchor, let text):
                guard !anchor.quote.isEmpty, !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }
                try reader.highlight(anchor, color: ReaderAssistant.colors[0], in: parent(), comment: text)
            case .explain(let anchor):
                guard !anchor.quote.isEmpty else { return }
                try reader.ask(.explain, about: anchor, in: parent(), article: article)
            case .define(let anchor):
                guard !anchor.quote.isEmpty else { return }
                try reader.ask(.define, about: anchor, in: parent(), article: article)
            case .ask(let anchor, let question):
                guard !anchor.quote.isEmpty, !question.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }
                try reader.ask(.ask(question), about: anchor, in: parent(), article: article)
            case .followup(let id, let question):
                try reader.followUp(question, on: id, in: parent(), article: article)
            case .continue(let id):
                reader.continueInSession(id, article: article)
            case .capture(let text):
                let note = try store.add(text, section: Note.inbox, source: article.title, sourceURL: article.url.absoluteString)
                messages.show("Saved to \(note.section)")
            case .open(let id):
                open(.note(id))
            case .copy(let id):
                guard let note = store.notes.first(where: { $0.id == id }) else { return }
                messages.copy(note.text)
            }
        } catch {
            messages.report(error)
        }
    }
}

/// An action of the selection bar or of a margin card. Both pages send these
/// actions. See `MarkAction` in `web/src/bridge.ts`.
enum ReaderAction: Decodable, Equatable {
    case highlight(NoteAnchor, color: String)
    case note(NoteAnchor, text: String)
    case explain(NoteAnchor)
    case define(NoteAnchor)
    case ask(NoteAnchor, question: String)
    case followup(id: UUID, question: String)
    case `continue`(id: UUID)
    case capture(text: String)
    case open(id: UUID)
    case copy(id: UUID)

    private enum Key: String, CodingKey { case action, anchor, color, text, question, id }

    init(from decoder: Decoder) throws {
        let values = try decoder.container(keyedBy: Key.self)
        let anchor = { try values.decode(NoteAnchor.self, forKey: .anchor) }
        let id = { try values.decode(UUID.self, forKey: .id) }
        let string = { (key: Key) in try values.decode(String.self, forKey: key) }
        let action = try string(.action)
        switch action {
        case "highlight": self = .highlight(try anchor(), color: try string(.color))
        case "note": self = .note(try anchor(), text: try string(.text))
        case "explain": self = .explain(try anchor())
        case "define": self = .define(try anchor())
        case "ask": self = .ask(try anchor(), question: try string(.question))
        case "followup": self = .followup(id: try id(), question: try string(.question))
        case "continue": self = .continue(id: try id())
        case "capture": self = .capture(text: try string(.text))
        case "open": self = .open(id: try id())
        case "copy": self = .copy(id: try id())
        default:
            throw DecodingError.dataCorruptedError(forKey: .action, in: values, debugDescription: "Unknown action \(action).")
        }
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
        guard url.isWeb else {
            state = .failed("Piper can read only web pages.")
            return
        }
        state = .loading
        extracting = false
        let view = WKWebView(frame: NSRect(origin: .zero, size: ArticleReader.Metrics.loaderSize))
        view.navigationDelegate = self
        webView = view
        view.load(URLRequest(url: url))
        timeout?.cancel()
        timeout = Task { [weak self] in
            try? await Task.sleep(for: .seconds(ArticleReader.Metrics.loadTimeout))
            guard !Task.isCancelled, let self, self.state == .loading else { return }
            await self.extract()
        }
    }

    private func extract() async {
        guard !extracting, let view = webView, let url = requested else { return }
        extracting = true
        timeout?.cancel()
        // Some pages draw their text with a script after the load ends.
        try? await Task.sleep(for: .milliseconds(ArticleReader.Metrics.settleMilliseconds))
        do {
            let result = try await view.evaluateJavaScript(Self.script, in: nil, contentWorld: .defaultClient)
            guard let json = result as? String else { throw PiperError("Cannot read this page.") }
            let raw = try JSONDecoder().decode(RawArticle.self, from: Data(json.utf8))
            let blocks = raw.blocks.filter { !$0.text.isEmpty || $0.src != nil || $0.rows != nil }
            let texts = blocks.filter { !$0.text.isEmpty }
            guard texts.count >= 2 || texts.contains(where: { $0.text.count > 200 }) else {
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
      const excluded = 'nav, header, footer, aside, form, [role=navigation], [hidden], [aria-hidden=true]';
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
      const web = value => {
        try { const url = new URL(value || '', location.href); return /^https?:$/.test(url.protocol) ? url.href : ''; }
        catch { return ''; }
      };
      // The caption of a figure belongs to the first image, video, or frame in it.
      const caption = el => {
        const figure = el.closest('figure');
        if (!figure || figure.querySelector('img, video, iframe') !== el) return '';
        return text(figure.querySelector('figcaption') || document.createElement('i'));
      };
      // A table of data holds only text. Old pages lay out their text in tables.
      const dataTable = table => table.rows.length >= 2 && !table.querySelector('table, p, pre, img, h1, h2, h3, h4');
      // A lazy image keeps its address in a data attribute until it scrolls into view.
      const imageSource = img => {
        const current = img.currentSrc || img.getAttribute('src') || '';
        const lazy = img.getAttribute('data-src') || img.getAttribute('data-lazy-src') || img.getAttribute('data-original') || '';
        const set = (img.getAttribute('data-srcset') || img.getAttribute('srcset') || '').split(',')
          .map(part => part.trim().split(/\\s+/)[0]).filter(Boolean).pop() || '';
        return web(current && !current.startsWith('data:') ? current : lazy || set);
      };
      // A video player in a frame. The Reader tab shows it as a link with its poster.
      const embed = src => {
        const youtube = src.match(/(?:youtube(?:-nocookie)?\\.com\\/embed\\/|youtu\\.be\\/)([\\w-]{6,})/);
        if (youtube) return { src: 'https://www.youtube.com/watch?v=' + youtube[1], poster: 'https://i.ytimg.com/vi/' + youtube[1] + '/hqdefault.jpg' };
        if (/player\\.vimeo\\.com|loom\\.com\\/embed|fast\\.wistia\\.net/.test(src)) return { src, poster: '' };
        return null;
      };
      const blocks = [];
      const seen = new Set();
      for (const el of root.querySelectorAll('h1, h2, h3, h4, p, li, blockquote, pre, img, video, iframe, table')) {
        if (el.closest(excluded)) continue;
        const table = el.parentElement?.closest('table');
        if (table && dataTable(table)) continue;
        if (el.tagName === 'IMG') {
          const src = imageSource(el);
          const width = Number(el.getAttribute('width')) || el.naturalWidth || 0;
          if (!src || seen.has(src) || (width > 0 && width < 80)) continue;
          seen.add(src);
          blocks.push({ kind: 'image', text: caption(el), src, alt: (el.getAttribute('alt') || '').trim() });
          continue;
        }
        if (el.tagName === 'VIDEO') {
          const src = web(el.currentSrc || el.getAttribute('src') || el.querySelector('source')?.getAttribute('src'));
          const poster = web(el.getAttribute('poster'));
          if (src) blocks.push({ kind: 'video', text: caption(el), src, poster });
          else if (poster) blocks.push({ kind: 'image', text: caption(el), src: poster, alt: '' });
          continue;
        }
        if (el.tagName === 'IFRAME') {
          const found = embed(web(el.getAttribute('src') || el.getAttribute('data-src')));
          if (found) blocks.push({ kind: 'embed', text: caption(el), src: found.src, poster: found.poster });
          continue;
        }
        if (el.tagName === 'TABLE') {
          if (dataTable(el)) blocks.push({ kind: 'table', text: '', rows: [...el.rows].map(row => [...row.cells].map(text)) });
          continue;
        }
        if (el.closest('figcaption')) continue;
        if (el.parentElement?.closest('p, li, blockquote, pre')) continue;
        const value = el.tagName === 'PRE' ? (el.innerText || '').replace(/^\\n+|\\s+$/g, '') : text(el);
        // The line numbers beside a code block are a block of digits.
        if (el.tagName === 'PRE' && /^[\\d\\s]*$/.test(value)) continue;
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

/// A message of the reader page, `Resources/reader.html`.
enum ReaderPageMessage: Decodable, Equatable {
    case ready
    /// A letter that the page does not use. The paper runs it.
    case key(String)
    /// The first block on the screen, and the part of the page above it.
    case position(block: Int, progress: Double)
    case link(URL)
    case mark(ReaderAction)

    private enum Key: String, CodingKey { case action, key, block, progress, url }

    init(from decoder: Decoder) throws {
        let values = try decoder.container(keyedBy: Key.self)
        switch try values.decode(String.self, forKey: .action) {
        case "ready":
            self = .ready
        case "key":
            self = .key(try values.decode(String.self, forKey: .key))
        case "position":
            self = .position(block: try values.decode(Int.self, forKey: .block), progress: try values.decode(Double.self, forKey: .progress))
        case "link":
            self = .link(try values.decode(URL.self, forKey: .url))
        default:
            self = .mark(try ReaderAction(from: decoder))
        }
    }
}

/// The reader page in a web view. Piper draws the article and the notes, and
/// the page reports each action of the reader.
struct ReaderPageView: NSViewRepresentable {
    let messages: Messages
    let state: ArticleLoader.State
    let placeholder: ReaderPlaceholder
    let notes: [ReaderPageNote]
    let scroll: ReaderScroll?
    let perform: (ReaderAction) -> Void
    /// Receives the first block on the screen and the part of the page above it, after a scroll.
    var positioned: (Int, Double) -> Void = { _, _ in }
    /// Reports a scroll request that the page ran.
    let scrolled: (ReaderScroll) -> Void
    /// Receives the bridge of the page, so that the reader paper can send keys to it and scroll it.
    let attach: (WebPageBridge) -> Void

    func makeCoordinator() -> Coordinator { Coordinator() }

    func makeNSView(context: Context) -> WKWebView {
        let configuration = WKWebViewConfiguration()
        configuration.userContentController.add(context.coordinator, name: "piper")
        configuration.websiteDataStore = .nonPersistent()
        let view = WKWebView(frame: .zero, configuration: configuration)
        view.underPageBackgroundColor = PiperTheme.paperNS
        view.setAccessibilityLabel("Article")
        let bridge = WebPageBridge(view: view, page: "reader", report: { [weak messages] in messages?.report($0) })
        bridge.reloaded = { [weak coordinator = context.coordinator] in coordinator?.reload() }
        context.coordinator.bridge = bridge
        attach(bridge)
        bridge.load()
        return view
    }

    func updateNSView(_ view: WKWebView, context: Context) {
        context.coordinator.perform = perform
        context.coordinator.positioned = positioned
        context.coordinator.scrolled = scrolled
        context.coordinator.placeholder = placeholder
        context.coordinator.show(state, notes: notes, scroll: scroll)
    }

    static func dismantleNSView(_ view: WKWebView, coordinator: Coordinator) {
        view.configuration.userContentController.removeScriptMessageHandler(forName: "piper")
        view.navigationDelegate = nil
    }

    @MainActor
    final class Coordinator: NSObject, WKScriptMessageHandler {
        var bridge: WebPageBridge?
        var perform: (ReaderAction) -> Void = { _ in }
        var positioned: (Int, Double) -> Void = { _, _ in }
        var scrolled: (ReaderScroll) -> Void = { _ in }
        var placeholder = ReaderPlaceholder(site: "", title: nil)
        private var shownState: ArticleLoader.State?
        private var shownNotes: [ReaderPageNote]?
        private var shownScroll: ReaderScroll?
        private var last: (state: ArticleLoader.State, notes: [ReaderPageNote], scroll: ReaderScroll?)?

        func show(_ state: ArticleLoader.State, notes: [ReaderPageNote], scroll: ReaderScroll?) {
            last = (state, notes, scroll)
            guard let bridge else { return }
            if state != shownState {
                shownState = state
                shownNotes = nil
                switch state {
                case .loading:
                    bridge.call("loading", placeholder)
                case .failed(let reason):
                    bridge.call("message", String(localized: "Cannot Read Article"), reason)
                case .loaded(let article):
                    bridge.call("render", article)
                }
            }
            guard case .loaded = state else { return }
            if notes != shownNotes {
                shownNotes = notes
                bridge.call("setNotes", notes)
            }
            if let scroll, scroll != shownScroll {
                shownScroll = scroll
                if let note = scroll.note { bridge.call("scrollTo", note.uuidString) }
                else { bridge.call("scrollToBlock", scroll.block ?? 0) }
                scrolled(scroll)
            }
        }

        /// Shows the last state again on a page that loaded again.
        func reload() {
            shownState = nil
            shownNotes = nil
            shownScroll = nil
            if let last { show(last.state, notes: last.notes, scroll: last.scroll) }
        }

        func userContentController(_ controller: WKUserContentController, didReceive message: WKScriptMessage) {
            guard let bridge, let decoded: ReaderPageMessage = bridge.decode(message) else { return }
            switch decoded {
            case .ready:
                bridge.pageReady()
            case .key(let key):
                (bridge.view?.window as? PaperWindow)?.perform(CommandKey(key, []))
            case .position(let block, let progress):
                positioned(block, progress)
            case .link(let url):
                if url.isWeb { NSWorkspace.shared.open(url) }
            case .mark(let action):
                perform(action)
            }
        }
    }
}

