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

    func testTheGlyphAndTheNameComeFromTheKey() {
        XCTAssertEqual(Command.newCapture.key?.glyph, "⌘N")
        XCTAssertEqual(Command.addFeed.key?.glyph, "⇧⌘N")
        XCTAssertEqual(Command.sessionCard.key?.glyph, "⌥⌘C")
        XCTAssertEqual(Command.sessionCard.key?.name, "Option-Command-C")
        XCTAssertEqual(Command.sendClipboard.key?.glyph, "⌃⌥W")
        XCTAssertEqual(Command.markAllAsRead.key?.name, "Shift-Command-K")
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
        XCTAssertEqual(Command.matching(try event("1", [.command])), .today)
        XCTAssertEqual(Command.matching(try event("k", [.command])), .goToFile)
        XCTAssertEqual(Command.matching(try event("K", [.shift, .command])), .markAllAsRead)
        XCTAssertNil(Command.matching(try event("3", [.command])))
    }

    func testEveryCommandIsInAMenuOrInThePaletteOrInAView() {
        let statusCommands = Command.statusMenu.joined()
        for command in Command.allCases where command.menu == nil && !statusCommands.contains(command) {
            XCTAssertEqual(command, .toggleFileSource, "\(command) has no place")
        }
        XCTAssertTrue(Command.find.isInPalette)
        XCTAssertFalse(Command.copy.isInPalette)
        XCTAssertEqual(Command.markAllAsRead.menu, .file)
    }

    private func event(_ characters: String, _ modifiers: NSEvent.ModifierFlags) throws -> NSEvent {
        try XCTUnwrap(NSEvent.keyEvent(with: .keyDown, location: .zero, modifierFlags: modifiers, timestamp: 0, windowNumber: 0,
                                       context: nil, characters: characters, charactersIgnoringModifiers: characters,
                                       isARepeat: false, keyCode: 0))
    }
}
