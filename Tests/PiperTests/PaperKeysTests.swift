import Captures
import XCTest
@testable import Piper

/// The keyboard of the papers: the index cursor, the number keys, and the hint strip.
@MainActor
final class PaperKeysTests: XCTestCase {

    private func entries(_ tab: PaperTab) -> [IndexEntry] {
        IndexEntry.entries(tab: tab, sections: ["Inbox", "Work"], feeds: ["a", "b"], sessionFolders: ["/notes"])
    }

    // MARK: - Index

    func testTheInboxIndexListsTheShowRowsThenTheSectionsThenDone() {
        XCTAssertEqual(entries(.inbox), [
            .scope(.inbox(section: nil)), .inboxFilter(.notes), .inboxFilter(.reading),
            .scope(.inbox(section: "Inbox")), .scope(.inbox(section: "Work")), .scope(.done)
        ])
    }

    func testClipboardFoldersAndAPinnedTabHaveNoIndex() {
        XCTAssertEqual(entries(.clipboard), [])
        XCTAssertEqual(entries(.folders), [])
        XCTAssertEqual(entries(.pinned("/pins/Talks")), [])
        XCTAssertFalse(PaperTab.folders.hasIndex)
        XCTAssertTrue(PaperTab.folders.showsTree)
        XCTAssertTrue(PaperTab.pinned("/pins/Talks").showsTree)
        XCTAssertFalse(PaperTab.feeds.showsTree)
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
        // A Show row is not a scope, so the cycle skips it.
        XCTAssertEqual(IndexEntry.cycle(.inbox(section: nil), by: 1, in: entries(.inbox)), .inbox(section: "Inbox"))
        XCTAssertNil(IndexEntry.cycle(.folder(""), by: 1, in: entries(.folders)))
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
        let tree = Hint.hints(index: false, tree: true, paper: nil, article: false, papersOpen: false, tabs: 8)
        XCTAssertEqual(tree.map(\.label), ["move", "open folder", "close folder", "open file", "pin as tab", "tab"])
        XCTAssertEqual(tree.last?.keys, ["1–8"])
    }

    func testTheFoldersTabShowsItsTreeWithNoIndexStep() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("piper-keys-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let suite = "piper-tree-keys-tests"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defaults.removePersistentDomain(forName: suite)
        defer { defaults.removePersistentDomain(forName: suite) }
        let model = AppModel(store: CaptureStore(url: root.appendingPathComponent(".captures.sqlite")), wikiPath: root.path)
        let paper = FeedPaperModel(model: model, defaults: defaults)
        paper.choose(.folders)
        XCTAssertEqual(paper.state.tab, .folders)
        XCTAssertFalse(paper.showsIndex)
        XCTAssertEqual(paper.state.scope, .folder(""))
    }
}
