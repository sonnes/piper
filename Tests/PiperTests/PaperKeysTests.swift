import Captures
import XCTest
@testable import Piper

/// The keyboard of the papers: the index cursor, the number keys, and the hint strip.
@MainActor
final class PaperKeysTests: XCTestCase {

    private func row(_ path: String, folder: Bool, depth: Int = 1) -> FolderIndexRow {
        FolderIndexRow(path: path, name: path, isFolder: folder, depth: depth, hasChildren: folder, expanded: false)
    }

    private func entries(_ tab: PaperTab) -> [IndexEntry] {
        IndexEntry.entries(tab: tab, sections: ["Inbox", "Work"], feeds: ["a", "b"], overflow: ["/pins/Talks"],
                           roots: ["/notes", "/other"], activeRoot: "/notes",
                           tree: [row("Field", folder: true), row("todo.md", folder: false)],
                           sessionFolders: ["/notes"])
    }

    // MARK: - Index

    func testTheInboxIndexListsTheShowRowsThenTheSectionsThenDone() {
        XCTAssertEqual(entries(.inbox), [
            .scope(.inbox(section: nil)), .inboxFilter(.notes), .inboxFilter(.reading),
            .scope(.inbox(section: "Inbox")), .scope(.inbox(section: "Work")), .scope(.done)
        ])
    }

    func testTheFoldersIndexListsThePinsThenEachRootWithTheTreeOfTheActiveRoot() {
        XCTAssertEqual(entries(.folders), [
            .pinned("/pins/Talks"), .scope(.folder("")), .scope(.folder("Field")), .file("todo.md"), .root("/other")
        ])
    }

    func testClipboardAndAPinnedTabHaveNoIndex() {
        XCTAssertEqual(entries(.clipboard), [])
        XCTAssertEqual(entries(.pinned("/pins/Talks")), [])
    }

    func testTheCursorStartsAtAnEndAndStopsAtTheLastRow() {
        let rows = entries(.feeds)
        XCTAssertEqual(IndexEntry.move(nil, by: 1, in: rows), rows.first)
        XCTAssertEqual(IndexEntry.move(nil, by: -1, in: rows), rows.last)
        XCTAssertEqual(IndexEntry.move(rows[1], by: 1, in: rows), rows[2])
        XCTAssertEqual(IndexEntry.move(rows.last, by: 1, in: rows), rows.last)
        XCTAssertNil(IndexEntry.move(nil, by: 1, in: []))
    }

    func testTheCurrentRowOfAFilteredInboxIsItsShowRow() {
        XCTAssertEqual(IndexEntry.current(scope: .inbox(section: nil), filter: .reading), .inboxFilter(.reading))
        XCTAssertEqual(IndexEntry.current(scope: .inbox(section: nil), filter: .all), .scope(.inbox(section: nil)))
        XCTAssertEqual(IndexEntry.current(scope: .done, filter: .notes), .scope(.done))
    }

    func testTheBracketKeysGoRoundTheScopesOfTheTab() {
        let rows = entries(.feeds)
        XCTAssertEqual(IndexEntry.cycle(.feed(.allUnread), by: 1, in: rows), .feed(.starred))
        XCTAssertEqual(IndexEntry.cycle(.feed(.discover), by: -1, in: rows), .feed(.feed("b")))
        // A file, a pin, and another root are not scopes, so the cycle skips them.
        XCTAssertEqual(IndexEntry.cycle(.folder("Field"), by: 1, in: entries(.folders)), .folder(""))
    }

    // MARK: - Number Keys

    func testTheNumberOfTheActiveTabTogglesItsIndexAtItsDefaultScope() {
        let tabs: [PaperTab] = [.inbox, .clipboard, .feeds, .folders]
        XCTAssertEqual(NumberKey.action(1, tabs: tabs, active: .inbox, showsIndex: false, atDefaultScope: true), .toggleIndex)
        XCTAssertEqual(NumberKey.action(1, tabs: tabs, active: .inbox, showsIndex: true, atDefaultScope: false), .toggleIndex)
        XCTAssertEqual(NumberKey.action(1, tabs: tabs, active: .inbox, showsIndex: false, atDefaultScope: false), .showTab(.inbox))
        XCTAssertEqual(NumberKey.action(3, tabs: tabs, active: .inbox, showsIndex: false, atDefaultScope: true), .showTab(.feeds))
        XCTAssertEqual(NumberKey.action(2, tabs: tabs, active: .clipboard, showsIndex: false, atDefaultScope: true), .showTab(.clipboard))
        XCTAssertEqual(NumberKey.action(5, tabs: tabs, active: .inbox, showsIndex: false, atDefaultScope: true), .none)
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
        XCTAssertEqual(list, ["move", "open as a paper", "capture", "tab", "index"])
        let open = Hint.hints(index: false, paper: nil, article: false, papersOpen: true, tabs: 5)
        XCTAssertEqual(open.last, Hint(keys: ["⌘`"], label: "next paper"))
        XCTAssertEqual(Hint.hints(index: true, paper: nil, article: false, papersOpen: false, tabs: 4)[2].keys, ["1–4"])
        let article = Hint.hints(index: false, paper: .article("a"), article: true, papersOpen: true, tabs: 5).map(\.label)
        XCTAssertEqual(article, ["highlight", "note", "next paper", "put back", "tidy"])
        let file = Hint.hints(index: false, paper: .file, article: false, papersOpen: true, tabs: 5).map(\.label)
        XCTAssertEqual(file, ["next paper", "put back", "tidy"])
    }

    func testAFolderListStepStopsAtTheEnds() {
        XCTAssertEqual(FolderListView.step(from: nil, by: 1, in: ["a", "b"]), "a")
        XCTAssertEqual(FolderListView.step(from: "a", by: 1, in: ["a", "b"]), "b")
        XCTAssertEqual(FolderListView.step(from: "b", by: 1, in: ["a", "b"]), "b")
        XCTAssertNil(FolderListView.step(from: "a", by: 1, in: []))
    }
}
