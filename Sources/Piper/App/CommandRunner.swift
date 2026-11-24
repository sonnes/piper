import AppKit
import Agents
import Captures
import PiperCore
import SwiftUI

/// Runs the commands of the `Command` table, and owns the windows that a
/// command opens: Settings, the command palette, and the note editors.
///
/// The main menu, the menu bar item, the command palette, and the More menu
/// of the feed paper run each command through `perform(_:)`. A view reaches
/// the runner through `PaperDesk.commands`.
@MainActor
final class CommandRunner: NSObject {

    // MARK: - Properties

    private let model: AppModel
    private let desk: PaperDesk
    private let capture: CaptureService
    private var settingsWindowController: SettingsWindowController?
    private var palette: CommandPaletteController?
    private var editors: [UUID: NSWindow] = [:]
    private var editorSessions: [ObjectIdentifier: CaptureEditSession] = [:]

    // MARK: - Initialization

    init(model: AppModel, desk: PaperDesk, capture: CaptureService) {
        self.model = model
        self.desk = desk
        self.capture = capture
        super.init()
        desk.commands = self
    }

    // MARK: - Commands

    /// The state of the app that enables a command.
    var context: Command.Context {
        let window = model.files.loadedEditorPage?.webView.window
        var showsFeedList = false
        if case .feed = desk.paper.state.scope { showsFeedList = true }
        return Command.Context(editorHasFocus: window != nil && window === PaperWindow.focusedWindow, showsFeedList: showsFeedList)
    }

    func perform(_ command: Command) {
        switch command {
        case .about, .quit, .undo, .redo, .cut, .copy, .paste, .selectAll, .closeWindow:
            if let action = command.standardAction { NSApp.sendAction(action, to: nil, from: nil) }
        case .settings: showSettings()
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
        case .feedPaper: desk.show()
        case .nextPaper: desk.cycle()
        case .sessionCard: desk.toggleSessionCard()
        case .captureClipboard: model.captureClipboard()
        case .sendClipboard: sendClipboard()
        case .toggleFileSource: model.files.showsFileSource.toggle()
        case .markAllAsRead:
            if case .feed(let id) = desk.paper.state.scope { model.articleActions.markAllRead(feed: id) }
        }
    }

    /// Shows the note draft of a session, with a button that opens the note.
    func showDraft(_ session: AgentSession) {
        model.messages.show("Draft in \(session.folderName)", action: session.noteID.map { id in
            Message.Action(title: "Show") { [weak self] in self?.desk.open(.note(id)) }
        })
    }

    // MARK: - Note Editors

    /// Edits a capture in a window of its own.
    func editNote(_ note: Note) {
        if let existing = editors[note.id], existing.isVisible { existing.makeKeyAndOrderFront(nil); return }
        let window = NSWindow(contentRect: NSRect(origin: .zero, size: NoteEditor.Metrics.windowSize),
                              styleMask: [.titled, .closable, .resizable], backing: .buffered, defer: false)
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

    /// Asks about each capture edit with changes before Piper quits.
    ///
    /// - Returns: False when the reader cancels.
    func resolveCaptureEdits() -> Bool {
        Array(model.captureEdits.values).allSatisfy(resolveCaptureEdit)
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
}

// MARK: - NSWindowDelegate

extension CommandRunner: NSWindowDelegate {
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
}

// MARK: - Private

private extension CommandRunner {
    /// Opens the command palette over the paper with the keyboard focus, or over the feed paper.
    func showPalette() {
        if !(NSApp.keyWindow is PaperWindow) { desk.show() }
        guard let window = NSApp.keyWindow ?? desk.feedWindow else { return }
        if palette == nil { palette = CommandPaletteController(library: model.library, files: model.files) }
        palette?.toggle(over: window, commands: paletteCommands) { [weak self] path in
            self?.model.files.openFile(path)
        }
    }

    var paletteCommands: [PaletteCommand] {
        Command.palette(in: context).map { command in
            let title = command == .toggleFileSource && model.files.showsFileSource ? "Show Preview" : command.title
            return PaletteCommand(title: title, shortcut: command.key?.glyph ?? "") { [weak self] in self?.perform(command) }
        }
    }

    /// The reader can take the Accessibility access away while Piper runs,
    /// so Settings checks it again. QA mode never starts the capture service.
    func showSettings() {
        if settingsWindowController == nil { settingsWindowController = SettingsWindowController(model: model) }
        if !QA.isOn { capture.start() }
        settingsWindowController?.show()
    }

    /// Saves the clipboard to Inbox and opens a draft in the default folder.
    func sendClipboard() {
        do {
            showDraft(try model.send.pasteboard())
        } catch {
            model.messages.report(error)
        }
    }
}
