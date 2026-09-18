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
    private var panelController: CapturePanelController?
    private var mainWindowController: MainWindowController?
    private var settingsWindowController: SettingsWindowController?
    private var editors: [UUID: NSWindow] = [:]
    private var editorSessions: [ObjectIdentifier: CaptureEditSession] = [:]
    private var statusItem: NSStatusItem?
    private var refresh: Timer?
    private var toast: NSPanel?
    private var toastDismiss: DispatchWorkItem?
    private let model = AppModel()
    private var capture: CaptureService?
    private let sendShortcut = SendShortcut()
    private var sendClipboardItem: NSMenuItem?
    private var terminateSignal: DispatchSourceSignal?

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.regular)
        installMenus()
        model.openNoteEditor = { [weak self] note in self?.showEditor(note) }
        model.openPanel = { [weak self] in self?.showPanel() }
        model.openLibrary = { [weak self] in self?.showLibrary() }
        model.openSettings = { [weak self] in self?.settings() }
        model.showFile = { [weak self] path in
            self?.showLibrary()
            self?.mainWindowController?.showFile(path)
        }
        model.showNote = { [weak self] id in
            self?.showLibrary()
            self?.mainWindowController?.showNote(id)
        }
        model.showSession = { [weak self] id in
            self?.showLibrary()
            self?.mainWindowController?.showSession(id)
        }
        let capture = CaptureService(model: model)
        capture.didCapture = { [weak self] text, noteID in self?.captured(text, noteID: noteID) }
        sendShortcut.action = { [weak self] in self?.sendClipboard() }
        sendShortcut.failure = { [weak self] message in self?.model.store.report(PiperError(message)) }
        sendShortcut.update(enabled: !model.agents.folders.isEmpty)
        stopRunsOnTerminateSignal()
        self.capture = capture
        model.captureShortcutChanged = { [weak capture] in capture?.start() }
        capture.start()
        model.clipboard.start()
        model.initialDocument = MainWindowState.restore().selectedFile
        model.reload()
        refresh = Timer.scheduledTimer(withTimeInterval: 4, repeats: true) { [weak self] _ in
            Task { @MainActor in
                self?.capture?.start()
                self?.sendShortcut.update(enabled: self?.model.agents.folders.isEmpty == false)
                if self?.mainWindowController?.window?.isVisible == true { self?.model.reload() }
            }
        }
        showPanel()
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
        for (title, action, key) in [("Undo", Selector(("undo:")), "z"), ("Cut", #selector(NSText.cut(_:)), "x"), ("Copy", #selector(NSText.copy(_:)), "c"), ("Paste", #selector(NSTextView.pasteAsPlainText(_:)), "v"), ("Select All", #selector(NSText.selectAll(_:)), "a")] {
            edit.addItem(withTitle: title, action: action, keyEquivalent: key)
        }
        let editItem = NSMenuItem(title: "Edit", action: nil, keyEquivalent: "")
        editItem.submenu = edit
        main.addItem(editItem)
        // Keys that the Wiki window used to handle through an event monitor.
        // A menu item puts them on the responder chain instead, which is where
        // AppKit expects them and which shows them to the reader.
        let fileMenu = NSMenu(title: "File")
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
        goMenu.addItem(withTitle: "Search", action: #selector(searchWiki), keyEquivalent: "o").target = self
        let goItem = NSMenuItem(title: "Go", action: nil, keyEquivalent: "")
        goItem.submenu = goMenu
        main.addItem(goItem)

        let windowMenu = NSMenu(title: "Window")
        windowMenu.addItem(withTitle: "Capture Panel", action: #selector(showPanel), keyEquivalent: "1").target = self
        windowMenu.addItem(withTitle: "Main Window", action: #selector(showBrowser), keyEquivalent: "2").target = self
        windowMenu.addItem(withTitle: "Home", action: #selector(showHome), keyEquivalent: "0").target = self
        let claudePane = windowMenu.addItem(withTitle: "Claude Pane", action: #selector(toggleClaudePane), keyEquivalent: "c")
        claudePane.keyEquivalentModifierMask = [.command, .option]
        claudePane.target = self
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
        menu.addItem(withTitle: "Capture Panel", action: #selector(showPanel), keyEquivalent: "").target = self
        menu.addItem(withTitle: "Main Window", action: #selector(showBrowser), keyEquivalent: "").target = self
        menu.addItem(withTitle: "Home", action: #selector(showHome), keyEquivalent: "").target = self
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

    /// Shows the capture panel and takes the main window off the screen.
    ///
    /// The two surfaces are exclusive. One of them is in front at a time, and
    /// the toolbar button of each one switches to the other.
    @objc func showPanel() {
        if panelController == nil { panelController = CapturePanelController(model: model) }
        mainWindowController?.hide()
        panelController?.show()
    }

    /// Shows the main window and takes the capture panel off the screen.
    @objc func showLibrary() {
        if mainWindowController == nil {
            let controller = MainWindowController(model: model)
            controller.window?.delegate = self
            mainWindowController = controller
        }
        panelController?.hide()
        mainWindowController?.show()
    }

    @objc func showHome() {
        showLibrary()
        mainWindowController?.showHome()
    }

    /// Opens or closes the Claude pane. A hidden window comes back with the pane open.
    @objc private func toggleClaudePane() {
        let visible = mainWindowController?.window?.isVisible == true
        showLibrary()
        if visible { mainWindowController?.toggleSessionPane() } else { mainWindowController?.showSessionPane() }
    }

    /// Shows the window and its browser. Showing the window alone leaves the
    /// home page in front, which is not what the menu item names.
    @objc func showBrowser() {
        showLibrary()
        mainWindowController?.showBrowser()
    }

    @objc private func saveFile() { model.saveWikiEdit() }
    @objc private func refreshVault() { model.reload(); mainWindowController?.refreshPanes() }
    @objc private func goBack() { model.navigate(-1); mainWindowController?.refreshPanes() }
    @objc private func goForward() { model.navigate(1); mainWindowController?.refreshPanes() }
    @objc private func searchWiki() { showHome() }

    @objc private func settings() {
        if settingsWindowController == nil { settingsWindowController = SettingsWindowController(model: model) }
        settingsWindowController?.show()
    }
    @objc private func clipboard() { model.captureClipboard(); showToast(model.store.status) }

    /// Names the default folder in the menu bar item, and hides the item when
    /// no folder has Claude skills.
    func menuNeedsUpdate(_ menu: NSMenu) {
        model.agents.refresh(paths: model.wikiPaths)
        sendClipboardItem?.isHidden = model.agents.folders.isEmpty
        sendClipboardItem?.title = "Send Clipboard to " + (model.agents.defaultFolder?.name ?? "Folder")
    }

    /// Saves the clipboard to Inbox and sends it to the default folder.
    @objc private func sendClipboard() {
        guard let run = model.agents.sendPasteboard() else {
            showToast(model.store.status)
            return
        }
        showRunToast(run)
    }

    /// Confirms a selection capture. A note that a folder can take gets a Send button.
    private func captured(_ text: String, noteID: UUID?) {
        guard let noteID, let note = model.store.notes.first(where: { $0.id == noteID }),
              let action = model.agents.defaultAction(for: note.text) else {
            showToast(text)
            return
        }
        showToast(text, action: ToastAction(title: "Send to " + action.folder.name) { [weak self] in
            guard let self, let session = model.agents.send(note, action: action) else { return }
            showRunToast(session)
        })
    }

    private func showRunToast(_ session: AgentSession) {
        showToast(model.store.status, action: session.noteID.map { id in
            ToastAction(title: "Show") { [weak self] in self?.model.showNote?(id) }
        })
    }

    private func showToast(_ text: String, action: ToastAction? = nil) {
        toastDismiss?.cancel()
        toast?.close()
        let window = NSPanel(contentRect: NSRect(x: 0, y: 0, width: 340, height: 44), styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        window.level = .floating
        window.isOpaque = false
        window.backgroundColor = .clear
        window.hasShadow = true
        window.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        window.contentView = FirstMouseHostingView(rootView: ToastView(text: text, action: action.map { action in
            ToastAction(title: action.title) { [weak window] in
                window?.orderOut(nil)
                action.perform()
            }
        }))
        if let screen = NSScreen.main { window.setFrameOrigin(NSPoint(x: screen.visibleFrame.maxX - 370, y: screen.visibleFrame.minY + 30)) }
        window.orderFrontRegardless()
        toast = window
        let dismiss = DispatchWorkItem { [weak window] in window?.orderOut(nil) }
        toastDismiss = dismiss
        DispatchQueue.main.asyncAfter(deadline: .now() + (action == nil ? 3 : AppDefaults.Agents.actionToastDuration), execute: dismiss)
    }

    /// Brings the open windows forward on a Dock click. With no window open,
    /// the click opens the main window. The capture panel has its own shortcut.
    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        if !flag { showLibrary() }
        return true
    }

    func windowShouldClose(_ sender: NSWindow) -> Bool {
        if sender === mainWindowController?.window { return model.finishWikiEdit() }
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
        dismissAttachedSheet()
        if !confirmStoppingRuns() { return .terminateCancel }
        for session in Array(model.captureEdits.values) {
            if !resolveCaptureEdit(session) { return .terminateCancel }
        }
        if model.finishWikiEdit() { return .terminateNow }
        showLibrary()
        return .terminateCancel
    }

    /// Stops the Claude runs when the process gets SIGTERM, for example from
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

    /// Asks before quitting stops Claude sessions that are in a turn.
    private func confirmStoppingRuns() -> Bool {
        let count = model.agents.runner.activeCount
        guard count > 0 else { return true }
        let alert = NSAlert()
        alert.messageText = count == 1 ? "Stop the Claude session and quit?" : "Stop \(count) Claude sessions and quit?"
        alert.informativeText = "A stopped turn can leave some files changed in its folder. You can continue the session after you open Piper again."
        alert.addButton(withTitle: "Stop and Quit")
        alert.addButton(withTitle: "Cancel").keyEquivalent = "\u{1b}"
        return alert.runModal() == .alertFirstButtonReturn
    }

    /// Closes a sheet on any window, so that a modal alert can appear.
    private func dismissAttachedSheet() {
        mainWindowController?.dismissAttachedSheet()
        panelController?.dismissAttachedSheet()
        model.route = "wiki"
    }

    func applicationWillTerminate(_ notification: Notification) {
        capture?.stop()
        sendShortcut.unregister()
        model.agents.runner.stopAll()
        model.clipboard.stop()
        refresh?.invalidate()
    }
}

/// A button on the toast.
private struct ToastAction {
    let title: String
    let perform: () -> Void
}

/// The toast takes a click without first becoming the key window.
private final class FirstMouseHostingView<Content: View>: NSHostingView<Content> {
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
}

private struct ToastView: View {
    let text: String
    let action: ToastAction?
    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: "checkmark.circle.fill").font(.system(size: 14)).foregroundStyle(PiperTheme.accent)
            Text(text).font(PiperTheme.ui(13)).lineLimit(1).help(text)
            Spacer(minLength: 0)
            if let action {
                Button(action.title, action: action.perform)
                    .buttonStyle(.borderedProminent).controlSize(.small)
            } else {
                Text("⌘1").font(PiperTheme.ui(11)).foregroundStyle(PiperTheme.faint)
            }
        }
        .foregroundStyle(PiperTheme.ink)
        .padding(.horizontal, 14).frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: PiperTheme.cardRadius))
        .overlay(RoundedRectangle(cornerRadius: PiperTheme.cardRadius).strokeBorder(PiperTheme.rule, lineWidth: 0.5))
    }
}
