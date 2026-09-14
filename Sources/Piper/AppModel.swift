import AppKit
import ApplicationServices
import Observation
import PiperCore
import Captures
import PiperCommands
import Vault

@MainActor @Observable
final class AppModel {
    let store: CaptureStore
    let clipboard: ClipboardInbox
    let agent = WikiAgent()
    var files: [VaultFile] = []
    var wikiProblems: [String] = []
    var wikiError: String?
    var loading = false
    var exporting = false
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
    var currentDocument: VaultFile? { files.first { $0.id == selectedDocument } }
    var wikiQuery = ""
    var requestedAnchor: String?
    var anchorRequest = UUID()
    var accessibilityEnabled = AXIsProcessTrusted()
    var exportNotes: [Note] = []
    var openNoteEditor: ((Note) -> Void)?
    var openPanel: (() -> Void)?
    var openLibrary: (() -> Void)?
    var captureClipboard: (() -> Void)?
    var captureShortcutChanged: (() -> Void)?
    var wikiPath: String {
        didSet { UserDefaults.standard.set(wikiPath, forKey: "wikiPath") }
    }
    var captureShortcut: String {
        didSet {
            UserDefaults.standard.set(captureShortcut, forKey: "captureShortcut")
            captureShortcutChanged?()
        }
    }
    var style = PiperStyle.current {
        didSet { UserDefaults.standard.set(style.rawValue, forKey: PiperStyle.key) }
    }

    init(store: CaptureStore? = nil, wikiPath: String? = nil) {
        let defaults = UserDefaults.standard
        if Bundle.main.bundleIdentifier == "com.piper", !defaults.bool(forKey: "migratedLocalPreferences") {
            let previous = defaults.persistentDomain(forName: "local.piper") ?? [:]
            for key in ["wikiPath", "captureShortcut", "composerDraft", "wikiReaderSize", "NSWindow Frame PiperCapturePanel", "NSWindow Frame PiperLibrary"] {
                if defaults.object(forKey: key) == nil, let value = previous[key] { defaults.set(value, forKey: key) }
            }
            defaults.set(true, forKey: "migratedLocalPreferences")
        }
        let store = store ?? CaptureStore()
        self.store = store
        clipboard = ClipboardInbox(store: store)
        self.wikiPath = wikiPath ?? UserDefaults.standard.string(forKey: "wikiPath") ?? FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Desktop/Wiki").path
        // Control-Option-C was the earlier alternative. A stored value that no
        // longer matches a preset leaves the capture shortcut dead.
        let stored = UserDefaults.standard.string(forKey: "captureShortcut") ?? "Shift, Shift"
        captureShortcut = stored == "Control-Option-C" ? "Control-Option-Space" : stored
    }

    func requestAccessibility() {
        let options = [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true] as CFDictionary
        accessibilityEnabled = AXIsProcessTrustedWithOptions(options)
        NSWorkspace.shared.open(URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility")!)
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
    var filteredFiles: [VaultFile] {
        files.filter { document in
            wikiQuery.trimmingCharacters(in: .whitespacesAndNewlines).split(separator: " ").allSatisfy { word in
                (document.title + " " + document.relativePath + " " + document.summary + " " + document.body).localizedCaseInsensitiveContains(String(word))
            }
        }
    }

    func reload() {
        guard !loading, !exporting, wikiEdit?.hasChanges != true else { return }
        loading = true
        let repo = vault
        let edit = wikiEdit
        let original = edit?.document.raw
        Task {
            let result = await Task.detached { Result { try repo.scan() } }.value
            loading = false
            guard repo.root == vault.root else { reload(); return }
            guard wikiEdit === edit, wikiEdit?.hasChanges != true, wikiEdit?.document.raw == original else { return }
            switch result {
            case .success(let scan):
                wikiProblems = scan.problems
                wikiError = nil
                let firstLoad = files.isEmpty && workspace.history.isEmpty
                files = scan.files
                let previousLocation = workspace.location
                workspace.reconcile(paths: Set(files.map(\.id)))
                if currentDocument?.id != wikiEdit?.document.id || currentDocument?.raw != wikiEdit?.document.raw { wikiEdit = nil }
                beginWikiEdit()
                if previousLocation != workspace.location { jump(to: workspace.location?.anchor) }
                if firstLoad, let first = files.first(where: { $0.id == "Start Here.md" }) ?? files.first(where: { $0.id == "index.md" }) ?? files.first {
                    openDocument(first.id)
                }
            case .failure(let error):
                files = []
                wikiEdit = nil
                wikiError = error.localizedDescription
            }
        }
    }

    func chooseWiki() {
        let panel = NSOpenPanel()
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.allowsMultipleSelection = false
        panel.message = "Choose your Wiki folder."
        guard panel.runModal() == .OK, let url = panel.url else { return }
        guard finishWikiEdit() else { return }
        wikiPath = url.path
        workspace = WikiWorkspace()
        files = []
        wikiQuery = ""
        route = "wiki"
        reload()
    }

    func createWiki() {
        guard finishWikiEdit() else { return }
        do { try vault.create(); reload() }
        catch { beginWikiEdit(); store.report(error) }
    }

    func prepareExport() {
        guard !store.selectedNotes.isEmpty else { return }
        exportNotes = store.selectedNotes
    }

    /// Writes the selected captures to one Markdown file that the reader names.
    ///
    /// The write touches that file and nothing else. Piper builds no index and
    /// appends to no log, because the folder belongs to the reader.
    func export(title: String, sourceURL: String, destination: URL) async -> String? {
        exporting = true
        defer { exporting = false }
        let notes = exportNotes
        do {
            let markdown = try WikiExport.markdown(notes: notes, title: title, sourceURL: sourceURL)
            try Data(markdown.utf8).write(to: destination, options: .atomic)
        } catch { return error.localizedDescription }
        route = "wiki"
        store.status = "Saved to " + destination.lastPathComponent
        reload()
        // The file opens when it sits inside the current folder. A file written
        // elsewhere stays on disk and the browser does not show it.
        if destination.path.hasPrefix(vault.root.path + "/") {
            openDocument(String(destination.path.dropFirst(vault.root.path.count + 1)))
        }
        return nil
    }

    /// The file that Send To Wiki proposes in the save panel.
    func exportDestination(title: String) -> URL {
        vault.root.appendingPathComponent(WikiExport.fileName(title))
    }

    /// Runs a Wiki command, then rescans. The command writes Markdown files
    /// directly, so an open edit must reach disk before it starts.
    func runCommand(_ job: WikiAgentJob, arguments: String) async -> String? {
        guard finishWikiEdit() else { return nil }
        let error = await agent.run(job, arguments: arguments, root: vault.root)
        reload()
        return error
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

    func openDocument(_ path: String, anchor: String? = nil) {
        if path == selectedDocument {
            route = "wiki"
            beginWikiEdit()
            if let anchor { jump(to: anchor) }
            return
        }
        guard files.contains(where: { $0.id == path }), finishWikiEdit() else { return }
        route = "wiki"
        workspace.open(WikiLocation(path: path, anchor: anchor))
        beginWikiEdit()
        jump(to: anchor)
    }

    func navigate(_ offset: Int) {
        let next = workspace.position + offset
        guard workspace.history.indices.contains(next) else { return }
        if workspace.history[next].path != selectedDocument, !finishWikiEdit() { return }
        workspace.move(offset)
        beginWikiEdit()
        jump(to: workspace.location?.anchor)
    }

    func beginWikiEdit() {
        guard wikiEdit == nil, let document = currentDocument else { return }
        wikiEdit = WikiEditSession(document: document)
    }

    @discardableResult func saveWikiEdit() -> Bool {
        guard let edit = wikiEdit, edit.hasChanges else { return true }
        do {
            let saved = try WikiSave.body(edit.markdown, of: edit.document, in: vault)
            if let index = files.firstIndex(where: { $0.id == saved.id }) { files[index] = saved }
            edit.document = saved
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
