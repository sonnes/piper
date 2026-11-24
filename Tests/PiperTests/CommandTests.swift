import AppKit
import XCTest
@testable import Piper

@MainActor
final class CommandTests: XCTestCase {
    func testNoTwoCommandsShareAKey() {
        let keyed = Command.allCases.compactMap { command in command.key.map { (command, $0) } }
        for (index, first) in keyed.enumerated() {
            for second in keyed[(index + 1)...] {
                XCTAssertNotEqual(first.1, second.1, "\(first.0) and \(second.0) share \(first.1.glyph)")
            }
        }
        XCTAssertFalse(keyed.contains { $0.1 == CaptureShortcut.spaceKey }, "The capture hotkey shares a key with a command.")
    }

    func testTheGlyphAndTheNameListTheModifiersInMenuOrder() {
        XCTAssertEqual(CommandKey("n").glyph, "⌘N")
        XCTAssertEqual(CommandKey("n", [.command, .shift]).glyph, "⇧⌘N")
        XCTAssertEqual(CommandKey("c", [.command, .option]).name, "Option-Command-C")
        XCTAssertEqual(CommandKey("w", [.option, .control]).glyph, "⌃⌥W")
        XCTAssertEqual(CaptureShortcut.controlOptionSpace.glyph, "⌃⌥Space")
    }

    /// Today and Feeds take the numbers of their tabs in the column.
    func testTodayAndFeedsTakeTheNumbersOfTheirTabs() {
        let column = PaperTab.column(folders: ["/notes"], showsAgents: true)
        XCTAssertEqual(Command.today.key, CommandKey(String(PaperTab.number(of: .today, in: column) ?? 0)))
        XCTAssertEqual(Command.feeds.key, CommandKey(String(PaperTab.number(of: .feeds, in: column) ?? 0)))
    }

    /// The feed paper leaves Command-1 to the menu, so Command-1 shows Today from every paper.
    func testCommandOneIsTodayAndCommandKIsGoToFile() throws {
        XCTAssertEqual(command(for: try event("1", [.command])), .today)
        XCTAssertEqual(command(for: try event("k", [.command])), .goToFile)
        XCTAssertEqual(command(for: try event("K", [.shift, .command])), .markAllAsRead)
        XCTAssertNil(command(for: try event("3", [.command])))
    }

    func testKeypadEnterIsReturnAndForwardDeleteIsDelete() throws {
        XCTAssertTrue(CommandKey.enter.matches(try event("\u{3}", [])))
        XCTAssertTrue(CommandKey.delete.matches(try event("\u{F728}", [])))
        XCTAssertFalse(CommandKey.enter.matches(try event("\r", [.shift])))
        XCTAssertEqual(CommandKey.up.shifted.glyph, "⇧↑")
    }

    func testEveryCommandIsInAMenuOrInThePaletteOrInAView() {
        let statusCommands = Command.statusMenu.joined()
        for command in Command.allCases where command.menu == nil && !statusCommands.contains(command) {
            XCTAssertEqual(command, .toggleFileSource, "\(command) has no place")
        }
        XCTAssertTrue(Command.find.isInPalette)
        XCTAssertFalse(Command.copy.isInPalette)
    }

    private func command(for event: NSEvent) -> Command? {
        Command.allCases.first { $0.key?.matches(event) == true }
    }

    private func event(_ characters: String, _ modifiers: NSEvent.ModifierFlags) throws -> NSEvent {
        try XCTUnwrap(NSEvent.keyEvent(with: .keyDown, location: .zero, modifierFlags: modifiers, timestamp: 0, windowNumber: 0,
                                       context: nil, characters: characters, charactersIgnoringModifiers: characters,
                                       isARepeat: false, keyCode: 0))
    }
}
