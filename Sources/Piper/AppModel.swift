import AppKit
import Agents
import CryptoKit
import ApplicationServices
import Observation
import PiperCore
import Captures
import Vault

@MainActor @Observable
final class AppModel {
    let store: CaptureStore
    let clipboard: ClipboardInbox
    let agents: FolderAgents
    let fileReadState: FileReadState
    /// The highlights and questions of link captures.
    let reader: ReaderAssistant
    let brief: BriefBuilder
    /// The tab that a link capture shows: the article, the web page, or the notes.
    /// A link capture opens in the Web tab.
    var articleTab = ArticleTab.web
    /// The chip of the Inbox list for each section. The empty key is Inbox
    /// with every section.
    var inboxFilters: [String: InboxStream.Filter] = [:]
    /// The child note that the Reader tab scrolls to.
    var readerScroll: ReaderScroll?

    /// The tab of a link capture as it opens. A request to show one of its
    /// highlights opens the Reader tab. Each other link opens in the Web tab.
    func openingTab(for article: UUID) -> ArticleTab {
        guard let scroll = readerScroll, scroll.article == article, scroll.note != nil else { return .web }
        return .reader
    }

    /// Shows a highlight or a question of a link capture in the Reader tab.
    func showHighlight(_ note: UUID, in article: UUID) {
        articleTab = .reader
        readerScroll = ReaderScroll(note: note, in: article)
    }
    var files: [VaultFile] = []
    /// Every folder of the vault, including the ones that hold no file.
    var folders: [String] = []
    /// The file the main window had open when it last closed. The first scan
    /// opens it, so that the window comes back to the file the reader left.
    var initialDocument: String?
    var wikiProblems: [String] = []
    var wikiError: String?
    var loading = false
    @ObservationIgnored private var vaultWatcher: VaultWatcher?
    @ObservationIgnored private var reloadPending = false
    var route = "wiki"
    var workspace = WikiWorkspace()
    /// The editor sessions by path: the open file, and each file with text that is not on disk.
    var editors: [String: EditorSession] = [:]
    var captureEdits: [UUID: CaptureEditSession] = [:]
    var selectedDocument: String? { workspace.location?.path }
    /// The open file. A deleted file stays open while the editor holds text that is not on disk.
    var currentDocument: VaultFile? {
        files.first { $0.id == selectedDocument } ?? selectedDocument.flatMap { editors[$0]?.document }
    }
    /// The editor session of the open file.
    var editor: EditorSession? { selectedDocument.flatMap { editors[$0] } }
    /// The web page of the editor. Piper creates it when the main window first shows a Markdown file.
    @ObservationIgnored private(set) var loadedEditorPage: EditorPage?
    var editorPage: EditorPage {
        if let loadedEditorPage { return loadedEditorPage }
        let page = EditorPage(model: self)
        loadedEditorPage = page
        return page
    }
    /// What the actions in the toolbar run on. The window sets it with the selection.
    var actionTarget = SkillTarget.folder
    var requestedAnchor: String?
    var anchorRequest = UUID()
    var composerDraft = UserDefaults.standard.string(forKey: AppDefaults.Key.composerDraft) ?? "" {
        didSet { UserDefaults.standard.set(composerDraft, forKey: AppDefaults.Key.composerDraft) }
    }
    var accessibilityEnabled = AXIsProcessTrusted()
    var openNoteEditor: ((Note) -> Void)?
    var openPanel: (() -> Void)?
    var openLibrary: (() -> Void)?
    var openSettings: (() -> Void)?
    /// True while the detail pane shows the text of a file in place of its preview.
    var showsFileSource = UserDefaults.standard.bool(forKey: AppDefaults.Key.showsFileSource) {
        didSet { UserDefaults.standard.set(showsFileSource, forKey: AppDefaults.Key.showsFileSource) }
    }
    var captureShortcutChanged: (() -> Void)?
    var captureFloatingChanged: ((Bool) -> Void)?
    var captureFloating: Bool {
        didSet {
            preferences.set(captureFloating, forKey: AppDefaults.Key.captureFloating)
            captureFloatingChanged?(captureFloating)
        }
    }
    private(set) var wikiPaths: [String] {
        didSet {
            preferences.set(wikiPaths, forKey: AppDefaults.Key.wikiPaths)
            agents.refresh(paths: wikiPaths)
        }
    }
    /// A file to open when the next scan finds it, because a run just wrote it.
    @ObservationIgnored private var pendingDocument: String?
    /// Shows a file in the main window.
    var showFile: ((String) -> Void)?
    /// Shows a note in the Inbox of the main window.
    var showNote: ((UUID) -> Void)?
    /// Shows a link capture in Inbox, in the Web tab.
    var showArticle: ((UUID) -> Void)?
    /// Shows a session in the session pane of the main window.
    var showSession: ((UUID) -> Void)?
    /// The session that the session card and the Sessions list show. Nil starts a new session.
    var selectedSession: UUID?
    /// The note whose session card the reader cleared with New Session. The
    /// card stays empty for that note until a message starts a session.
    var newSessionNote: UUID?
    /// The pill, the card, or the detached panel. The choice survives a restart.
    var sessionPresentation = SessionPresentation(rawValue: UserDefaults.standard.string(forKey: AppDefaults.Key.sessionPresentation) ?? "") ?? .pill {
        didSet {
            UserDefaults.standard.set(sessionPresentation.rawValue, forKey: AppDefaults.Key.sessionPresentation)
            if oldValue != sessionPresentation { sessionPresentationChanged?(sessionPresentation) }
        }
    }
    /// Opens or closes the detached panel when the presentation changes.
    @ObservationIgnored var sessionPresentationChanged: ((SessionPresentation) -> Void)?
    @ObservationIgnored private let preferences: UserDefaults
    var wikiPath: String {
        didSet {
            preferences.set(wikiPath, forKey: AppDefaults.Key.vaultPath)
            if let vaultWatcher, vaultWatcher.root != vault.root { reload() }
        }
    }
    var captureShortcut: String {
        didSet {
            UserDefaults.standard.set(captureShortcut, forKey: "captureShortcut")
            captureShortcutChanged?()
        }
    }

    init(store: CaptureStore? = nil, wikiPath: String? = nil, fileReadState: FileReadState? = nil, preferences: UserDefaults = .standard) {
        self.preferences = preferences
        let defaults = preferences
        captureFloating = defaults.object(forKey: AppDefaults.Key.captureFloating) as? Bool ?? true
        if Bundle.main.bundleIdentifier == "com.piper", !defaults.bool(forKey: "migratedLocalPreferences") {
            let previous = defaults.persistentDomain(forName: "local.piper") ?? [:]
            for key in ["wikiPath", "captureShortcut", "composerDraft", "wikiReaderSize", "NSWindow Frame PiperCapturePanel", "NSWindow Frame PiperLibrary"] {
                if defaults.object(forKey: key) == nil, let value = previous[key] { defaults.set(value, forKey: key) }
            }
            defaults.set(true, forKey: "migratedLocalPreferences")
        }
        composerDraft = defaults.string(forKey: AppDefaults.Key.composerDraft) ?? ""
        let store = store ?? CaptureStore()
        self.store = store
        clipboard = ClipboardInbox(store: store)
        agents = FolderAgents(store: store, preferences: preferences)
        self.fileReadState = fileReadState ?? FileReadState()
        let activePath = wikiPath ?? defaults.string(forKey: AppDefaults.Key.vaultPath)
            ?? FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Desktop/Wiki").path
        self.wikiPath = activePath
        var savedPaths = wikiPath == nil ? defaults.stringArray(forKey: AppDefaults.Key.wikiPaths) ?? [] : []
        if !savedPaths.contains(activePath) { savedPaths.append(activePath) }
        self.wikiPaths = savedPaths
        // Control-Option-C was the earlier alternative. A stored value that no
        // longer matches a preset leaves the capture shortcut dead.
        let stored = UserDefaults.standard.string(forKey: "captureShortcut") ?? "Shift, Shift"
        captureShortcut = stored == "Control-Option-C" ? "Control-Option-Space" : stored
        reader = ReaderAssistant(store: store, agents: agents)
        brief = BriefBuilder(agents: agents, preferences: preferences)
        archiveFinishedReading()
        agents.refresh(paths: wikiPaths)
        agents.showDraft = { [weak self] id in self?.showSession?(id) }
        // A question goes to the folder of the Send buttons, or else to the open folder.
        reader.folder = { [weak self] in self.map { $0.agents.defaultFolder?.path ?? $0.vault.root.path } }
    }

    /// Moves the articles that the reader finished more than a week ago to
    /// Archived. Launch runs it, and so does each return to the main window.
    func archiveFinishedReading(now: Date = Date()) {
        store.archiveFinishedReading(before: now.addingTimeInterval(-Double(ReadingList.finishedDays) * 86_400))
    }

    /// The chip of the Inbox list of a section, or of every section when the section is nil.
    func inboxFilter(for section: String?) -> InboxStream.Filter {
        inboxFilters[section ?? "", default: .all]
    }

    /// Changes the chip of Inbox when it hides the note, so that the note shows.
    func showInInbox(_ note: Note) {
        let filter = inboxFilter(for: nil)
        if (filter == .notes && note.isArticle) || (filter == .reading && !note.isArticle) { inboxFilters[""] = .all }
    }

    func requestAccessibility() {
        let options = [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true] as CFDictionary
        accessibilityEnabled = AXIsProcessTrustedWithOptions(options)
        NSWorkspace.shared.open(URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility")!)
    }

    @discardableResult func captureClipboard(from pasteboard: NSPasteboard = .general) -> Bool {
        store.captureClipboard(from: pasteboard)
    }

    func editCapture(_ note: Note) -> CaptureEditSession {
        let session = CaptureEditSession(note: note)
        captureEdits[session.id] = session
        return session
    }

    @discardableResult func saveCaptureEdit(_ session: CaptureEditSession) -> Bool {
        guard session.hasChanges else { return true }
        guard store.update(session.note.id, text: session.text, originalText: session.note.text),
              let saved = store.notes.first(where: { $0.id == session.note.id }) else { return false }
        session.note = saved
        return true
    }

    var vault: Vault { Vault(root: URL(fileURLWithPath: (wikiPath as NSString).expandingTildeInPath).standardizedFileURL) }

    func isUnread(_ file: VaultFile) -> Bool { fileReadState.isUnread(file, in: vault.root) }

    var unreadFolderCounts: [String: Int] {
        var counts: [String: Int] = [:]
        for file in files where isUnread(file) {
            counts["", default: 0] += 1
            var folder = file.folder
            while !folder.isEmpty {
                counts[folder, default: 0] += 1
                folder = (folder as NSString).deletingLastPathComponent
            }
        }
        return counts
    }

    func markCurrentDocumentRead() {
        guard let document = currentDocument else { return }
        fileReadState.markRead(document, in: vault.root)
    }

    func reload() {
        agents.refresh(paths: wikiPaths)
        let repo = vault
        if vaultWatcher?.root != repo.root {
            vaultWatcher?.stop()
            let watcher = VaultWatcher(root: repo.root) { [weak self] in self?.reload() }
            vaultWatcher = watcher
            watcher.start()
        }
        guard !loading else { reloadPending = true; return }
        reloadPending = false
        loading = true
        Task {
            defer {
                loading = false
                if reloadPending { reload() }
            }
            let result = await Task.detached { Result { try repo.scan() } }.value
            guard repo.root == vault.root else {
                reloadPending = true
                return
            }
            switch result {
            case .success(let scan):
                wikiProblems = scan.problems
                wikiError = nil
                let firstLoad = files.isEmpty && workspace.history.isEmpty
                let previous = Dictionary(files.map { ($0.id, $0.modifiedAt) }, uniquingKeysWith: { first, _ in first })
                for file in scan.files where ["html", "htm"].contains((file.id as NSString).pathExtension.lowercased()) {
                    if let date = previous[file.id], date != file.modifiedAt { loadedEditorPage?.assetChanged(file.id) }
                }
                files = scan.files
                folders = scan.folders
                let previousLocation = workspace.location
                var paths = Set(files.map(\.id))
                for (path, session) in editors {
                    if let file = files.first(where: { $0.id == path }) {
                        if file.raw != session.baseline { session.diskChanged(in: repo) }
                        if !session.hasChanges { session.document = file }
                    } else if session.hasChanges {
                        // A deleted file stays open while the editor holds text that is not on disk.
                        paths.insert(path)
                    }
                }
                workspace.reconcile(paths: paths)
                pruneEditors()
                beginEdit()
                if previousLocation != workspace.location { jump(to: workspace.location?.anchor) }
                if let pending = pendingDocument, files.contains(where: { $0.id == pending }) {
                    pendingDocument = nil
                    openDocument(pending)
                } else if firstLoad,
                   let first = files.first(where: { $0.id == initialDocument })
                       ?? files.first(where: { $0.id == "Start Here.md" })
                       ?? files.first(where: { $0.id == "index.md" })
                       ?? files.first {
                    openDocument(first.id, markAsRead: false)
                }
            case .failure(let error):
                files = []
                folders = []
                wikiError = error.localizedDescription
            }
        }
    }

    func chooseWiki() {
        let panel = NSOpenPanel()
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.allowsMultipleSelection = true
        panel.prompt = "Add"
        panel.message = "Choose folders to add to the sidebar."
        guard panel.runModal() == .OK else { return }
        addWikiFolders(panel.urls)
    }

    /// Takes a folder out of the sidebar. The folder on disk does not change.
    ///
    /// The active folder moves to the next folder in the list first. The last
    /// folder stays, because the window needs one folder to show.
    func removeWikiFolder(_ path: String) {
        guard wikiPaths.count > 1, let index = wikiPaths.firstIndex(of: path) else { return }
        if path == wikiPath {
            let next = wikiPaths[index == 0 ? 1 : index - 1]
            changeWiki(to: URL(fileURLWithPath: (next as NSString).expandingTildeInPath))
            guard wikiPath == next else { return }
        }
        wikiPaths.removeAll { $0 == path }
    }

    func addWikiFolders(_ urls: [URL]) {
        guard let first = urls.first, settleEditors() else { return }
        for url in urls { registerWikiFolder(url) }
        changeWiki(to: first)
    }

    @discardableResult private func registerWikiFolder(_ url: URL) -> String {
        let resolved = url.standardizedFileURL.resolvingSymlinksInPath()
        if let existing = wikiPaths.first(where: {
            URL(fileURLWithPath: ($0 as NSString).expandingTildeInPath)
                .standardizedFileURL.resolvingSymlinksInPath() == resolved
        }) { return existing }
        let path = url.standardizedFileURL.path
        wikiPaths.append(path)
        return path
    }

    func changeWiki(to url: URL) {
        guard settleEditors() else { return }
        wikiPath = registerWikiFolder(url)
        workspace = WikiWorkspace()
        initialDocument = nil
        files = []
        folders = []
        route = "wiki"
        NotificationCenter.default.post(name: .vaultPathDidChange, object: self)
        reload()
    }

    /// Opens a file that a run wrote, in the folder it ran in.
    ///
    /// The file can be newer than the last scan. The model then opens it when
    /// the next scan finds it.
    func openRunFile(_ path: String, in folder: String) {
        let root = URL(fileURLWithPath: folder).standardizedFileURL
        if root != vault.root {
            changeWiki(to: root)
            guard vault.root == root else { return }
        }
        if files.contains(where: { $0.id == path }) {
            openDocument(path)
        } else {
            pendingDocument = path
            reload()
        }
        showFile?(path)
    }

    func createWiki() {
        guard settleEditors() else { return }
        do { try vault.create(); reload() }
        catch { store.report(error) }
    }

    func openLink(_ url: URL, from document: VaultFile) {
        if url.scheme == "piper-footnote" {
            let id = String(url.path.dropFirst())
            if WikiMarkdown.parse(document.body).contains(where: { $0.anchor == "fn-" + id }) {
                openDocument(document.id, anchor: "fn-" + id)
            } else { store.status = "See the footnote at the end of the document" }
            return
        }
        if ["http", "https", "mailto"].contains(url.scheme ?? "") { NSWorkspace.shared.open(url); return }
        if url.scheme == "piper-note" || url.scheme == "piper-wiki" || url.scheme == nil || url.isFileURL {
            do {
                let wikiStyle = url.scheme == "piper-note"
                let target = wikiStyle ? URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems?.first(where: { $0.name == "target" })?.value ?? "" : url.path + (url.fragment.map { "#" + $0 } ?? "")
                let location = try WikiLinks.resolve(target, from: document, files: files, vault: vault, wikiStyle: wikiStyle)
                openDocument(location.path, anchor: location.anchor)
            } catch { store.report(error) }
        }
    }

    func openDocument(_ path: String, anchor: String? = nil, markAsRead: Bool = true) {
        if path == selectedDocument {
            route = "wiki"
            beginEdit()
            if markAsRead { markCurrentDocumentRead() }
            if let anchor { jump(to: anchor) }
            return
        }
        guard files.contains(where: { $0.id == path }) else { return }
        route = "wiki"
        workspace.open(WikiLocation(path: path, anchor: anchor))
        pruneEditors()
        beginEdit()
        jump(to: anchor)
        if markAsRead { markCurrentDocumentRead() }
    }

    func navigate(_ offset: Int) {
        let next = workspace.position + offset
        guard workspace.history.indices.contains(next) else { return }
        workspace.move(offset)
        pruneEditors()
        beginEdit()
        jump(to: workspace.location?.anchor)
        markCurrentDocumentRead()
    }

    // MARK: - Editor

    /// Starts an editor session for the open Markdown file, if it has none.
    func beginEdit() {
        guard let document = currentDocument, document.isMarkdown, document.isText,
              editors[document.id] == nil else { return }
        editors[document.id] = EditorSession(document: document)
    }

    /// Takes the text of a file from the editor and saves it.
    ///
    /// The editor sends its text 120 ms after the last edit, and again when it
    /// closes a file. The text can be for a file that is no longer open.
    func editorChanged(path: String, text: String) {
        guard let session = editors[path] else { return }
        session.text = text
        saveEditor(session)
    }

    @discardableResult func saveEditor(_ session: EditorSession) -> Bool {
        let saved = session.save(in: vault)
        refreshFile(of: session)
        pruneEditors()
        return saved
    }

    /// Writes the editor text over a change on disk.
    func keepEditorText() {
        guard let session = editor else { return }
        session.keepMine(in: vault)
        refreshFile(of: session)
    }

    /// Drops the edits of the open file and loads the text on disk.
    func reloadEditorFromDisk() {
        guard let session = editor else { return }
        session.reloadFromDisk(in: vault)
        refreshFile(of: session)
    }

    /// True when a Piper session wrote the file in the last 10 minutes, or is still running.
    func sessionWrote(_ path: String) -> Bool {
        let recent = Date().addingTimeInterval(-AppDefaults.Editor.sessionWriteWindow)
        return agents.runner.sessions(in: vault.root.path).contains { session in
            session.files.contains(path) && (session.isActive || session.updatedAt > recent)
        }
    }

    /// Saves each edit before the folder changes or Piper quits.
    ///
    /// A change on disk blocks the save of a file with edits. Piper then shows
    /// that file and returns false, so the reader can choose Reload or Keep Mine.
    func settleEditors() -> Bool {
        for session in editors.values where session.hasChanges { saveEditor(session) }
        if let blocked = editors.values.first(where: { $0.hasChanges || $0.status == .conflict }) {
            if blocked.path != selectedDocument { openDocument(blocked.path) }
            showFile?(blocked.path)
            store.report(PiperError("“\(blocked.document.title)” changed on disk while you edited it. Choose Reload or Keep Mine first."))
            return false
        }
        editors = [:]
        return true
    }

    /// Drops the sessions of the files that are not open and that hold no text off disk.
    func pruneEditors() {
        let kept = editors.filter { $0.key == selectedDocument || $0.value.hasChanges || $0.value.status == .conflict }
        if kept.count != editors.count { editors = kept }
    }

    private func refreshFile(of session: EditorSession) {
        guard !session.hasChanges, session.status == .saved, let file = try? vault.read(session.path) else { return }
        session.document = file
        if let index = files.firstIndex(where: { $0.id == file.id }) { files[index] = file }
        fileReadState.markRead(file, in: vault.root)
    }

    // MARK: - Margin notes of a file

    /// The link of the page note that holds the margin notes of a file.
    func fileLink(_ path: String) -> String {
        let absolute = vault.root.appendingPathComponent(path).path
        return "piper-file://" + (absolute.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? absolute)
    }

    /// A file as the margin agent reads it: its title and its blocks.
    func fileArticle(_ document: VaultFile) -> ReaderArticle {
        let blocks = WikiMarkdown.parse(document.body)
            .filter { !$0.text.trimmingCharacters(in: .whitespaces).isEmpty }
            .map { ReaderArticle.Block(kind: $0.kind == .heading ? "heading" : "paragraph", text: $0.text) }
        return ReaderArticle(url: URL(string: fileLink(document.id)) ?? vault.root, site: vault.root.lastPathComponent,
                             title: document.title, author: "", blocks: blocks)
    }

    /// The margin notes of a file, as the editor page draws them.
    func fileNotes(_ document: VaultFile) -> [ReaderPageNote] {
        let link = fileLink(document.id)
        guard let parent = store.notes.first(where: { $0.parent == nil && $0.sourceURLs.contains(link) }) else { return [] }
        return ReaderMarks.payload(model: self, parent: parent.id, article: fileArticle(document), places: NotePlaces())
    }

    /// Runs an action of the selection bar or a margin card of the editor page.
    func performFileAction(_ message: [String: Any], path: String) {
        guard let document = editors[path]?.document ?? files.first(where: { $0.id == path }) else { return }
        let link = fileLink(path)
        ReaderMarks.perform(message, model: self, article: fileArticle(document)) {
            store.pageNote(for: link, title: document.title, source: ReaderAssistant.source)?.id
        }
    }

    /// Follows a link that the reader clicked in the editor.
    func openEditorLink(kind: String, target: String) {
        guard let document = currentDocument else { return }
        if kind == "wiki" {
            do {
                let location = try WikiLinks.resolve(target, from: document, files: files, vault: vault, wikiStyle: true)
                openDocument(location.path, anchor: location.anchor)
            } catch { store.report(error) }
            return
        }
        let encoded = target.addingPercentEncoding(withAllowedCharacters: .urlFragmentAllowed)
        guard let url = URL(string: target) ?? encoded.flatMap(URL.init(string:)) else { return }
        openLink(url, from: document)
    }

    /// Writes a pasted image next to a note, as `<note>.assets/<hash>.<ext>`,
    /// and returns the path for the Markdown, relative to the note.
    func saveEditorImage(for path: String, type: String, base64: String) throws -> String {
        guard let data = Data(base64Encoded: base64), !data.isEmpty else { throw PiperError("The image is empty.") }
        let hash = SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined().prefix(12)
        let stem = ((path as NSString).lastPathComponent as NSString).deletingPathExtension
        let name = "\(stem).assets/\(hash).\(Self.imageExtension(for: type))"
        let url = try vault.containedURL(name, relativeTo: path)
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        if !FileManager.default.fileExists(atPath: url.path) { try data.write(to: url, options: .atomic) }
        return name.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? name
    }

    static func imageExtension(for type: String) -> String {
        switch type.lowercased() {
        case "image/jpeg", "image/jpg": return "jpg"
        case "image/gif": return "gif"
        case "image/webp": return "webp"
        case "image/heic": return "heic"
        case "image/svg+xml": return "svg"
        case "image/tiff": return "tiff"
        default: return "png"
        }
    }

    func jump(to anchor: String?) {
        requestedAnchor = anchor
        anchorRequest = UUID()
    }
}

/// The tabs of a link capture in the detail pane.
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
