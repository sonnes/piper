import AppKit
import SwiftUI

/// A key with its modifiers, and the text that shows it.
struct CommandKey: Equatable {
    /// The character of the key in lowercase, as a menu item takes it.
    let character: String
    let modifiers: NSEvent.ModifierFlags

    init(_ character: String, _ modifiers: NSEvent.ModifierFlags = .command) {
        self.character = character
        self.modifiers = modifiers
    }

    /// The key as a menu shows it, for example ⇧⌘K.
    var glyph: String {
        Self.order.filter { modifiers.contains($0.flag) }.map(\.glyph).joined() + keyName
    }

    /// The key as a sentence names it, for example Shift-Command-K.
    var name: String {
        (Self.order.filter { modifiers.contains($0.flag) }.map(\.name) + [keyName]).joined(separator: "-")
    }

    var keyboardShortcut: KeyboardShortcut {
        var eventModifiers: EventModifiers = []
        if modifiers.contains(.control) { eventModifiers.insert(.control) }
        if modifiers.contains(.option) { eventModifiers.insert(.option) }
        if modifiers.contains(.shift) { eventModifiers.insert(.shift) }
        if modifiers.contains(.command) { eventModifiers.insert(.command) }
        return KeyboardShortcut(KeyEquivalent(Character(character)), modifiers: eventModifiers)
    }

    /// True when `event` is this key. The Enter key of the keypad counts as
    /// Return, and Forward Delete counts as Delete.
    func matches(_ event: NSEvent) -> Bool {
        guard event.modifierFlags.intersection([.control, .option, .shift, .command]) == modifiers,
              let typed = event.charactersIgnoringModifiers?.lowercased() else { return false }
        return (Self.sameKeys[typed] ?? typed) == character
    }

    private var keyName: String {
        Self.names[character] ?? character.uppercased()
    }

    private static let sameKeys = ["\u{3}": "\r", "\u{F728}": "\u{7F}"]

    private static let names = [
        " ": "Space", "\u{F700}": "↑", "\u{F701}": "↓", "\u{F702}": "←", "\u{F703}": "→",
        "\r": "↵", "\u{1B}": "esc", "\u{7F}": "⌫"
    ]

    /// The order of the modifiers in the macOS menus.
    private static let order: [(flag: NSEvent.ModifierFlags, glyph: String, name: String)] = [
        (.control, "⌃", "Control"), (.option, "⌥", "Option"), (.shift, "⇧", "Shift"), (.command, "⌘", "Command")
    ]
}

/// An action of the app, with its title, its key, and its place in the menus.
///
/// The main menu, the menu bar item, and the command palette list these
/// commands. `AppDelegate.perform(_:)` runs them.
enum Command: CaseIterable {
    case about, settings, quit
    case undo, redo, cut, copy, paste, selectAll, find
    case newCapture, addFeed, save, refresh, closeWindow
    case back, forward, goToFile
    case today, feeds, feedPaper, nextPaper, sessionCard
    case captureClipboard, sendClipboard, toggleFileSource
    case markAllAsRead

    /// A menu of the main menu.
    enum Menu: CaseIterable {
        case app, edit, file, go, window

        var title: String {
            switch self {
            case .app: return "Piper"
            case .edit: return "Edit"
            case .file: return "File"
            case .go: return "Go"
            case .window: return "Window"
            }
        }

        /// The commands of the menu. A separator goes between two groups.
        var groups: [[Command]] {
            switch self {
            case .app: return [[.about], [.settings], [.quit]]
            case .edit: return [[.undo, .redo, .cut, .copy, .paste, .selectAll], [.find]]
            case .file: return [[.newCapture, .addFeed, .markAllAsRead, .save, .refresh], [.closeWindow]]
            case .go: return [[.back, .forward], [.goToFile]]
            case .window: return [[.today, .feeds, .feedPaper, .nextPaper, .sessionCard]]
            }
        }
    }

    /// The commands of the menu bar item. A separator goes between two groups.
    static let statusMenu: [[Command]] = [[.newCapture, .feedPaper, .captureClipboard, .sendClipboard, .settings], [.quit]]

    var title: String {
        switch self {
        case .about: return "About Piper"
        case .settings: return "Settings…"
        case .quit: return "Quit Piper"
        case .undo: return "Undo"
        case .redo: return "Redo"
        case .cut: return "Cut"
        case .copy: return "Copy"
        case .paste: return "Paste"
        case .selectAll: return "Select All"
        case .find: return "Find…"
        case .newCapture: return "New Capture"
        case .addFeed: return "Add Feed…"
        case .save: return "Save"
        case .refresh: return "Refresh"
        case .closeWindow: return "Close Window"
        case .back: return "Back"
        case .forward: return "Forward"
        case .goToFile: return "Go to File…"
        case .today: return "Today"
        case .feeds: return "Feeds"
        case .feedPaper: return "Feed Paper"
        case .nextPaper: return "Next Paper"
        case .sessionCard: return "Session Card"
        case .captureClipboard: return "Capture Clipboard"
        case .sendClipboard: return "Send Clipboard"
        case .toggleFileSource: return "Show Source"
        case .markAllAsRead: return "Mark All as Read"
        }
    }

    var key: CommandKey? {
        switch self {
        case .about, .captureClipboard, .toggleFileSource: return nil
        case .settings: return CommandKey(",")
        case .quit: return CommandKey("q")
        case .undo: return CommandKey("z")
        case .redo: return CommandKey("z", [.shift, .command])
        case .cut: return CommandKey("x")
        case .copy: return CommandKey("c")
        case .paste: return CommandKey("v")
        case .selectAll: return CommandKey("a")
        case .find: return CommandKey("f")
        case .newCapture: return CommandKey("n")
        case .addFeed: return CommandKey("n", [.shift, .command])
        case .save: return CommandKey("s")
        case .refresh: return CommandKey("r")
        case .closeWindow: return CommandKey("w")
        case .back: return CommandKey("[")
        case .forward: return CommandKey("]")
        case .goToFile: return CommandKey("k")
        case .today: return Self.tabKey(.today)
        case .feeds: return Self.tabKey(.feeds)
        case .feedPaper: return CommandKey("0")
        case .nextPaper: return CommandKey("`")
        case .sessionCard: return CommandKey("c", [.option, .command])
        case .sendClipboard: return CommandKey("w", [.control, .option])
        case .markAllAsRead: return CommandKey("k", [.shift, .command])
        }
    }

    /// The AppKit action that the responder chain takes, for a command that
    /// AppKit performs. Piper performs the other commands.
    var standardAction: Selector? {
        switch self {
        case .about: return #selector(NSApplication.orderFrontStandardAboutPanel(_:))
        case .quit: return #selector(NSApplication.terminate(_:))
        case .undo: return Selector(("undo:"))
        case .redo: return Selector(("redo:"))
        case .cut: return #selector(NSText.cut(_:))
        case .copy: return #selector(NSText.copy(_:))
        case .paste: return #selector(NSTextView.pasteAsPlainText(_:))
        case .selectAll: return #selector(NSText.selectAll(_:))
        case .closeWindow: return #selector(NSWindow.performClose(_:))
        default: return nil
        }
    }

    /// The menu of the main menu that holds the command.
    var menu: Menu? {
        Menu.allCases.first { $0.groups.joined().contains(self) }
    }

    /// The command palette lists the commands that Piper performs. Go to File
    /// opens the palette itself.
    var isInPalette: Bool {
        standardAction == nil && self != .goToFile && (menu != nil || self == .toggleFileSource)
    }

    /// The state of the app that enables a command.
    struct Context {
        /// True while the file editor is in the paper with the keyboard focus.
        var editorHasFocus: Bool
        /// True while the feed paper shows the list of one feed.
        var showsFeedList: Bool
    }

    /// The menus and the command palette show a command only while it is enabled.
    func isEnabled(in context: Context) -> Bool {
        switch self {
        case .find: return context.editorHasFocus
        case .markAllAsRead: return context.showsFeedList
        default: return true
        }
    }

    /// The commands of the command palette, in the order of `allCases`.
    static func palette(in context: Context) -> [Command] {
        allCases.filter { $0.isInPalette && $0.isEnabled(in: context) }
    }

    /// Today and Feeds always lead the column of tabs, so their numbers do not change.
    private static func tabKey(_ tab: PaperTab) -> CommandKey? {
        PaperTab.number(of: tab, in: PaperTab.column(folders: [], showsAgents: false)).map { CommandKey(String($0)) }
    }
}
