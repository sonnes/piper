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
final class AppDelegate: NSObject, NSApplicationDelegate, NSWindowDelegate, NSMenuDelegate, NSMenuItemValidation {
    private let model: AppModel
    /// Opens every paper. It exists before the first scan, which opens the file that the file paper restores.
    private let desk: PaperDesk
    private var settingsWindowController: SettingsWindowController?
    private var editors: [UUID: NSWindow] = [:]
    private var editorSessions: [ObjectIdentifier: CaptureEditSession] = [:]
    private var statusItem: NSStatusItem?
    private let toast = Toast()
    private var readingToast: ReadingToast?
    private var palette: CommandPaletteController?
    private var capture: CaptureService?
    private var sendShortcut: SendShortcut?
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
        let readingToast = ReadingToast(store: model.store, toast: toast, messages: model.messages) { [weak model] in
            model?.captureShortcut ?? .shiftShift
        }
        readingToast.open = { [weak self] id in self?.showArticle(id) }
        self.readingToast = readingToast
        let capture = CaptureService(store: model.store, messages: model.messages, shortcut: { [weak model] in model?.captureShortcut ?? .shiftShift },
                                     accessibilityChanged: { [weak model] enabled in model?.accessibilityEnabled = enabled })
        capture.didCapture = { [weak self] outcome in self?.captured(outcome) }
        capture.shownHighlight = { [weak readingToast] in readingToast?.shownHighlight }
        let sendShortcut = SendShortcut { [weak self] in self?.sendClipboard() }
        sendShortcut.failure = { [weak self] message in self?.model.messages.report(PiperError(message)) }
        sendShortcut.update(enabled: !model.skills.folders.isEmpty)
        model.skills.foldersChanged = { [weak self, weak sendShortcut] in
            sendShortcut?.update(enabled: self?.model.skills.folders.isEmpty == false)
        }
        self.sendShortcut = sendShortcut
        stopRunsOnTerminateSignal()
        self.capture = capture
        model.captureShortcutChanged = { [weak capture] in capture?.start() }
        // In QA mode, Piper records neither the clipboard nor the selections of the
        // user, so that no private text gets into a test or a screenshot.
        if !QA.isOn {
            capture.start()
            model.clipboard.start()
        }
        #if DEBUG
        if QA.isOn { qaScripts = QAScripts(model: model, desk: desk) }
        #endif
        showLibrary()
    }

    /// Builds the main menu and the menu of the menu bar item from `Command`.
    /// A menu item puts a key on the responder chain, where AppKit expects it.
    private func installMenus() {
        let main = NSMenu()
        for menu in Command.Menu.allCases {
            let submenu = NSMenu(title: menu.title)
            add(menu.groups, to: submenu)
            let item = NSMenuItem(title: menu.title, action: nil, keyEquivalent: "")
            item.submenu = submenu
            main.addItem(item)
        }
        NSApp.mainMenu = main
        let status = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        if let mark = PiperTheme.mark?.copy() as? NSImage {
            mark.isTemplate = true
            mark.size = NSSize(width: 20, height: 20 * mark.size.height / mark.size.width)
            status.button?.image = mark
            status.button?.setAccessibilityLabel("Piper")
        }
        let menu = NSMenu()
        add(Command.statusMenu, to: menu)
        sendClipboardItem = menu.items.first { $0.representedObject as? Command == .sendClipboard }
        menu.delegate = self
        status.menu = menu
        statusItem = status
    }

    private func add(_ groups: [[Command]], to menu: NSMenu) {
        for (index, group) in groups.enumerated() {
            if index > 0 { menu.addItem(.separator()) }
            for command in group {
                let item = NSMenuItem(title: command.title, action: command.standardAction ?? #selector(performMenuItem(_:)),
                                      keyEquivalent: command.key?.character ?? "")
                if let key = command.key { item.keyEquivalentModifierMask = key.modifiers }
                if command.standardAction == nil { item.target = self }
                item.representedObject = command
                menu.addItem(item)
            }
        }
    }

    @objc private func performMenuItem(_ sender: NSMenuItem) {
        guard let command = sender.representedObject as? Command else { return }
        perform(command)
    }

    func validateMenuItem(_ menuItem: NSMenuItem) -> Bool {
        (menuItem.representedObject as? Command)?.isEnabled(in: commandContext) ?? true
    }

    private var commandContext: Command.Context {
        let window = model.files.loadedEditorPage?.webView.window
        var showsFeedList = false
        if case .feed = desk.paper.state.scope { showsFeedList = true }
        return Command.Context(editorHasFocus: window != nil && window === PaperWindow.focusedWindow, showsFeedList: showsFeedList)
    }

    /// Performs a command of a menu item or of the command palette.
    private func perform(_ command: Command) {
        switch command {
        case .about, .quit, .undo, .redo, .cut, .copy, .paste, .selectAll, .closeWindow:
            if let action = command.standardAction { NSApp.sendAction(action, to: nil, from: nil) }
        case .settings: settings()
        case .find: model.files.find()
        case .newCapture, .today: desk.newCapture()
        case .addFeed: desk.addFeed()
        // The editor also saves by itself 120 ms after an edit.
        case .save: Task { @MainActor in await model.files.save() }
        case .refresh:
            model.library.reload()
            model.skills.reload()
        case .back: model.files.navigate(-1)
        case .forward: model.files.navigate(1)
        case .goToFile: showPalette()
        case .feeds: desk.showSources()
        case .feedPaper: showLibrary()
        case .nextPaper: desk.cycle()
        case .sessionCard: desk.toggleSessionCard()
        case .captureClipboard: model.captureClipboard()
        case .sendClipboard: sendClipboard()
        case .toggleFileSource: model.files.showsFileSource.toggle()
        case .markAllAsRead:
            if case .feed(let id) = desk.paper.state.scope { model.feeds.markAllRead(.feed(id)) }
        }
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
    private func showLibrary() {
        desk.show()
    }

    /// Shows a link capture of the reading toast in the opening tab of its site.
    private func showArticle(_ id: UUID) {
        if let note = model.store.notes.first(where: { $0.id == id }) {
            model.chooseArticleTab(model.openingTab(for: note), for: note)
        }
        desk.open(.note(id))
    }

    /// Opens the command palette over the paper with the keyboard focus, or over the feed paper.
    private func showPalette() {
        if !(NSApp.keyWindow is PaperWindow) { showLibrary() }
        guard let window = NSApp.keyWindow ?? desk.feedWindow else { return }
        if palette == nil { palette = CommandPaletteController(library: model.library, files: model.files) }
        palette?.toggle(over: window, commands: paletteCommands) { [weak self] path in
            self?.desk.openFile(path)
        }
    }

    private var paletteCommands: [PaletteCommand] {
        Command.palette(in: commandContext).map { command in
            let title = command == .toggleFileSource && model.files.showsFileSource ? "Show Preview" : command.title
            return PaletteCommand(title: title, shortcut: command.key?.glyph ?? "") { [weak self] in self?.perform(command) }
        }
    }

    private func settings() {
        if settingsWindowController == nil { settingsWindowController = SettingsWindowController(model: model) }
        checkAccessibility()
        settingsWindowController?.show()
    }

    func applicationDidBecomeActive(_ notification: Notification) {
        checkAccessibility()
    }

    /// The user can take the Accessibility access away while Piper runs.
    /// QA mode never starts the capture service.
    private func checkAccessibility() {
        if !QA.isOn { capture?.start() }
    }

    /// Names the default folder in the menu bar item, and hides the item when
    /// no folder has Claude skills.
    func menuNeedsUpdate(_ menu: NSMenu) {
        sendClipboardItem?.isHidden = model.skills.folders.isEmpty
        sendClipboardItem?.title = Command.sendClipboard.title + " to " + (model.skills.defaultFolder?.name ?? "Folder")
    }

    /// Saves the clipboard to Inbox and opens a draft in the default folder.
    private func sendClipboard() {
        do {
            showRunToast(try model.send.pasteboard())
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
        guard let action = model.skills.defaultAction(for: note.text) else { return model.messages.show(text) }
        model.messages.show(text, action: Message.Action(title: "Send to " + action.folder.name) { [weak self] in
            guard let self else { return }
            do {
                showRunToast(try model.send.note(note, action: action))
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
        sendShortcut?.unregister()
        model.agents.runner.stopAll()
        model.clipboard.stop()
    }
}
