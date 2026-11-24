import AppKit
import Agents
import ApplicationServices
import Observation
import PiperCore
import Captures
import CapturesDatabase
import Feeds
import Vault

@MainActor @Observable
final class AppModel {
    /// The messages that the toast shows.
    let messages: Messages
    let store: CaptureStore
    /// The undo stack of the app. Edit > Undo, Command-Z, and the Undo button of Today use it.
    var undoManager: UndoManager { store.undoManager }
    let clipboard: ClipboardInbox
    let agents: AgentSettings
    /// The folders with skills, which Send runs.
    let skills: SkillFolders
    let send: Send
    /// The highlights and questions of link captures.
    let reader: ReaderAssistant
    /// The subscriptions and their articles.
    let feeds: FeedStore
    /// Keep, open in the browser, copy the link, and open as a paper, for a feed article.
    let articleActions: ArticleActions
    /// The icon of each site, for the rows of Today and Sources.
    let favicons: FaviconStore
    /// The sites of browser history and their feeds.
    let siteScan: SiteScan
    /// The tab that each open link capture shows, by the id of the capture:
    /// the article, the web page, or the notes. Each reader paper has its own tab.
    private(set) var articleTabs: [UUID: ArticleTab] = [:]
    /// The tab, Reader or Web, that the reader last chose for each site, by `Site.key`.
    /// Preferences keep it.
    private(set) var siteTabs: [String: ArticleTab] = [:]
    /// The child note that the Reader tab scrolls to.
    var readerScroll: ReaderScroll?
    /// The pages of the Reader tabs that show, one for each reader paper.
    @ObservationIgnored let readerPages = NSHashTable<WebPageBridge>.weakObjects()

    /// The tab of a link capture as it opens. A request to show one of its
    /// highlights opens the Reader tab. Each other link opens in the tab that
    /// the reader last chose for its site. A new site opens in the Web tab.
    func openingTab(for note: Note) -> ArticleTab {
        if let scroll = readerScroll, scroll.article == note.id, scroll.note != nil { return .reader }
        return note.articleURL.flatMap(Site.init).flatMap { siteTabs[$0.key] } ?? .web
    }

    /// The tab that a link capture shows: the tab that the reader chose for
    /// it, or else its opening tab.
    func articleTab(for note: Note) -> ArticleTab {
        articleTabs[note.id] ?? openingTab(for: note)
    }

    /// Keeps the tab of a link capture as it opens, so that a later change of
    /// the opening tab of its site does not change it.
    func keepArticleTab(for note: Note) {
        articleTabs[note.id] = articleTab(for: note)
    }

    /// Shows a tab of a link capture that the reader chose. A choice of Reader
    /// or Web becomes the opening tab of the site of the link.
    func chooseArticleTab(_ tab: ArticleTab, for note: Note) {
        articleTabs[note.id] = tab
        guard tab != .notes, let url = note.articleURL, let site = Site(url)?.key, siteTabs[site] != tab else { return }
        siteTabs[site] = tab
        preferences.set(siteTabs.mapValues(\.rawValue), forKey: AppDefaults.Key.siteTabs)
    }

    /// Shows a highlight or a question of a link capture in the Reader tab.
    func showHighlight(_ note: UUID, in article: UUID) {
        articleTabs[article] = .reader
        readerScroll = ReaderScroll(note: note, in: article)
    }

    // MARK: - Folders and files

    let library: Library
    let files: FileEditor

    // MARK: - Captures

    var captureEdits: [UUID: CaptureEditSession] = [:]
    var composerDraft: String {
        didSet { preferences.set(composerDraft, forKey: AppDefaults.Key.composerDraft) }
    }
    var accessibilityEnabled = AXIsProcessTrusted()
    var captureShortcut: CaptureShortcut {
        didSet {
            preferences.set(captureShortcut.rawValue, forKey: AppDefaults.Key.captureShortcut)
            captureShortcutChanged?()
        }
    }
    @ObservationIgnored var captureShortcutChanged: (() -> Void)?

    // MARK: - Sessions

    /// What the session card works with. The focused reader paper sets it.
    var actionTarget = SkillTarget.folder
    /// The session that the session card and the Sessions list show. Nil starts a new session.
    var selectedSession: UUID?
    /// The note whose session card the reader cleared with New Session. The
    /// card stays empty for that note until a message starts a session.
    var newSessionNote: UUID?
    /// The pill, the card, or the detached panel. The choice survives a restart.
    var sessionPresentation: SessionPresentation {
        didSet {
            preferences.set(sessionPresentation.rawValue, forKey: AppDefaults.Key.sessionPresentation)
            if oldValue != sessionPresentation { sessionPresentationChanged?(sessionPresentation) }
        }
    }
    /// Opens or closes the detached panel when the presentation changes.
    @ObservationIgnored var sessionPresentationChanged: ((SessionPresentation) -> Void)?

    // MARK: - Windows

    /// The desk, which opens every paper. `PaperDesk` sets it when the app makes the desk.
    @ObservationIgnored weak var desk: PaperDesk?

    /// The preferences of every key that the model and its parts keep.
    @ObservationIgnored let preferences: UserDefaults

    /// - Parameters:
    ///   - databaseURL: The note database. Nil uses the one in the data folder.
    ///   - feeds: The feed store. A test that gives a database and no feed
    ///     store gets a feed store in a temporary folder.
    init(databaseURL: URL? = nil, wikiPath: String? = nil, preferences: UserDefaults = .standard, feeds: FeedStore? = nil) {
        self.preferences = preferences
        let messages = Messages()
        self.messages = messages
        composerDraft = preferences.string(forKey: AppDefaults.Key.composerDraft) ?? ""
        sessionPresentation = SessionPresentation(rawValue: preferences.string(forKey: AppDefaults.Key.sessionPresentation) ?? "") ?? .pill
        siteTabs = (preferences.dictionary(forKey: AppDefaults.Key.siteTabs) as? [String: Int] ?? [:])
            .compactMapValues { ArticleTab(rawValue: $0) }
        self.feeds = feeds ?? FeedStore(url: databaseURL == nil ? nil : FileManager.default.temporaryDirectory
            .appendingPathComponent("PiperFeeds-\(UUID().uuidString)/Feeds.sqlite")) { [weak messages] in messages?.report($0) }
        favicons = FaviconStore(folder: databaseURL == nil ? nil : FileManager.default.temporaryDirectory
            .appendingPathComponent("PiperFavicons-\(UUID().uuidString)"))
        let database = Result { try Database(url: databaseURL ?? DataFolder.url.appendingPathComponent("notes.sqlite")) }
        // A test store makes each change its own undo step, because a test runs no events.
        let store = CaptureStore(database: database, undoManager: databaseURL == nil ? UndoManager() : nil)
        self.store = store
        store.reportUndoError = { [weak messages] in messages?.report($0) }
        if let error = store.loadError { messages.report(error) }
        clipboard = ClipboardInbox(store: store, database: try? database.get()) { [weak messages] in messages?.report($0) }
        let agents = AgentSettings(storage: try? database.get(), messages: messages, preferences: preferences)
        self.agents = agents
        let skills = SkillFolders(preferences: preferences)
        self.skills = skills
        send = Send(store: store, agents: agents, skills: skills)
        captureShortcut = CaptureShortcut(stored: preferences.string(forKey: AppDefaults.Key.captureShortcut))
        let library = Library(wikiPath: wikiPath, preferences: preferences, skills: skills)
        self.library = library
        articleActions = ArticleActions(store: store, feeds: self.feeds, messages: messages, library: library)
        let reader = ReaderAssistant(store: store, agents: agents, messages: messages) { [library] in library.agentFolder }
        self.reader = reader
        files = FileEditor(library: library, store: store, reader: reader, agents: agents, messages: messages, preferences: preferences)
        siteScan = SiteScan(feeds: self.feeds, messages: messages, preferences: preferences)
        do { try store.archiveFinishedReading() } catch { messages.report(error) }
        agents.showSession = { [weak self] session in self?.desk?.open(.session(session.id)) }
    }

    func requestAccessibility() {
        let options = [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true] as CFDictionary
        accessibilityEnabled = AXIsProcessTrustedWithOptions(options)
        NSWorkspace.shared.open(URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility")!)
    }

    /// Saves the text of the clipboard as a note in the active section.
    @discardableResult func captureClipboard(from pasteboard: NSPasteboard = .general) -> Note? {
        do {
            let note = try store.add(pasteboard.text(), section: store.activeSection, source: Note.clipboardSource)
            messages.show("Saved to \(note.section)")
            return note
        } catch {
            messages.report(error)
            return nil
        }
    }

    func editCapture(_ note: Note) -> CaptureEditSession {
        let session = CaptureEditSession(note: note)
        captureEdits[session.id] = session
        return session
    }

    @discardableResult func saveCaptureEdit(_ session: CaptureEditSession) -> Bool {
        guard session.hasChanges else { return true }
        do {
            try store.update(session.note.id, text: session.text, originalText: session.note.text)
        } catch {
            messages.report(error)
            return false
        }
        guard let saved = store.notes.first(where: { $0.id == session.note.id }) else { return false }
        session.note = saved
        return true
    }
}

/// The tabs of a link capture in its reader paper.
enum ArticleTab: Int {
    case reader
    case web
    case notes
}

/// A request to scroll the Reader tab to a child note. Each request is new, so
/// a second click on the same note scrolls again.
struct ReaderScroll: Equatable {
    /// The link capture that the request is for. Another article ignores it.
    let article: UUID
    /// The child note to show. Nil scrolls to the block.
    let note: UUID?
    /// The block to show when no note is given. Zero is the top.
    let block: Int?
    let request = UUID()

    init(note: UUID, in article: UUID) {
        self.article = article
        self.note = note
        block = nil
    }

    init(block: Int, in article: UUID) {
        self.article = article
        note = nil
        self.block = block
    }
}
