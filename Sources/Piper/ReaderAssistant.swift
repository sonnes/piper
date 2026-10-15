import Agents
import AppKit
import Captures
import Observation
import PiperCore

/// The clean text of a web page, as the Reader tab shows it.
struct ReaderArticle: Codable, Equatable {

    /// One paragraph, heading, list item, quote, or code block.
    struct Block: Codable, Equatable {
        /// `paragraph`, `heading`, `subheading`, `item`, `quote`, or `code`.
        let kind: String
        let text: String
    }

    let url: URL
    let site: String
    let title: String
    /// The author and the reading time.
    let byline: [String]
    let blocks: [Block]

    var texts: [String] { blocks.map(\.text) }
    var words: Int { blocks.reduce(0) { $0 + $1.text.split(whereSeparator: \.isWhitespace).count } }

    init(url: URL, site: String, title: String, byline: [String], blocks: [Block]) {
        self.url = url
        self.site = site
        self.title = title
        self.byline = byline
        self.blocks = blocks
    }

    /// An article with the reading time in its byline.
    init(url: URL, site: String, title: String, author: String, blocks: [Block]) {
        let words = blocks.reduce(0) { $0 + $1.text.split(whereSeparator: \.isWhitespace).count }
        let minutes = max(1, Int((Double(words) / AppDefaults.ArticleReader.wordsPerMinute).rounded()))
        self.init(url: url, site: site, title: title, byline: [author, "\(minutes) min read"].filter { !$0.isEmpty }, blocks: blocks)
    }

    /// The article in the text of a page that a browser showed. Each line of
    /// 40 characters or more is a paragraph. Shorter lines are menus and
    /// buttons. Nil when no line is long enough.
    init?(url: URL, title: String?, pageText: String) {
        let blocks = pageText.components(separatedBy: .newlines)
            .map(NoteAnchor.normalized)
            .filter { $0.count >= Self.shortestParagraph && $0 != title }
            .map { Block(kind: "paragraph", text: $0) }
        guard !blocks.isEmpty else { return nil }
        let host = url.host() ?? url.absoluteString
        self.init(url: url, site: host.hasPrefix("www.") ? String(host.dropFirst(4)) : host,
                  title: title ?? host, author: "", blocks: blocks)
    }

    private static let shortestParagraph = 40
}

/// The highlights and questions of a link capture, and the hidden margin
/// session that answers the questions.
///
/// Each highlight and each question is a child note of the capture. A question
/// note holds its thread as plain text (see `NoteThread`). One session answers
/// every question about one capture, so the article goes to the agent once.
@MainActor @Observable
final class ReaderAssistant {

    /// What the reader asked for in the selection bar.
    enum Request {
        case explain
        case define
        case ask(String)

        var label: String {
            switch self {
            case .explain: return "Explain"
            case .define: return "Define"
            case .ask: return "Ask"
            }
        }
    }

    /// A message that waits for its answer.
    fileprivate struct Pending {
        let noteID: UUID
        let sessionID: UUID
        let userBlockID: String
    }

    /// A message that waits for the turn before it to end.
    fileprivate struct Queued {
        let noteID: UUID
        let text: String
    }

    // MARK: - Properties

    static let highlightTag = ReadingList.highlightTag
    static let questionTag = ReadingList.questionTag
    static let summaryTag = ReadingList.summaryTag
    static let colors = ["yellow", "green", "pink"]
    /// The most article text that the first message carries.
    private static let articleLimit = 120_000

    /// The question notes that wait for an answer.
    private(set) var waitingNotes: Set<UUID> = []
    /// Why the last answer of a note failed.
    private(set) var failures: [UUID: String] = [:]
    /// The tools that the last answer of a note used, in one line, since Piper started.
    private(set) var toolLines: [UUID: String] = [:]
    @ObservationIgnored private var pending: [Pending] = []
    @ObservationIgnored private var queued: [UUID: [Queued]] = [:]
    @ObservationIgnored private var watched: Set<UUID> = []
    @ObservationIgnored private let store: CaptureStore
    @ObservationIgnored private let agents: FolderAgents
    /// The folder that a new session works in.
    @ObservationIgnored var folder: () -> String? = { nil }

    // MARK: - Initialization

    init(store: CaptureStore, agents: FolderAgents) {
        self.store = store
        self.agents = agents
    }

    // MARK: - Notes

    /// Saves a highlight under the capture. A comment is the note of the
    /// reader, and it follows the quote in the note text.
    @discardableResult
    func highlight(_ anchor: NoteAnchor, color: String, in parent: UUID, comment: String = "") -> Note? {
        let color = Self.colors.contains(color) ? color : Self.colors[0]
        return store.addChild(HighlightText.adding(comment, to: anchor.quote), to: parent,
                              tags: [Self.highlightTag, color], anchor: anchor, source: Self.source)
    }

    /// Asks the margin agent to review every highlight and note of the capture.
    @discardableResult
    func reviewHighlights(in parent: UUID, article: ReaderArticle) -> Note? {
        let highlights = ReadingList.highlights(in: store.children(of: parent))
        guard !highlights.isEmpty else { return nil }
        guard let folder = folder() else {
            store.report(PiperError("Add a folder in the sidebar. An agent works in a folder."))
            return nil
        }
        guard let note = store.addChild(Self.reviewTitle, to: parent, tags: [Self.questionTag]) else { return nil }
        let session = session(for: parent) ?? agents.newMarginSession(in: folder, noteID: note.id)
        let list = highlights.map { highlight -> String in
            let comment = HighlightText.comment(of: highlight.text, quote: highlight.anchor?.quote)
            let quote = "> " + Self.line(highlight.anchor?.quote ?? highlight.text)
            return comment.isEmpty ? quote : quote + "\nMy note: " + Self.line(comment)
        }.joined(separator: "\n\n")
        var message = """
        These are my highlights and notes from the article. In a few short paragraphs, say what they add up to. \
        Then name one important point of the article that they miss.

        \(list)
        """
        if session.blocks.isEmpty { message += "\n\n" + Self.context(article) }
        send(message, for: note.id, in: session)
        return note
    }

    /// The source of a note that the reader made in Piper.
    static let source = "Piper"
    static let reviewTitle = "Review: My highlights"

    /// Saves a question under the capture and sends it to the margin agent.
    @discardableResult
    func ask(_ request: Request, about anchor: NoteAnchor, in parent: UUID, article: ReaderArticle) -> Note? {
        guard let folder = folder() else {
            store.report(PiperError("Add a folder in the sidebar. An agent works in a folder."))
            return nil
        }
        var text = request.label + ": " + Self.line(anchor.quote)
        if case .ask(let question) = request { text += "\n\n" + NoteThread.question(question) }
        guard let note = store.addChild(text, to: parent, tags: [Self.questionTag], anchor: anchor) else { return nil }
        let session = session(for: parent) ?? agents.newMarginSession(in: folder, noteID: note.id)
        var message = Self.prompt(request, quote: anchor.quote)
        if session.blocks.isEmpty { message += "\n\n" + Self.context(article) }
        send(message, for: note.id, in: session)
        return note
    }

    /// Adds a follow-up question to a question note and sends it.
    func followUp(_ question: String, on noteID: UUID, in parent: UUID, article: ReaderArticle) {
        let question = question.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !question.isEmpty, let note = store.notes.first(where: { $0.id == noteID }),
              store.append(NoteThread.question(question), to: noteID) else { return }
        let quote = note.anchor?.quote ?? ""
        var message = question + (quote.isEmpty ? "" : "\n\nThis follows up on the passage:\n\n> " + Self.line(quote))
        if let session = session(for: parent) {
            send(message, for: noteID, in: session)
        } else if let folder = folder() {
            let session = agents.newMarginSession(in: folder, noteID: noteID)
            message += "\n\n" + Self.context(article)
            send(message, for: noteID, in: session)
        }
    }

    /// The model and the agent that answer the questions about a capture,
    /// such as "Haiku · Claude Code".
    func answererName(for parent: UUID) -> String {
        guard let session = session(for: parent) else {
            let agent = agents.marginAgent
            let model = agent.isClaudeCode ? ClaudeCodeConnection.models.first { $0.id == agents.marginModel }?.name : nil
            return [model, agent.name].compactMap { $0 }.joined(separator: " · ")
        }
        let option = session.configOptions.first { $0.category == "model" }
        let value = session.model ?? option?.currentValue
        let model = value.flatMap { value in
            (option?.values ?? ClaudeCodeConnection.models).first { $0.id == value }?.name ?? value
        }
        let agent = agents.runner.agent(of: session)?.name ?? "Agent"
        return [model, agent].compactMap { $0 }.filter { !$0.isEmpty }.joined(separator: " · ")
    }

    /// Opens a draft session with the thread of a question and the page, with every tool.
    func continueInSession(_ noteID: UUID, article: ReaderArticle) {
        guard let note = store.notes.first(where: { $0.id == noteID }) else { return }
        guard let folder = folder() else {
            store.report(PiperError("Add a folder in the sidebar. An agent works in a folder."))
            return
        }
        let quote = note.anchor.map { "\n\n> " + Self.line($0.quote) } ?? ""
        let session = agents.newSession(in: folder)
        session.draft = "This continues my questions about \u{201C}\(article.title)\u{201D} (\(article.url.absoluteString))."
            + quote + "\n\n" + note.text + "\n\n"
        agents.showDraft?(session.id)
    }

    /// The margin session that answers the questions about a capture. A
    /// session whose agent cannot answer in the margin does not count.
    func session(for parent: UUID) -> AgentSession? {
        let questions = Set(store.children(of: parent).filter { $0.tags.contains(Self.questionTag) }.map(\.id))
        return agents.runner.sessions.first {
            $0.purpose == .margin && $0.noteID.map(questions.contains) == true && agents.canAnswerInMargin($0.agentID)
        }
    }

    // MARK: - Prompts

    static func prompt(_ request: Request, quote: String) -> String {
        let quote = line(quote)
        switch request {
        case .explain:
            return "Explain this passage from the article in one or two short paragraphs:\n\n> " + quote
        case .define:
            return "Define \u{201C}\(quote)\u{201D} as the article uses it, in one short paragraph."
        case .ask(let question):
            return question + "\n\nThe question is about this passage:\n\n> " + quote
        }
    }

    /// The instructions and the article, for the first message of a session.
    static func context(_ article: ReaderArticle) -> String {
        var text = article.blocks.map(\.text).joined(separator: "\n\n")
        if text.count > articleLimit { text = String(text.prefix(articleLimit)) + "\n\n[The rest of the article is cut.]" }
        return """
        Answer in plain text, without headings. I read the article below in Piper, and \
        each of my messages asks about a passage of it. Answer from the article first. If it does not answer the \
        question, you can read my notes in this folder or search the web. You cannot change files.

        Title: \(article.title)
        URL: \(article.url.absoluteString)

        \(text)
        """
    }

    private static func line(_ text: String) -> String {
        text.split(whereSeparator: \.isNewline).joined(separator: " ")
    }
}

// MARK: - Private

private extension ReaderAssistant {

    /// Sends now, or after the turn that runs. One turn at a time keeps each
    /// answer after its own message in the transcript.
    func send(_ text: String, for noteID: UUID, in session: AgentSession) {
        waitingNotes.insert(noteID)
        failures[noteID] = nil
        watch(session)
        if session.isActive || pending.contains(where: { $0.sessionID == session.id }) {
            queued[session.id, default: []].append(Queued(noteID: noteID, text: text))
            return
        }
        agents.runner.send(text, to: session)
        // A turn that cannot start ends at once, so a result can follow the message.
        guard let message = session.blocks.last(where: { if case .user = $0 { return true } else { return false } }) else {
            waitingNotes.remove(noteID)
            return
        }
        pending.append(Pending(noteID: noteID, sessionID: session.id, userBlockID: message.id))
    }

    func watch(_ session: AgentSession) {
        guard watched.insert(session.id).inserted else { return }
        observe(session)
    }

    func observe(_ session: AgentSession) {
        withObservationTracking {
            _ = session.blocks.count
            _ = session.state
        } onChange: { [weak self, weak session] in
            Task { @MainActor in
                guard let self, let session else { return }
                self.resolve(session)
                if self.pending.contains(where: { $0.sessionID == session.id }) || self.queued[session.id]?.isEmpty == false {
                    self.observe(session)
                } else {
                    self.watched.remove(session.id)
                }
            }
        }
    }

    /// Saves each answer that arrived, then sends the next queued message.
    func resolve(_ session: AgentSession) {
        for item in pending where item.sessionID == session.id {
            guard let start = session.blocks.firstIndex(where: { $0.id == item.userBlockID }) else {
                finish(item, failure: "The session was deleted.")
                continue
            }
            let turn = session.blocks[(start + 1)...]
            guard let end = turn.firstIndex(where: { if case .result = $0 { return true } else { return false } }),
                  case .result(_, let result) = session.blocks[end] else { continue }
            let texts = turn[..<end].compactMap { block -> String? in
                if case .assistant(_, let text) = block { return text } else { return nil }
            }
            let answer = result.text.isEmpty ? texts.joined(separator: "\n\n") : result.text
            if !answer.isEmpty { store.append(answer, to: item.noteID) }
            let calls = turn[..<end].compactMap { block -> ToolCall? in
                if case .toolCall(let call) = block { return call } else { return nil }
            }
            toolLines[item.noteID] = calls.isEmpty ? nil : "Used " + ToolCall.summary(of: calls)
            finish(item, failure: result.failure ?? (answer.isEmpty ? "The agent gave no answer." : nil))
        }
        guard !session.isActive, !pending.contains(where: { $0.sessionID == session.id }),
              var waiting = queued[session.id], !waiting.isEmpty else { return }
        let next = waiting.removeFirst()
        queued[session.id] = waiting
        send(next.text, for: next.noteID, in: session)
    }

    func finish(_ item: Pending, failure: String?) {
        pending.removeAll { $0.userBlockID == item.userBlockID }
        waitingNotes.remove(item.noteID)
        failures[item.noteID] = failure
    }
}
