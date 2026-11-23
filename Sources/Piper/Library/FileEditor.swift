import AppKit
import Agents
import Captures
import CryptoKit
import Observation
import PiperCore
import Vault

/// The open file of the file paper: its history, its editor sessions, the
/// editor page, and its margin notes.
@MainActor @Observable
final class FileEditor {
    let library: Library
    var workspace = WikiWorkspace() {
        didSet {
            if workspace.location?.path != oldValue.location?.path { desk?.fileChanged(to: selectedDocument) }
        }
    }
    /// The editor sessions by path: the open file, and each file with text that is not on disk.
    var editors: [String: EditorSession] = [:]
    /// The file the file paper had open when Piper last quit. The first scan
    /// opens it, so that the window comes back to the file the reader left.
    var initialDocument: String?
    var requestedAnchor: String?
    var anchorRequest = UUID()
    /// True while the file paper shows the text of a file in place of its preview.
    var showsFileSource: Bool {
        didSet { preferences.set(showsFileSource, forKey: AppDefaults.Key.showsFileSource) }
    }
    /// The desk, which shows the file paper and follows its file. `PaperDesk` sets it.
    @ObservationIgnored weak var desk: PaperDesk?
    /// The web page of the editor. Piper creates it when the file paper first shows a Markdown file.
    @ObservationIgnored private(set) var loadedEditorPage: EditorPage?
    /// A file to open when the next scan finds it, because a run just wrote it.
    @ObservationIgnored private var pendingDocument: String?
    @ObservationIgnored let store: CaptureStore
    @ObservationIgnored private let reader: ReaderAssistant
    @ObservationIgnored private let agents: FolderAgents
    @ObservationIgnored private let preferences: UserDefaults

    init(library: Library, store: CaptureStore, reader: ReaderAssistant, agents: FolderAgents, preferences: UserDefaults) {
        self.library = library
        self.store = store
        self.reader = reader
        self.agents = agents
        self.preferences = preferences
        showsFileSource = preferences.bool(forKey: AppDefaults.Key.showsFileSource)
        library.delegate = self
    }

    var selectedDocument: String? { workspace.location?.path }
    /// The open file. A deleted file stays open while the editor holds text that is not on disk.
    var currentDocument: VaultFile? {
        library.files.first { $0.id == selectedDocument } ?? selectedDocument.flatMap { editors[$0]?.document }
    }
    /// The editor session of the open file.
    var editor: EditorSession? { selectedDocument.flatMap { editors[$0] } }
    var editorPage: EditorPage {
        if let loadedEditorPage { return loadedEditorPage }
        let page = EditorPage(files: self)
        loadedEditorPage = page
        return page
    }

    /// Opens a file that a run wrote, in the folder it ran in.
    ///
    /// The file can be newer than the last scan. The editor then opens it when
    /// the next scan finds it.
    func openRunFile(_ path: String, in folder: String) {
        let root = Vault(path: folder).root
        if root != library.vault.root {
            library.changeWiki(to: folder)
            guard library.vault.root == root else { return }
        }
        if library.files.contains(where: { $0.id == path }) {
            openDocument(path)
        } else {
            pendingDocument = path
            library.reload()
        }
        desk?.open(.file)
    }

    func openDocument(_ path: String, anchor: String? = nil) {
        if path == selectedDocument {
            beginEdit()
            if let anchor { jump(to: anchor) }
            return
        }
        guard library.files.contains(where: { $0.id == path }) else { return }
        workspace.open(WikiLocation(path: path, anchor: anchor))
        pruneEditors()
        beginEdit()
        jump(to: anchor)
    }

    /// Back with -1, Forward with 1.
    func navigate(_ offset: Int) {
        let next = workspace.position + offset
        guard workspace.history.indices.contains(next) else { return }
        workspace.move(offset)
        pruneEditors()
        beginEdit()
        jump(to: workspace.location?.anchor)
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
        let saved = session.save(in: library.vault)
        refreshFile(of: session)
        pruneEditors()
        return saved
    }

    /// Saves the open file at once, with the newest text of the editor page.
    func save() async {
        await flushEditor()
        if let editor { saveEditor(editor) }
    }

    /// Shows the find bar of the editor page.
    func find() {
        loadedEditorPage?.webView.findInPage(nil)
    }

    /// Writes the editor text over a change on disk.
    func keepEditorText() {
        guard let session = editor else { return }
        session.keepMine(in: library.vault)
        refreshFile(of: session)
    }

    /// Drops the edits of the open file and loads the text on disk.
    func reloadEditorFromDisk() {
        guard let session = editor else { return }
        session.reloadFromDisk(in: library.vault)
        refreshFile(of: session)
    }

    /// True when a Piper session wrote the file in the last 10 minutes, or is still running.
    func sessionWrote(_ path: String) -> Bool {
        let recent = Date().addingTimeInterval(-AppDefaults.Editor.sessionWriteWindow)
        return agents.runner.sessions(in: library.vault.root.path).contains { session in
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
            desk?.open(.file)
            store.report(PiperError("“\(blocked.document.title)” changed on disk while you edited it. Choose Reload or Keep Mine first."))
            return false
        }
        editors = [:]
        return true
    }

    /// Takes the newest text from the editor page, which can be newer than its last save.
    func flushEditor() async {
        guard let page = loadedEditorPage, let (path, text) = await page.flush() else { return }
        editorChanged(path: path, text: text)
    }

    /// Drops the sessions of the files that are not open and that hold no text off disk.
    private func pruneEditors() {
        let kept = editors.filter { $0.key == selectedDocument || $0.value.hasChanges || $0.value.status == .conflict }
        if kept.count != editors.count { editors = kept }
    }

    private func refreshFile(of session: EditorSession) {
        guard !session.hasChanges, session.status == .saved, let file = try? library.vault.file(session.path) else { return }
        session.document = file
        if let index = library.files.firstIndex(where: { $0.id == file.id }) { library.files[index] = file }
    }

    // MARK: - Margin notes of a file

    /// The link of the page note that holds the margin notes of a file.
    func fileLink(_ path: String) -> String {
        let absolute = library.vault.root.appendingPathComponent(path).path
        return "piper-file://" + (absolute.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? absolute)
    }

    /// A file as the margin agent reads it: its title and its blocks.
    private func fileArticle(_ document: VaultFile) -> ReaderArticle {
        let vault = library.vault
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
        return ReaderMarks.payload(store: store, reader: reader, parent: parent.id, article: fileArticle(document), places: NotePlaces())
    }

    /// Runs an action of the selection bar or a margin card of the editor page.
    func performFileAction(_ message: [String: Any], path: String) {
        guard let document = editors[path]?.document ?? library.files.first(where: { $0.id == path }) else { return }
        let link = fileLink(path)
        ReaderMarks.perform(message, store: store, reader: reader, article: fileArticle(document),
                            open: { [weak self] item in self?.desk?.open(item) }) { [store] in
            store.pageNote(for: link, title: document.title, source: ReaderAssistant.source)?.id
        }
    }

    // MARK: - Links and images

    /// Follows a link that the reader clicked in the editor.
    func openEditorLink(kind: String, target: String) {
        guard let document = currentDocument else { return }
        if kind == "wiki" {
            do {
                let location = try WikiLinks.resolve(target, from: document, files: library.files, vault: library.vault, wikiStyle: true)
                openDocument(location.path, anchor: location.anchor)
            } catch { store.report(error) }
            return
        }
        let encoded = target.addingPercentEncoding(withAllowedCharacters: .urlFragmentAllowed)
        guard let url = URL(string: target) ?? encoded.flatMap(URL.init(string:)) else { return }
        openLink(url, from: document)
    }

    private func openLink(_ url: URL, from document: VaultFile) {
        if ["http", "https", "mailto"].contains(url.scheme ?? "") { NSWorkspace.shared.open(url); return }
        guard url.scheme == nil || url.isFileURL else { return }
        do {
            let target = url.path + (url.fragment.map { "#" + $0 } ?? "")
            let location = try WikiLinks.resolve(target, from: document, files: library.files, vault: library.vault)
            openDocument(location.path, anchor: location.anchor)
        } catch { store.report(error) }
    }

    /// Writes a pasted image next to a note, as `<note>.assets/<hash>.<ext>`,
    /// and returns the path for the Markdown, relative to the note.
    func saveEditorImage(for path: String, type: String, base64: String) throws -> String {
        guard let data = Data(base64Encoded: base64), !data.isEmpty else { throw PiperError("The image is empty.") }
        let hash = SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined().prefix(12)
        let stem = ((path as NSString).lastPathComponent as NSString).deletingPathExtension
        let name = "\(stem).assets/\(hash).\(Self.imageExtension(for: type))"
        try library.vault.write(data, to: ((path as NSString).deletingLastPathComponent as NSString).appendingPathComponent(name))
        return name.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? name
    }

    private static func imageExtension(for type: String) -> String {
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

    private func jump(to anchor: String?) {
        requestedAnchor = anchor
        anchorRequest = UUID()
    }
}

// MARK: - LibraryDelegate

extension FileEditor: LibraryDelegate {
    func librarySettle(_ library: Library) -> Bool {
        settleEditors()
    }

    func libraryDidChangeFolder(_ library: Library) {
        workspace = WikiWorkspace()
        initialDocument = nil
    }

    /// Follows the scan: reloads changed HTML embeds, marks the sessions of
    /// changed files, keeps a deleted file with edits open, and opens the file
    /// that waits for the scan.
    func library(_ library: Library, didScan previous: [VaultFile]) {
        let files = library.files
        let firstLoad = previous.isEmpty && workspace.history.isEmpty
        let dates = Dictionary(previous.map { ($0.id, $0.modifiedAt) }, uniquingKeysWith: { first, _ in first })
        for file in files where ["html", "htm"].contains((file.id as NSString).pathExtension.lowercased()) {
            if let date = dates[file.id], date != file.modifiedAt { loadedEditorPage?.assetChanged(file.id) }
        }
        let previousLocation = workspace.location
        var paths = Set(files.map(\.id))
        for (path, session) in editors {
            if let file = files.first(where: { $0.id == path }) {
                if file.raw != session.baseline { session.diskChanged(in: library.vault) }
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
            openDocument(first.id)
        }
    }
}
