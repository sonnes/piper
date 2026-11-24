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
final class AppDelegate: NSObject, NSApplicationDelegate, NSMenuDelegate, NSMenuItemValidation {
    private let model: AppModel
    /// Opens every paper. It exists before the first scan, which opens the file that the file paper restores.
    private let desk: PaperDesk
    private let capture: CaptureService
    private let commands: CommandRunner
    private var statusItem: NSStatusItem?
    private let toast = Toast()
    private var readingToast: ReadingToast?
    private var sendShortcut: SendShortcut?
    private var sendClipboardItem: NSMenuItem?
    private var terminateSignal: DispatchSourceSignal?
    #if DEBUG
    private var qaScripts: QAScripts?
    #endif

    override init() {
        let model = AppModel()
        self.model = model
        let desk = PaperDesk(model: model)
        self.desk = desk
        let capture = CaptureService(store: model.store, messages: model.messages, shortcut: { [weak model] in model?.captureShortcut ?? .shiftShift })
        self.capture = capture
        commands = CommandRunner(model: model, desk: desk, capture: capture)
        super.init()
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        model.feeds.start()
        NSApp.setActivationPolicy(.regular)
        installMenus()
        if model.sessionPresentation == .detached { DispatchQueue.main.async { [weak self] in self?.desk.showSessionPanel() } }
        model.messages.present = { [toast] message in toast.show(message) }
        if let message = model.messages.last { toast.show(message) }
        let readingToast = ReadingToast(store: model.store, toast: toast, messages: model.messages) { [weak model] in
            model?.captureShortcut ?? .shiftShift
        }
        readingToast.open = { [weak self] id in self?.showArticle(id) }
        self.readingToast = readingToast
        capture.didCapture = { [weak self] outcome in self?.captured(outcome) }
        capture.shownHighlight = { [weak readingToast] in readingToast?.shownHighlight }
        let sendShortcut = SendShortcut { [weak self] in self?.commands.perform(.sendClipboard) }
        sendShortcut.failure = { [weak self] message in self?.model.messages.report(PiperError(message)) }
        sendShortcut.update(enabled: !model.skills.folders.isEmpty)
        model.skills.foldersChanged = { [weak self, weak sendShortcut] in
            sendShortcut?.update(enabled: self?.model.skills.folders.isEmpty == false)
        }
        self.sendShortcut = sendShortcut
        stopRunsOnTerminateSignal()
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
        desk.show()
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
            mark.size = NSSize(width: Metrics.menuBarIconWidth,
                               height: Metrics.menuBarIconWidth * mark.size.height / mark.size.width)
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
        commands.perform(command)
    }

    func validateMenuItem(_ menuItem: NSMenuItem) -> Bool {
        (menuItem.representedObject as? Command)?.isEnabled(in: commands.context) ?? true
    }

    /// Shows a link capture of the reading toast in the opening tab of its site.
    private func showArticle(_ id: UUID) {
        desk.open(.note(id, show: .openingTab))
    }

    func applicationDidBecomeActive(_ notification: Notification) {
        checkAccessibility()
    }

    /// The user can take the Accessibility access away while Piper runs.
    /// QA mode never starts the capture service.
    private func checkAccessibility() {
        if !QA.isOn { capture.start() }
    }

    /// Names the default folder in the menu bar item, and hides the item when
    /// no folder has Claude skills.
    func menuNeedsUpdate(_ menu: NSMenu) {
        sendClipboardItem?.isHidden = model.skills.folders.isEmpty
        sendClipboardItem?.title = Command.sendClipboard.title + " to " + (model.skills.defaultFolder?.name ?? "Folder")
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
                commands.showDraft(try model.send.note(note, action: action))
            } catch {
                model.messages.report(error)
            }
        })
    }

    /// Brings the open windows forward on a Dock click. With no window open,
    /// the click opens the feed paper.
    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        if !flag { desk.show() }
        return true
    }

    func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
        // The guards below ask through a modal alert, and an attached sheet
        // stops that alert from appearing. Quit then does nothing at all, so
        // close the sheet first.
        desk.dismissAttachedSheet()
        if !confirmStoppingRuns() { return .terminateCancel }
        if !commands.resolveCaptureEdits() { return .terminateCancel }
        Task { @MainActor in
            await model.files.flushEditor()
            let settled = model.files.settleEditors()
            if !settled {
                desk.show()
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
        capture.stop()
        sendShortcut?.unregister()
        model.agents.runner.stopAll()
        model.clipboard.stop()
    }
}

extension AppDelegate {
    enum Metrics {
        /// The width of the Piper mark in the menu bar. The height keeps the shape of the mark.
        static let menuBarIconWidth: CGFloat = 20
    }
}
