import AppKit
import Agents
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
    var wikiEdit: WikiEditSession?
    var confirmWikiChanges: (VaultFile) -> NSApplication.ModalResponse = { document in
        let alert = NSAlert()
        alert.messageText = "Save changes to “\(document.title)”?"
        alert.informativeText = "Your changes have not been saved to the Markdown file."
        alert.addButton(withTitle: "Save")
        alert.addButton(withTitle: "Discard")
        alert.addButton(withTitle: "Cancel").keyEquivalent = "\u{1b}"
        return alert.runModal()
    }
    var captureEdits: [UUID: CaptureEditSession] = [:]
    var selectedDocument: String? { workspace.location?.path }
    var currentDocument: VaultFile? {
        if let edit = wikiEdit, edit.hasChanges, edit.document.id == selectedDocument { return edit.document }
        return files.first { $0.id == selectedDocument }
    }
    /// What the actions in the toolbar run on. The window sets it with the selection.
    var actionTarget = SkillTarget.folder
    var wikiQuery = ""
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
    /// Shows a session in the Claude pane of the main window.
    var showSession: ((UUID) -> Void)?
    /// The session that the Claude pane and the Claude list show. Nil starts a new session.
    var selectedSession: UUID?
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
        agents.refresh(paths: wikiPaths)
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

    var filteredFiles: [VaultFile] { filteredFiles(in: nil) }

    func filteredFiles(in folder: String?) -> [VaultFile] {
        files.filter { document in
            guard folder == nil || document.folder == folder else { return false }
            return wikiQuery.trimmingCharacters(in: .whitespacesAndNewlines).split(separator: " ").allSatisfy { word in
                (document.title + " " + document.relativePath + " " + document.summary + " " + document.body).localizedCaseInsensitiveContains(String(word))
            }
        }
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
        let edit = wikiEdit
        let original = edit?.document.raw
        Task {
            defer {
                loading = false
                if reloadPending { reload() }
            }
            let result = await Task.detached { Result { try repo.scan() } }.value
            guard repo.root == vault.root, wikiEdit === edit, wikiEdit?.document.raw == original else {
                reloadPending = true
                return
            }
            let hasDraft = wikiEdit?.hasChanges == true
            switch result {
            case .success(let scan):
                wikiProblems = scan.problems
                wikiError = nil
                let firstLoad = files.isEmpty && workspace.history.isEmpty
                files = scan.files
                folders = scan.folders
                let previousLocation = workspace.location
                var paths = Set(files.map(\.id))
                // A deleted file can still have an unsaved draft in the editor.
                if hasDraft, let edit = wikiEdit { paths.insert(edit.document.id) }
                workspace.reconcile(paths: paths)
                if !hasDraft {
                    if currentDocument?.id != wikiEdit?.document.id || currentDocument?.raw != wikiEdit?.document.raw { wikiEdit = nil }
                    beginWikiEdit()
                }
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
                if !hasDraft { wikiEdit = nil }
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
        guard let first = urls.first, finishWikiEdit() else { return }
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
        guard finishWikiEdit() else { return }
        wikiPath = registerWikiFolder(url)
        workspace = WikiWorkspace()
        initialDocument = nil
        files = []
        folders = []
        wikiQuery = ""
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
        guard finishWikiEdit() else { return }
        do { try vault.create(); reload() }
        catch { beginWikiEdit(); store.report(error) }
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
            beginWikiEdit()
            if markAsRead { markCurrentDocumentRead() }
            if let anchor { jump(to: anchor) }
            return
        }
        guard files.contains(where: { $0.id == path }), finishWikiEdit() else { return }
        route = "wiki"
        workspace.open(WikiLocation(path: path, anchor: anchor))
        beginWikiEdit()
        jump(to: anchor)
        if markAsRead { markCurrentDocumentRead() }
    }

    func navigate(_ offset: Int) {
        let next = workspace.position + offset
        guard workspace.history.indices.contains(next) else { return }
        if workspace.history[next].path != selectedDocument, !finishWikiEdit() { return }
        workspace.move(offset)
        beginWikiEdit()
        jump(to: workspace.location?.anchor)
        markCurrentDocumentRead()
    }

    func beginWikiEdit() {
        guard wikiEdit == nil, let document = currentDocument, document.isMarkdown, document.isText else { return }
        wikiEdit = WikiEditSession(document: document)
    }

    @discardableResult func saveWikiEdit() -> Bool {
        guard let edit = wikiEdit, edit.hasChanges else { return true }
        do {
            let saved = try WikiSave.body(edit.markdown, of: edit.document, in: vault)
            if let index = files.firstIndex(where: { $0.id == saved.id }) { files[index] = saved }
            edit.document = saved
            fileReadState.markRead(saved, in: vault.root)
            return true
        } catch {
            store.report(error)
            return false
        }
    }

    @discardableResult func finishWikiEdit() -> Bool {
        if let edit = wikiEdit, edit.hasChanges {
            switch confirmWikiChanges(edit.document) {
            case .alertFirstButtonReturn: guard saveWikiEdit() else { return false }
            case .alertSecondButtonReturn: break
            default: return false
            }
        }
        wikiEdit = nil
        return true
    }

    func discardWikiEdit() {
        guard let edit = wikiEdit else { return }
        do {
            let saved = try vault.read(edit.document.id)
            if let index = files.firstIndex(where: { $0.id == saved.id }) { files[index] = saved }
            edit.document = saved
            edit.text = WikiEditorLinks.encode(saved.editableBody)
        } catch { store.report(error) }
    }

    func jump(to anchor: String?) {
        requestedAnchor = anchor
        anchorRequest = UUID()
    }
}
