import AppKit
import Captures
import XCTest
@testable import Piper

/// The keyboard of the papers: the index cursor, the number keys, the key table of a paper window, and the hint strip.
@MainActor
final class PaperKeysTests: XCTestCase {

    private func entries(_ tab: PaperTab) -> [IndexEntry] {
        IndexEntry.entries(tab: tab, sections: ["Inbox", "Work"], feeds: ["https://a.example/feed", "https://b.example/feed"],
                           sessionFolders: ["/notes", "/talks"])
    }

    // MARK: - Index

    func testTheTodayIndexListsTheLensesTheSectionsAndDone() {
        XCTAssertEqual(entries(.today), [
            .lens(.all), .lens(.notes), .lens(.reading), .lens(.kept),
            .scope(.today(section: "Inbox")), .scope(.today(section: "Work")), .scope(.done)
        ])
    }

    func testTheFeedsIndexListsSourcesThenEachFeed() {
        XCTAssertEqual(entries(.feeds), [
            .scope(.sources), .scope(.feed("https://a.example/feed")), .scope(.feed("https://b.example/feed"))
        ])
        XCTAssertTrue(PaperTab.feeds.hasIndex)
    }

    func testAFolderTabHasNoIndex() {
        XCTAssertEqual(entries(.folder("/notes/Talks")), [])
        XCTAssertFalse(PaperTab.folder("/notes/Talks").hasIndex)
        XCTAssertTrue(PaperTab.folder("/notes/Talks").isFolder)
        XCTAssertFalse(PaperTab.today.isFolder)
    }

    func testTheCursorStartsAtAnEndAndStopsAtTheLastRow() {
        let rows = entries(.today)
        XCTAssertEqual(rows.step(from: nil, by: 1), rows.first)
        XCTAssertEqual(rows.step(from: nil, by: -1), rows.last)
        XCTAssertEqual(rows.step(from: rows[1], by: 1), rows[2])
        XCTAssertEqual(rows.step(from: rows.last, by: 1), rows.last)
        XCTAssertEqual(rows.step(from: rows.first, by: -1), rows.first)
        XCTAssertNil([IndexEntry]().step(from: nil, by: 1))
    }

    func testTheCurrentRowOfTodayIsItsLens() {
        XCTAssertEqual(IndexEntry.current(scope: .today(section: nil), lens: .reading), .lens(.reading))
        XCTAssertEqual(IndexEntry.current(scope: .today(section: "Work"), lens: .reading), .scope(.today(section: "Work")))
        XCTAssertEqual(IndexEntry.current(scope: .done, lens: .notes), .scope(.done))
    }

    func testTheBracketKeysGoRoundTheRowsOfTheIndex() {
        let rows = entries(.today)
        XCTAssertEqual(IndexEntry.cycle(.lens(.kept), by: 1, in: rows), .scope(.today(section: "Inbox")))
        XCTAssertEqual(IndexEntry.cycle(.lens(.all), by: -1, in: rows), .scope(.done))
        XCTAssertEqual(IndexEntry.cycle(.scope(.sessions("/notes")), by: 1, in: entries(.agents)), .scope(.sessions("/talks")))
        XCTAssertNil(IndexEntry.cycle(.scope(.folder), by: 1, in: entries(.folder("/notes/Talks"))))
    }

    // MARK: - Number Keys

    /// Today is Command-1 and Feeds is Command-2, so each folder tab comes after them.
    func testFeedsIsTheSecondTabAndTheFolderNumbersFollowIt() {
        let tabs = PaperTab.column(folders: ["/notes", "/talks"], showsAgents: false)
        XCTAssertEqual(tabs, [.today, .feeds, .folder("/notes"), .folder("/talks")])
        XCTAssertEqual(PaperTab.number(of: .today, in: tabs), 1)
        XCTAssertEqual(PaperTab.number(of: .feeds, in: tabs), 2)
        XCTAssertEqual(PaperTab.number(of: .folder("/notes"), in: tabs), 3)
        XCTAssertNil(PaperTab.number(of: .agents, in: tabs))
        let withAgents = PaperTab.column(folders: ["/notes"], showsAgents: true)
        XCTAssertEqual(withAgents, [.today, .feeds, .agents, .folder("/notes")])
        XCTAssertEqual(PaperTab.number(of: .feeds, in: withAgents), 2)
        XCTAssertEqual(PaperTab.number(of: .folder("/notes"), in: withAgents), 4)
    }

    // MARK: - Key Table

    func testTheWindowRunsTheFirstKeyThatIsOn() throws {
        var ran: [String] = []
        let window = PaperWindow(paperSize: NSSize(width: 600, height: 560), minimumPaperSize: ReaderPaperController.Metrics.minimumSize)
        window.keys = {
            [PaperKey(key: .escape, title: "back to the list", isOn: { false }) { ran.append("index") },
             PaperKey(key: .escape, title: "clear the selection") { ran.append("selection") },
             PaperKey(key: .escape, title: "end the search") { ran.append("search") }]
        }
        window.keyDown(with: try event("\u{1B}"))
        window.cancelOperation(nil)
        XCTAssertEqual(ran, ["selection", "selection"])
    }

    func testATextViewKeepsThePlainKeysButNotTheKeysThatWorkInText() throws {
        var ran: [String] = []
        let window = PaperWindow(paperSize: NSSize(width: 600, height: 560), minimumPaperSize: ReaderPaperController.Metrics.minimumSize)
        window.keys = {
            [PaperKey(key: CommandKey("k", []), title: "keep") { ran.append("keep") },
             PaperKey(key: CommandKey("3"), title: "tab", inText: true) { ran.append("tab") }]
        }
        let text = NSTextView(frame: NSRect(x: 0, y: 0, width: 100, height: 20))
        window.contentView?.addSubview(text)
        XCTAssertTrue(window.makeFirstResponder(text))
        XCTAssertTrue(window.editsText)
        XCTAssertTrue(window.performKeyEquivalent(with: try event("3", [.command])))
        window.keyDown(with: try event("k"))
        XCTAssertEqual(ran, ["tab"])
        XCTAssertTrue(window.perform(CommandKey("k", [])), "The reader page sends its letters past the focus.")
        XCTAssertEqual(ran, ["tab", "keep"])
    }

    // MARK: - Hints

    func testTheHintStripListsExactlyTheKeysThatAreOn() {
        var selected = false
        let table = [
            PaperKey(key: .up, title: "move") {},
            PaperKey(key: .down, title: "move") {},
            PaperKey(key: CommandKey("k", []), title: "keep", isOn: { selected }) {},
            PaperKey(key: CommandKey("e", []), title: "done", isOn: { selected }) {},
            PaperKey(key: .space, title: "done", isOn: { selected }) {},
            PaperKey(key: CommandKey("b", []), title: "open in browser") {}
        ] + (1...4).map { PaperKey(key: CommandKey(String($0), []), title: "lens") {} }
            + (3...5).map { PaperKey(key: CommandKey(String($0)), title: "tab") {} }
        XCTAssertEqual(Hint.hints(table), [
            Hint(keys: ["↑", "↓"], label: "move"), Hint(keys: ["B"], label: "open in browser"),
            Hint(keys: ["1–4"], label: "lens"), Hint(keys: ["⌘3–5"], label: "tab")
        ])
        selected = true
        XCTAssertEqual(Hint.hints(table).map(\.label), ["move", "keep", "done", "open in browser", "lens", "tab"])
        XCTAssertEqual(Hint.hints(table)[2].keys, ["E", "Space"])
    }

    private func event(_ characters: String, _ modifiers: NSEvent.ModifierFlags = []) throws -> NSEvent {
        try XCTUnwrap(NSEvent.keyEvent(with: .keyDown, location: .zero, modifierFlags: modifiers, timestamp: 0, windowNumber: 0,
                                       context: nil, characters: characters, charactersIgnoringModifiers: characters,
                                       isARepeat: false, keyCode: 0))
    }
}
