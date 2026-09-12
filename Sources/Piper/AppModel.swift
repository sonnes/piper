import AppKit
import ApplicationServices
import Observation

@MainActor @Observable
final class AppModel {
    let store: AppStore
    let clipboard: ClipboardInbox
    var documents: [WikiDocument] = []
    var wikiProblems: [String] = []
    var wikiError: String?
    var loading = false
    var exporting = false
    var route = "wiki"
    var workspace = WikiWorkspace()
    var wikiEdit: WikiEditSession?
    var confirmWikiChanges: (WikiDocument) -> NSApplication.ModalResponse = { document in
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
    var currentDocument: WikiDocument? { documents.first { $0.id == selectedDocument } }
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

    init(store: AppStore? = nil, wikiPath: String? = nil) {
        let defaults = UserDefaults.standard
        if Bundle.main.bundleIdentifier == "com.piper", !defaults.bool(forKey: "migratedLocalPreferences") {
            let previous = defaults.persistentDomain(forName: "local.piper") ?? [:]
            for key in ["wikiPath", "captureShortcut", "composerDraft", "wikiReaderSize", "NSWindow Frame PiperCapturePanel", "NSWindow Frame PiperLibrary"] {
                if defaults.object(forKey: key) == nil, let value = previous[key] { defaults.set(value, forKey: key) }
            }
            defaults.set(true, forKey: "migratedLocalPreferences")
        }
        let store = store ?? AppStore()
        self.store = store
        clipboard = ClipboardInbox(store: store)
        self.wikiPath = wikiPath ?? UserDefaults.standard.string(forKey: "wikiPath") ?? FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Desktop/Wiki").path
        captureShortcut = UserDefaults.standard.string(forKey: "captureShortcut") ?? "Shift, Shift"
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

    var repository: WikiRepository { WikiRepository(root: URL(fileURLWithPath: (wikiPath as NSString).expandingTildeInPath).standardizedFileURL) }
    var filteredDocuments: [WikiDocument] {
        documents.filter { document in
            wikiQuery.trimmingCharacters(in: .whitespacesAndNewlines).split(separator: " ").allSatisfy { word in
                (document.title + " " + document.relativePath + " " + document.description + " " + document.body).localizedCaseInsensitiveContains(String(word))
            }
        }
    }

    func reload() {
        guard !loading, !exporting, wikiEdit?.hasChanges != true else { return }
        loading = true
        let repo = repository
        let edit = wikiEdit
        let original = edit?.document.raw
        Task {
            let result = await Task.detached { Result { try repo.scan(includeIndexes: true) } }.value
            loading = false
            guard repo.root == repository.root else { reload(); return }
            guard wikiEdit === edit, wikiEdit?.hasChanges != true, wikiEdit?.document.raw == original else { return }
            switch result {
            case .success(let scan):
                wikiProblems = scan.problems
                wikiError = nil
                let firstLoad = documents.isEmpty && workspace.history.isEmpty
                documents = scan.documents
                let previousLocation = workspace.location
                workspace.reconcile(paths: Set(documents.map(\.id)))
                if currentDocument?.id != wikiEdit?.document.id || currentDocument?.raw != wikiEdit?.document.raw { wikiEdit = nil }
                beginWikiEdit()
                if previousLocation != workspace.location { jump(to: workspace.location?.anchor) }
                if firstLoad, let first = documents.first(where: { $0.id == "Start Here.md" }) ?? documents.first(where: { $0.id == "index.md" }) ?? documents.first {
                    openDocument(first.id)
                }
            case .failure(let error):
                documents = []
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
        documents = []
        wikiQuery = ""
        route = "wiki"
        reload()
    }

    func createWiki() {
        guard finishWikiEdit() else { return }
        do { try repository.create(); reload() }
        catch { beginWikiEdit(); store.report(error) }
    }

    func prepareExport() {
        guard !store.selectedNotes.isEmpty else { return }
        exportNotes = store.selectedNotes
    }

    func export(title: String, description: String, destination: String, sourceURL: String) async -> String? {
        exporting = true
        let repo = repository
        let notes = exportNotes
        let result = await Task.detached { Result { try repo.export(notes: notes, title: title, description: description, destination: destination, sourceURL: sourceURL) } }.value
        exporting = false
        switch result {
        case .success(let document):
            route = "wiki"
            if !documents.contains(where: { $0.id == document.id }) { documents.append(document) }
            openDocument(document.id)
            store.status = "Wiki draft saved"
            reload()
            return nil
        case .failure(let error): return error.localizedDescription
        }
    }

    func openLink(_ url: URL, from document: WikiDocument) {
        if url.scheme == "piper-footnote" {
            let id = String(url.path.dropFirst())
            if WikiMarkdown.parse(document.body).contains(where: { $0.anchor == "fn-" + id }) {
                openDocument(document.id, anchor: "fn-" + id)
            } else if let resource = document.sources.first(where: { $0["id"] as? String == id })?["resource"] as? String,
               let source = URL(string: resource), source.scheme != "piper-footnote" { openLink(source, from: document) }
            else { store.status = "See the footnote at the end of the document" }
            return
        }
        if ["http", "https", "mailto"].contains(url.scheme ?? "") { NSWorkspace.shared.open(url); return }
        if url.scheme == "piper-note" || url.scheme == "piper-wiki" || url.scheme == nil || url.isFileURL {
            do {
                let wikiStyle = url.scheme == "piper-note"
                let target = wikiStyle ? URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems?.first(where: { $0.name == "target" })?.value ?? "" : url.path + (url.fragment.map { "#" + $0 } ?? "")
                let location = try WikiLinks.resolve(target, from: document, documents: documents, repository: repository, wikiStyle: wikiStyle)
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
        guard documents.contains(where: { $0.id == path }), finishWikiEdit() else { return }
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
            let saved = try repository.saveBody(edit.markdown, of: edit.document)
            if let index = documents.firstIndex(where: { $0.id == saved.id }) { documents[index] = saved }
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
            let url = try repository.containedURL(edit.document.id)
            let saved = WikiDocument.parse(try String(contentsOf: url, encoding: .utf8), path: edit.document.id)
            if let index = documents.firstIndex(where: { $0.id == saved.id }) { documents[index] = saved }
            edit.document = saved
            edit.text = WikiEditorLinks.encode(saved.editableBody)
        } catch { store.report(error) }
    }

    func jump(to anchor: String?) {
        requestedAnchor = anchor
        anchorRequest = UUID()
    }
}
