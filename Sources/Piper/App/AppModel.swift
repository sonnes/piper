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
    /// The tab of each link capture and the place that its Reader tab scrolls to.
    let articleTabs: ArticleTabs
    /// The one way for a part of the model to open a paper.
    let papers: PaperOpener

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
        articleTabs = ArticleTabs(preferences: preferences)
        let papers = PaperOpener()
        self.papers = papers
        let open: (PaperItem) -> Void = { papers.open($0) }
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
        let agents = AgentSettings(storage: try? database.get(), messages: messages, preferences: preferences, open: open)
        self.agents = agents
        let skills = SkillFolders(preferences: preferences)
        self.skills = skills
        send = Send(store: store, agents: agents, skills: skills, open: open)
        captureShortcut = CaptureShortcut(stored: preferences.string(forKey: AppDefaults.Key.captureShortcut))
        let library = Library(wikiPath: wikiPath, preferences: preferences, skills: skills)
        self.library = library
        articleActions = ArticleActions(store: store, feeds: self.feeds, messages: messages, library: library, open: open)
        let reader = ReaderAssistant(store: store, agents: agents, messages: messages) { [library] in library.agentFolder }
        self.reader = reader
        files = FileEditor(library: library, store: store, reader: reader, agents: agents, messages: messages,
                           preferences: preferences, open: open)
        siteScan = SiteScan(feeds: self.feeds, messages: messages, preferences: preferences)
        do { try store.archiveFinishedReading() } catch { messages.report(error) }
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
