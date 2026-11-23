import AppKit
import SwiftUI
import Agents
import Captures
import PiperCore

@main
struct PiperApp {
    @MainActor static func main() {
        let application = NSApplication.shared
        if let identifier = Bundle.main.bundleIdentifier,
           let existing = NSRunningApplication.runningApplications(withBundleIdentifier: identifier).first(where: { $0.processIdentifier != ProcessInfo.processInfo.processIdentifier }),
           let url = existing.bundleURL {
            NSWorkspace.shared.open(url)
            return
        }
        let delegate = AppDelegate()
        application.delegate = delegate
        withExtendedLifetime(delegate) { application.run() }
    }
}

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate, NSWindowDelegate, NSMenuDelegate {
    private let model: AppModel
    /// Opens every paper. It exists before the first scan, which opens the file that the file paper restores.
    private let desk: PaperDesk
    private var settingsWindowController: SettingsWindowController?
    private var editors: [UUID: NSWindow] = [:]
    private var editorSessions: [ObjectIdentifier: CaptureEditSession] = [:]
    private var statusItem: NSStatusItem?
    private var refresh: Timer?
    private let toast = Toast()
    private var readingToast: ReadingToast?
    private var palette: CommandPaletteController?
    private var capture: CaptureService?
    private let sendShortcut = SendShortcut()
    private var sendClipboardItem: NSMenuItem?
    private var terminateSignal: DispatchSourceSignal?
    #if DEBUG
    private var qaScripts: QAScripts?
    #endif

    override init() {
        let model = AppModel()
        self.model = model
        desk = PaperDesk(model: model)
        super.init()
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        model.feeds.start()
        NSApp.setActivationPolicy(.regular)
        installMenus()
        model.openNoteEditor = { [weak self] note in self?.showEditor(note) }
        model.openSettings = { [weak self] in self?.settings() }
        if model.sessionPresentation == .detached { DispatchQueue.main.async { [weak self] in self?.desk.showSessionPanel() } }
        model.messages.present = { [toast] message in toast.show(message) }
        if let message = model.messages.last { toast.show(message) }
        let readingToast = ReadingToast(store: model.store, toast: toast, messages: model.messages)
        readingToast.open = { [weak self] id in self?.showArticle(id) }
        self.readingToast = readingToast
        let capture = CaptureService(store: model.store, messages: model.messages, shortcut: { [weak model] in model?.captureShortcut ?? "" },
                                     accessibilityChanged: { [weak model] enabled in model?.accessibilityEnabled = enabled })
        capture.didCapture = { [weak self] outcome in self?.captured(outcome) }
        capture.shownHighlight = { [weak readingToast] in readingToast?.shownHighlight }
        sendShortcut.action = { [weak self] in self?.sendClipboard() }
        sendShortcut.failure = { [weak self] message in self?.model.messages.report(PiperError(message)) }
        sendShortcut.update(enabled: !model.agents.folders.isEmpty)
        stopRunsOnTerminateSignal()
        self.capture = capture
        model.captureShortcutChanged = { [weak capture] in capture?.start() }
        // In QA mode, Piper records neither the clipboard nor the selections of the
        // user, so that no private text gets into a test or a screenshot.
        if !QA.isOn {
            capture.start()
            model.clipboard.start()
        }
        refresh = Timer.scheduledTimer(withTimeInterval: 4, repeats: true) { [weak self] _ in
            Task { @MainActor in
                if !QA.isOn { self?.capture?.start() }
                self?.sendShortcut.update(enabled: self?.model.agents.folders.isEmpty == false)
                if self?.desk.isVisible == true { self?.model.library.reload() }
            }
        }
        #if DEBUG
        if QA.isOn { qaScripts = QAScripts(model: model, desk: desk) }
        #endif
        showLibrary()
    }

    private func installMenus() {
        let main = NSMenu()
        let application = NSMenu()
        let appItem = NSMenuItem()
        application.addItem(withTitle: "About Piper", action: #selector(NSApplication.orderFrontStandardAboutPanel(_:)), keyEquivalent: "")
        application.addItem(.separator())
        application.addItem(withTitle: "Settings...", action: #selector(settings), keyEquivalent: ",").target = self
        application.addItem(.separator())
        application.addItem(withTitle: "Quit Piper", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        appItem.submenu = application
        main.addItem(appItem)
        let edit = NSMenu(title: "Edit")
        for (title, action, key) in [("Undo", Selector(("undo:")), "z"), ("Redo", Selector(("redo:")), "Z"), ("Cut", #selector(NSText.cut(_:)), "x"), ("Copy", #selector(NSText.copy(_:)), "c"), ("Paste", #selector(NSTextView.pasteAsPlainText(_:)), "v"), ("Select All", #selector(NSText.selectAll(_:)), "a")] {
            edit.addItem(withTitle: title, action: action, keyEquivalent: key)
        }
        edit.addItem(.separator())
        edit.addItem(withTitle: "Find…", action: #selector(EditorWebView.findInPage(_:)), keyEquivalent: "f")
        let editItem = NSMenuItem(title: "Edit", action: nil, keyEquivalent: "")
        editItem.submenu = edit
        main.addItem(editItem)
        // A menu item puts these keys on the responder chain, which is where
        // AppKit expects them and which shows them to the reader.
        let fileMenu = NSMenu(title: "File")
        fileMenu.addItem(withTitle: "New Capture", action: #selector(newCapture), keyEquivalent: "n").target = self
        fileMenu.addItem(withTitle: "Add Feed…", action: #selector(addFeed), keyEquivalent: "N").target = self
        fileMenu.addItem(withTitle: "Save", action: #selector(saveFile), keyEquivalent: "s").target = self
        fileMenu.addItem(withTitle: "Refresh", action: #selector(refreshVault), keyEquivalent: "r").target = self
        fileMenu.addItem(.separator())
        fileMenu.addItem(withTitle: "Close Window", action: #selector(NSWindow.performClose(_:)), keyEquivalent: "w")
        let fileItem = NSMenuItem(title: "File", action: nil, keyEquivalent: "")
        fileItem.submenu = fileMenu
        main.addItem(fileItem)

        let goMenu = NSMenu(title: "Go")
        goMenu.addItem(withTitle: "Back", action: #selector(goBack), keyEquivalent: "[").target = self
        goMenu.addItem(withTitle: "Forward", action: #selector(goForward), keyEquivalent: "]").target = self
        goMenu.addItem(.separator())
        goMenu.addItem(withTitle: "Go to File…", action: #selector(showPalette), keyEquivalent: "k").target = self
        let goItem = NSMenuItem(title: "Go", action: nil, keyEquivalent: "")
        goItem.submenu = goMenu
        main.addItem(goItem)

        let windowMenu = NSMenu(title: "Window")
        windowMenu.addItem(withTitle: "Today", action: #selector(newCapture), keyEquivalent: tabKey(.today)).target = self
        windowMenu.addItem(withTitle: "Feeds", action: #selector(showFeeds), keyEquivalent: tabKey(.feeds)).target = self
        windowMenu.addItem(withTitle: "Feed Paper", action: #selector(showLibrary), keyEquivalent: "0").target = self
        windowMenu.addItem(withTitle: "Next Paper", action: #selector(nextPaper), keyEquivalent: "`").target = self
        let sessionCard = windowMenu.addItem(withTitle: "Session Card", action: #selector(toggleSessionCard), keyEquivalent: "c")
        sessionCard.keyEquivalentModifierMask = [.command, .option]
        sessionCard.target = self
        let windowItem = NSMenuItem(title: "Window", action: nil, keyEquivalent: "")
        windowItem.submenu = windowMenu
        main.addItem(windowItem)
        NSApp.mainMenu = main
        let status = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        if let mark = PiperTheme.mark?.copy() as? NSImage {
            mark.isTemplate = true
            mark.size = NSSize(width: 20, height: 20 * mark.size.height / mark.size.width)
            status.button?.image = mark
            status.button?.setAccessibilityLabel("Piper")
        }
        let menu = NSMenu()
        menu.addItem(withTitle: "New Capture", action: #selector(newCapture), keyEquivalent: "").target = self
        menu.addItem(withTitle: "Feed Paper", action: #selector(showLibrary), keyEquivalent: "").target = self
        menu.addItem(withTitle: "Capture Clipboard", action: #selector(clipboard), keyEquivalent: "").target = self
        let send = menu.addItem(withTitle: "Send Clipboard", action: #selector(sendClipboard), keyEquivalent: "w")
        send.keyEquivalentModifierMask = [.control, .option]
        send.target = self
        sendClipboardItem = send
        menu.addItem(withTitle: "Settings...", action: #selector(settings), keyEquivalent: "").target = self
        menu.addItem(.separator())
        menu.addItem(withTitle: "Quit Piper", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        menu.delegate = self
        status.menu = menu
        statusItem = status
    }

    private func showEditor(_ note: Note) {
        if let existing = editors[note.id], existing.isVisible { existing.makeKeyAndOrderFront(nil); return }
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 480, height: 360), styleMask: [.titled, .closable, .resizable], backing: .buffered, defer: false)
        window.title = "Edit Note"
        window.isReleasedWhenClosed = false
        window.delegate = self
        let session = model.editCapture(note)
        editorSessions[ObjectIdentifier(window)] = session
        window.contentView = NSHostingView(rootView: NoteEditor(model: model, session: session, cancel: { [weak window] in window?.close() }) { [weak self, weak window] in
            if self?.model.saveCaptureEdit(session) == true { window?.close() }
        })
        window.center()
        window.makeKeyAndOrderFront(nil)
        editors[note.id] = window
    }

    /// Shows the feed paper and the open reader papers.
    @objc func showLibrary() {
        desk.show()
    }

    /// Shows the feed paper on Today, with the cursor in its capture field.
    @objc private func newCapture() {
        desk.newCapture()
    }

    /// Shows the feed paper on the Feeds tab, with Sources.
    @objc private func showFeeds() {
        desk.showSources()
    }

    @objc private func addFeed() {
        desk.addFeed()
    }

    /// The number key of Today or Feeds: the same number that the feed paper
    /// reads, because these tabs always lead the column.
    private func tabKey(_ tab: PaperTab) -> String {
        PaperTab.number(of: tab, in: PaperTab.column(folders: [], showsAgents: false)).map(String.init) ?? ""
    }

    /// Gives the keyboard focus to the next paper.
    @objc private func nextPaper() {
        desk.cycle()
    }

    @objc private func toggleSessionCard() {
        desk.toggleSessionCard()
    }

    /// Shows a link capture of the reading toast in the opening tab of its site.
    private func showArticle(_ id: UUID) {
        if let note = model.store.notes.first(where: { $0.id == id }) {
            model.chooseArticleTab(model.openingTab(for: note), for: note)
        }
        desk.open(.note(id))
    }

    /// Saves the open file at once. The editor saves by itself 120 ms after an edit.
    @objc private func saveFile() {
        Task { @MainActor in await model.files.save() }
    }

    @objc private func refreshVault() { model.library.reload() }
    @objc private func goBack() { model.files.navigate(-1) }
    @objc private func goForward() { model.files.navigate(1) }

    /// Opens the command palette over the paper with the keyboard focus, or over the feed paper.
    @objc private func showPalette() {
        let key = NSApp.keyWindow
        if !(key?.windowController is FeedPaperController || key?.windowController is ReaderPaperController) {
            showLibrary()
        }
        guard let window = NSApp.keyWindow ?? desk.feedWindow else { return }
        if palette == nil { palette = CommandPaletteController(library: model.library, files: model.files) }
        palette?.toggle(over: window, commands: paletteCommands) { [weak self] path in
            self?.desk.openFile(path)
        }
    }

    private var paletteCommands: [PaletteCommand] {
        [
            PaletteCommand(title: "New Capture", shortcut: "⌘N") { [weak self] in self?.newCapture() },
            PaletteCommand(title: "Feeds", shortcut: "⌘" + tabKey(.feeds)) { [weak self] in self?.showFeeds() },
            PaletteCommand(title: "Add Feed", shortcut: "⇧⌘N") { [weak self] in self?.desk.addFeed() },
            PaletteCommand(title: "Find in File", shortcut: "⌘F") { [weak self] in self?.model.files.find() },
            PaletteCommand(title: model.files.showsFileSource ? "Show Preview" : "Show Source", shortcut: "") { [weak self] in
                self?.model.files.showsFileSource.toggle()
            },
            PaletteCommand(title: "Back", shortcut: "⌘[") { [weak self] in self?.goBack() },
            PaletteCommand(title: "Forward", shortcut: "⌘]") { [weak self] in self?.goForward() },
            PaletteCommand(title: "Refresh", shortcut: "⌘R") { [weak self] in self?.refreshVault() },
            PaletteCommand(title: "Settings", shortcut: "⌘,") { [weak self] in self?.settings() },
        ]
    }

    @objc private func settings() {
        if settingsWindowController == nil { settingsWindowController = SettingsWindowController(model: model) }
        settingsWindowController?.show()
    }
    @objc private func clipboard() { model.captureClipboard() }

    /// Names the default folder in the menu bar item, and hides the item when
    /// no folder has Claude skills.
    func menuNeedsUpdate(_ menu: NSMenu) {
        model.agents.refresh(paths: model.library.wikiPaths)
        sendClipboardItem?.isHidden = model.agents.folders.isEmpty
        sendClipboardItem?.title = "Send Clipboard to " + (model.agents.defaultFolder?.name ?? "Folder")
    }

    /// Saves the clipboard to Inbox and opens a draft in the default folder.
    @objc private func sendClipboard() {
        do {
            let run = try model.agents.sendPasteboard()
            desk.open(.session(run.id))
            showRunToast(run)
        } catch {
            model.messages.report(error)
        }
    }

    /// Confirms a capture. A web page capture shows the reading toast.
    private func captured(_ outcome: CaptureOutcome) {
        switch outcome {
        case .note(let note):
            captured(note)
        case .highlight(let article, let highlight):
            readingToast?.show(.highlight(article: article, highlight: highlight))
        case .article(let article, let isNew):
            readingToast?.show(.article(article, isNew: isNew))
        case .comment(let highlight):
            readingToast?.show(.comment(highlight: highlight))
        }
    }

    /// Confirms a selection capture. A note that a folder can take gets a Send button.
    private func captured(_ note: Note) {
        let text = "Saved to \(note.section)"
        guard let action = model.agents.defaultAction(for: note.text) else { return model.messages.show(text) }
        model.messages.show(text, action: Message.Action(title: "Send to " + action.folder.name) { [weak self] in
            guard let self else { return }
            do {
                let session = try model.agents.send(note, action: action)
                desk.open(.session(session.id))
                showRunToast(session)
            } catch {
                model.messages.report(error)
            }
        })
    }

    private func showRunToast(_ session: AgentSession) {
        model.messages.show("Draft in \(session.folderName)", action: session.noteID.map { id in
            Message.Action(title: "Show") { [weak self] in self?.desk.open(.note(id)) }
        })
    }

    /// Brings the open windows forward on a Dock click. With no window open,
    /// the click opens the feed paper.
    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        if !flag { showLibrary() }
        return true
    }

    func windowShouldClose(_ sender: NSWindow) -> Bool {
        if let session = editorSessions[ObjectIdentifier(sender)] { return resolveCaptureEdit(session) }
        return true
    }

    func windowWillClose(_ notification: Notification) {
        guard let window = notification.object as? NSWindow,
              let session = editorSessions.removeValue(forKey: ObjectIdentifier(window)) else { return }
        model.captureEdits.removeValue(forKey: session.id)
        editors.removeValue(forKey: session.note.id)
    }

    private func resolveCaptureEdit(_ session: CaptureEditSession) -> Bool {
        guard session.hasChanges else { return true }
        let alert = NSAlert()
        alert.messageText = "Save changes to this note?"
        alert.informativeText = String(session.text.prefix(160))
        alert.addButton(withTitle: "Save")
        alert.buttons[0].isEnabled = !session.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        alert.addButton(withTitle: "Discard")
        alert.addButton(withTitle: "Cancel")
        switch alert.runModal() {
        case .alertFirstButtonReturn: return model.saveCaptureEdit(session)
        case .alertSecondButtonReturn: session.text = session.note.text; return true
        default: return false
        }
    }

    func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
        // The guards below ask through a modal alert, and an attached sheet
        // stops that alert from appearing. Quit then does nothing at all, so
        // close the sheet first.
        desk.dismissAttachedSheet()
        if !confirmStoppingRuns() { return .terminateCancel }
        for session in Array(model.captureEdits.values) {
            if !resolveCaptureEdit(session) { return .terminateCancel }
        }
        Task { @MainActor in
            await model.files.flushEditor()
            let settled = model.files.settleEditors()
            if !settled {
                showLibrary()
                desk.open(.file)
            }
            NSApp.reply(toApplicationShouldTerminate: settled)
        }
        return .terminateLater
    }

    /// Stops the agent runs when the process gets SIGTERM, for example from
    /// `kill`. A child process otherwise keeps writing to its folder after
    /// Piper exits.
    private func stopRunsOnTerminateSignal() {
        signal(SIGTERM, SIG_IGN)
        let source = DispatchSource.makeSignalSource(signal: SIGTERM, queue: .main)
        source.setEventHandler { [weak self] in
            MainActor.assumeIsolated {
                self?.model.agents.runner.stopAll()
                exit(0)
            }
        }
        source.resume()
        terminateSignal = source
    }

    /// Asks before quitting stops agent sessions that are in a turn.
    private func confirmStoppingRuns() -> Bool {
        let count = model.agents.runner.activeCount
        guard count > 0 else { return true }
        let alert = NSAlert()
        alert.messageText = count == 1 ? "Stop the agent session and quit?" : "Stop \(count) agent sessions and quit?"
        alert.informativeText = "A stopped turn can leave some files changed in its folder. You can continue the session after you open Piper again."
        alert.addButton(withTitle: "Stop and Quit")
        alert.addButton(withTitle: "Cancel").keyEquivalent = "\u{1b}"
        return alert.runModal() == .alertFirstButtonReturn
    }

    func applicationWillTerminate(_ notification: Notification) {
        capture?.stop()
        sendShortcut.unregister()
        model.agents.runner.stopAll()
        model.clipboard.stop()
        refresh?.invalidate()
    }
}
