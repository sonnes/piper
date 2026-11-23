import AppKit
import Captures
import Vault
import XCTest
@testable import Piper

final class PaperDeskStateTests: XCTestCase {
    private var defaults: UserDefaults!
    private let suite = "piper-paper-desk-tests"

    override func setUp() {
        defaults = UserDefaults(suiteName: suite)
        defaults.removePersistentDomain(forName: suite)
    }

    override func tearDown() { defaults.removePersistentDomain(forName: suite) }

    // MARK: - Save And Restore

    func testStateRestoresAfterASave() {
        var state = PaperDeskState()
        state.tab = .pinned("/tmp/notes/Field Notes")
        state.scope = .feed(.feed("harbor"))
        state.expandedFolders = ["Field Notes", "Field Notes/Essays"]
        state.pinnedFolders = ["/tmp/notes/Field Notes"]
        state.feedFrame = NSStringFromRect(NSRect(x: 40, y: 80, width: 520, height: 760))
        state.selectedFile = "Field Notes/reading-journal.md"
        state.save(to: defaults)

        XCTAssertEqual(PaperDeskState.restore(from: defaults), state)
    }

    func testEveryScopeRestores() {
        let scopes: [PaperScope] = [.inbox(section: nil), .inbox(section: "Work"), .done, .clipboard,
                                    .feed(.discover), .feed(.allUnread), .feed(.starred), .feed(.feed("a")),
                                    .folder(""), .folder("a/b"), .sessions("/tmp/a")]
        for scope in scopes {
            var state = PaperDeskState()
            state.scope = scope
            state.save(to: defaults)
            XCTAssertEqual(PaperDeskState.restore(from: defaults).scope, scope)
        }
    }

    func testNoSavedStateOrABadStateOpensOnInbox() {
        XCTAssertEqual(PaperDeskState.restore(from: defaults), PaperDeskState())
        defaults.set(Data("not json".utf8), forKey: AppDefaults.Key.paperDeskState)
        let state = PaperDeskState.restore(from: defaults)
        XCTAssertEqual(state.tab, .inbox)
        XCTAssertEqual(state.scope, .inbox(section: nil))
    }

    // MARK: - Pins And Folders

    func testUnpinningTheActiveTabGoesToFolders() {
        var state = PaperDeskState()
        state.togglePin("/tmp/a")
        state.togglePin("/tmp/b")
        XCTAssertEqual(state.pinnedFolders, ["/tmp/a", "/tmp/b"])
        state.tab = .pinned("/tmp/a")
        state.togglePin("/tmp/a")
        XCTAssertEqual(state.pinnedFolders, ["/tmp/b"])
        XCTAssertEqual(state.tab, .folders)
    }

    func testAFolderChangeKeepsThePinsAndForgetsTheRest() {
        var state = PaperDeskState()
        state.tab = .pinned("/tmp/a")
        state.scope = .folder("a/b")
        state.expandedFolders = ["a"]
        state.pinnedFolders = ["/tmp/a"]
        state.selectedFile = "a/b/c.md"
        state.resetForVault()
        XCTAssertEqual(state.tab, .folders)
        XCTAssertEqual(state.scope, .folder(""))
        XCTAssertEqual(state.expandedFolders, [])
        XCTAssertEqual(state.pinnedFolders, ["/tmp/a"])
        XCTAssertNil(state.selectedFile)

        var feeds = PaperDeskState()
        feeds.scope = .feed(.starred)
        feeds.resetForVault()
        XCTAssertEqual(feeds.scope, .feed(.starred))
    }

    func testRelativePathsStayInsideTheRoot() {
        XCTAssertEqual(PaperDeskState.relativePath(of: "/tmp/root", in: "/tmp/root"), "")
        XCTAssertEqual(PaperDeskState.relativePath(of: "/tmp/root/a/b", in: "/tmp/root/"), "a/b")
        XCTAssertNil(PaperDeskState.relativePath(of: "/tmp/rooted/a", in: "/tmp/root"))
        XCTAssertNil(PaperDeskState.relativePath(of: "/tmp/other", in: "/tmp/root"))
    }

    func testAPinnedTabShowsItsFolder() {
        let state = PaperDeskState()
        XCTAssertEqual(state.defaultScope(for: .pinned("/tmp/root/a"), root: "/tmp/root", sessionFolders: []), .folder("a"))
        XCTAssertEqual(state.defaultScope(for: .feeds, root: "/tmp/root", sessionFolders: []), .feed(.allUnread))
        XCTAssertEqual(state.defaultScope(for: .agents, root: "/tmp/root", sessionFolders: ["/tmp/s"]), .sessions("/tmp/s"))
        XCTAssertEqual(state.defaultScope(for: .agents, root: "/tmp/root", sessionFolders: []), .sessions("/tmp/root"))
    }

    // MARK: - Tab Overflow

    func testPinsFillTheColumnAndTheRestOverflow() {
        let pins = ["/a", "/b", "/c", "/d", "/e"]
        let withAgents = PaperTab.column(pins: pins, showsAgents: true, limit: 8)
        XCTAssertEqual(withAgents.tabs, [.inbox, .clipboard, .feeds, .folders, .agents, .pinned("/a"), .pinned("/b"), .pinned("/c")])
        XCTAssertEqual(withAgents.overflow, ["/d", "/e"])

        let withoutAgents = PaperTab.column(pins: pins, showsAgents: false, limit: 8)
        XCTAssertEqual(withoutAgents.tabs.count, 8)
        XCTAssertFalse(withoutAgents.tabs.contains(.agents))
        XCTAssertEqual(withoutAgents.overflow, ["/e"])
    }

    func testAColumnWithoutRoomForPinsOverflowsEveryPin() {
        let column = PaperTab.column(pins: ["/a"], showsAgents: true, limit: 3)
        XCTAssertEqual(column.tabs, [.inbox, .clipboard, .feeds, .folders, .agents])
        XCTAssertEqual(column.overflow, ["/a"])
        XCTAssertEqual(PaperTab.column(pins: [], showsAgents: false).overflow, [])
    }

    // MARK: - Placement

    func testReaderPapersOpenRightOfTheFeedAndCascade() {
        let screen = NSRect(x: 0, y: 0, width: 2000, height: 1200)
        let feed = NSRect(x: 100, y: 200, width: 520, height: 760)
        let size = NSSize(width: 600, height: 560)
        XCTAssertEqual(PaperDesk.frame(index: 0, size: size, feed: feed, screen: screen),
                       NSRect(x: 644, y: 400, width: 600, height: 560))
        XCTAssertEqual(PaperDesk.frame(index: 1, size: size, feed: feed, screen: screen),
                       NSRect(x: 668, y: 376, width: 600, height: 560))
        XCTAssertEqual(PaperDesk.frame(index: 6, size: size, feed: feed, screen: screen),
                       PaperDesk.frame(index: 0, size: size, feed: feed, screen: screen))
    }

    func testReaderPapersStayOnTheScreen() {
        let screen = NSRect(x: 0, y: 0, width: 2000, height: 1200)
        let size = NSSize(width: 600, height: 560)
        let right = PaperDesk.frame(index: 0, size: size, feed: NSRect(x: 1300, y: 200, width: 520, height: 760), screen: screen)
        XCTAssertEqual(right.maxX, 2000 - AppDefaults.Papers.screenInset)

        let centered = PaperDesk.frame(index: 0, size: size, feed: nil, screen: screen)
        XCTAssertEqual(centered, NSRect(x: 700, y: 616, width: 600, height: 560))

        let small = PaperDesk.frame(index: 0, size: NSSize(width: 712, height: 860), feed: nil,
                                    screen: NSRect(x: 0, y: 0, width: 800, height: 600))
        XCTAssertEqual(small, NSRect(x: 44, y: 24, width: 712, height: 552))
    }

    // MARK: - Folder Index And Lists

    func testTheFolderIndexShowsOnlyTheOpenFolders() {
        let paths = ["index.md", "Field Notes/journal.md", "Field Notes/Essays/margins.md"]
        let closed = FolderIndex.rows(paths: paths, folders: [], expanded: [])
        XCTAssertEqual(closed.map(\.path), ["Field Notes", "index.md"])
        XCTAssertEqual(closed.first?.hasChildren, true)

        let open = FolderIndex.rows(paths: paths, folders: [], expanded: ["Field Notes"])
        XCTAssertEqual(open.map(\.path), ["Field Notes", "Field Notes/Essays", "Field Notes/journal.md", "index.md"])
        XCTAssertEqual(open.map(\.depth), [1, 2, 2, 1])
        XCTAssertEqual(open.first?.expanded, true)
    }

    func testAFolderListGroupsTheFilesUnderTheFolder() {
        let files = ["b.md", "a/z.md", "a/c.md", "a/sub/d.md", "ab/e.md"].map { makeFile("", path: $0) }
        let groups = FolderListView.groups(files, in: "a")
        XCTAssertEqual(groups.map(\.folder), ["a", "a/sub"])
        XCTAssertEqual(groups[0].files.map(\.name), ["c.md", "z.md"])
        XCTAssertEqual(FolderListView.groups(files, in: "").map(\.folder), ["", "a", "a/sub", "ab"])
    }
}

@MainActor
final class PaperDeskTests: XCTestCase {
    private var root: URL!

    override func setUp() async throws {
        root = FileManager.default.temporaryDirectory.appendingPathComponent("piper-desk-tests-" + UUID().uuidString)
        try FileManager.default.createDirectory(at: root.appendingPathComponent("notes"), withIntermediateDirectories: true)
        try Data("# Journal\n".utf8).write(to: root.appendingPathComponent("notes/journal.md"))
    }

    override func tearDown() async throws { try FileManager.default.removeItem(at: root) }

    /// A file that opens from a list or the Folders index, and not only from
    /// `openFile`, is the file that the feed paper restores.
    func testEveryFilePaperSavesItsFile() async throws {
        let model = AppModel(store: CaptureStore(url: root.appendingPathComponent(".captures.sqlite")), wikiPath: root.path)
        model.reload()
        for _ in 0..<400 where model.loading { try await Task.sleep(for: .milliseconds(20)) }
        let defaults = try XCTUnwrap(UserDefaults(suiteName: "piper-paper-desk-window-tests"))
        defer { defaults.removePersistentDomain(forName: "piper-paper-desk-window-tests") }
        let desk = PaperDesk(model: model, defaults: defaults)
        defer { desk.hide() }

        model.openDocument("notes/journal.md")
        desk.paper.open(.file)
        XCTAssertEqual(desk.paper.state.selectedFile, "notes/journal.md")
    }
}
