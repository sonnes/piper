import AppKit

/// A key that the papers read, from a key-down event.
///
/// The papers act on plain keys only. A key with Command, Option, or Control
/// goes to the menus, except Command and a number, which shows a tab.
enum PaperKey: Equatable {
    case up, down, left, right, enter
    case number(Int)
    case previousScope, nextScope
    case letter(Character)

    /// The virtual key codes of the keys that the papers read, and that QA sends.
    enum Code {
        static let up: UInt16 = 126
        static let down: UInt16 = 125
        static let left: UInt16 = 123
        static let right: UInt16 = 124
        static let enter: UInt16 = 36
        static let keypadEnter: UInt16 = 76
        static let space: UInt16 = 49
    }

    init?(_ event: NSEvent) {
        let flags = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
        guard flags.isDisjoint(with: [.command, .option, .control]) else { return nil }
        self.init(keyCode: event.keyCode, characters: event.charactersIgnoringModifiers ?? "",
                  shift: flags.contains(.shift))
    }

    init?(keyCode: UInt16, characters: String, shift: Bool) {
        switch keyCode {
        case Code.up: self = .up
        case Code.down: self = .down
        case Code.left: self = .left
        case Code.right: self = .right
        case Code.enter, Code.keypadEnter: self = .enter
        default:
            guard !shift, let character = characters.lowercased().first else { return nil }
            switch character {
            case "1"..."9": self = .number(Int(String(character)) ?? 0)
            case "[": self = .previousScope
            case "]": self = .nextScope
            case "a"..."z", " ": self = .letter(character)
            default: return nil
            }
        }
    }

    /// The number of Command and a number key, from 1 to 9. Command-1 is the first tab.
    static func tabNumber(_ event: NSEvent) -> Int? {
        let flags = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
        guard flags.intersection([.command, .option, .control, .shift]) == .command,
              let character = event.charactersIgnoringModifiers?.first, ("1"..."9").contains(character) else { return nil }
        return Int(String(character))
    }

    /// The window that has the keyboard focus. In QA mode no window is key,
    /// so the paper that has the focus stands in for it.
    @MainActor static var focusedWindow: NSWindow? {
        if let window = NSApp.keyWindow { return window }
        guard QA.isOn else { return nil }
        return NSApp.windows.first { ($0 as? PaperWindow)?.isFocused == true }
    }

    /// True while the window edits text, so the keys type into the text.
    @MainActor static func editsText(_ window: NSWindow) -> Bool {
        window.firstResponder is NSTextView || window.attachedSheet != nil
    }
}
