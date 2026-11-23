import Captures
import XCTest
@testable import Piper

/// The keyboard of the papers: the index cursor, the number keys, and the hint strip.
@MainActor
final class PaperKeysTests: XCTestCase {

    private func entries(_ tab: PaperTab) -> [IndexEntry] {
        IndexEntry.entries(tab: tab, sections: ["Inbox", "Work"], sessionFolders: ["/notes", "/talks"])
    }

    // MARK: - Index

    func testTheTodayIndexListsTheLensesThenTheSectionsThenDone() {
        XCTAssertEqual(entries(.today), [
            .lens(.all), .lens(.notes), .lens(.reading), .lens(.kept),
            .scope(.today(section: "Inbox")), .scope(.today(section: "Work")), .scope(.done)
        ])
    }

    func testAFolderTabHasNoIndex() {
        XCTAssertEqual(entries(.folder("/notes/Talks")), [])
        XCTAssertFalse(PaperTab.folder("/notes/Talks").hasIndex)
        XCTAssertTrue(PaperTab.folder("/notes/Talks").isFolder)
        XCTAssertFalse(PaperTab.today.isFolder)
    }

    func testTheCursorStartsAtAnEndAndStopsAtTheLastRow() {
        let rows = entries(.today)
        XCTAssertEqual(IndexEntry.move(nil, by: 1, in: rows), rows.first)
        XCTAssertEqual(IndexEntry.move(nil, by: -1, in: rows), rows.last)
        XCTAssertEqual(IndexEntry.move(rows[1], by: 1, in: rows), rows[2])
        XCTAssertEqual(IndexEntry.move(rows.last, by: 1, in: rows), rows.last)
        XCTAssertNil(IndexEntry.move(nil, by: 1, in: []))
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

    func testCommandAndTheNumberOfTheActiveTabTogglesItsIndexAtItsDefaultScope() {
        let tabs: [PaperTab] = [.today, .agents, .folder("/notes")]
        XCTAssertEqual(NumberKey.action(1, tabs: tabs, active: .today, showsIndex: false, atDefaultScope: true), .toggleIndex)
        XCTAssertEqual(NumberKey.action(1, tabs: tabs, active: .today, showsIndex: true, atDefaultScope: false), .toggleIndex)
        XCTAssertEqual(NumberKey.action(1, tabs: tabs, active: .today, showsIndex: false, atDefaultScope: false), .showTab(.today))
        XCTAssertEqual(NumberKey.action(3, tabs: tabs, active: .today, showsIndex: false, atDefaultScope: true), .showTab(.folder("/notes")))
        XCTAssertEqual(NumberKey.action(4, tabs: tabs, active: .today, showsIndex: false, atDefaultScope: true), .none)
    }

    func testPlainKeysMapToPaperKeys() {
        XCTAssertEqual(PaperKey(keyCode: 126, characters: "", shift: false), .up)
        XCTAssertEqual(PaperKey(keyCode: 36, characters: "\r", shift: false), .enter)
        XCTAssertEqual(PaperKey(keyCode: 18, characters: "1", shift: false), .number(1))
        XCTAssertEqual(PaperKey(keyCode: 33, characters: "[", shift: false), .previousScope)
        XCTAssertEqual(PaperKey(keyCode: 17, characters: "t", shift: false), .letter("t"))
        XCTAssertNil(PaperKey(keyCode: 17, characters: "T", shift: true))
    }

    // MARK: - Hints

    func testTheHintsFollowThePaperWithTheFocus() {
        let list = Hint.hints(index: false, paper: nil, article: false, papersOpen: false, tabs: 5).map(\.label)
        XCTAssertEqual(list, ["move", "open as a paper", "write", "tab", "index"])
        let today = Hint.hints(index: false, today: true, paper: nil, article: false, papersOpen: false, tabs: 5).map(\.label)
        XCTAssertEqual(today, ["move", "open as a paper", "keep", "done", "file", "send", "lens", "write"])
        let open = Hint.hints(index: false, paper: nil, article: false, papersOpen: true, tabs: 5)
        XCTAssertEqual(open.last, Hint(keys: ["⌘`"], label: "next paper"))
        XCTAssertEqual(Hint.hints(index: true, paper: nil, article: false, papersOpen: false, tabs: 4)[2].keys, ["⌘1–4"])
        let article = Hint.hints(index: false, paper: .article("a"), article: true, papersOpen: true, tabs: 5).map(\.label)
        XCTAssertEqual(article, ["highlight", "note", "next paper", "put back", "tidy"])
        let file = Hint.hints(index: false, paper: .file, article: false, papersOpen: true, tabs: 5).map(\.label)
        XCTAssertEqual(file, ["next paper", "put back", "tidy"])
        let tree = Hint.hints(index: false, tree: true, paper: nil, article: false, papersOpen: false, tabs: 8)
        XCTAssertEqual(tree.map(\.label), ["move", "open folder", "close folder", "open file", "tab"])
        XCTAssertEqual(tree.last?.keys, ["⌘1–8"])
        let many = Hint.hints(index: false, tree: true, paper: nil, article: false, papersOpen: false, tabs: 12)
        XCTAssertEqual(many.last?.keys, ["⌘1–9"], "Command and a number reach the ninth tab.")
    }
}
