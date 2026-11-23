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
        state.pinColors = ["/tmp/notes/Field Notes": .rose]
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

    /// A state that an older version saved, before the tab colors, keeps its pins.
    func testAStateWithoutTabColorsKeepsItsPins() throws {
        let json = #"{"tab":{"inbox":{}},"scope":{"clipboard":{}},"expandedFolders":["/n/a"],"pinnedFolders":["/n/a"]}"#
        defaults.set(Data(json.utf8), forKey: AppDefaults.Key.paperDeskState)
        let state = PaperDeskState.restore(from: defaults)
        XCTAssertEqual(state.pinnedFolders, ["/n/a"])
        XCTAssertEqual(state.scope, .clipboard)
        XCTAssertEqual(state.pinColors, [:])
        XCTAssertEqual(PaperTab.pinned("/n/a").color(pins: state.pinColors), .teal)
    }

    // MARK: - Tab Colors

    func testATabColorRestoresAfterASave() {
        var state = PaperDeskState()
        state.togglePin("/n/a", fixedTabs: 5)
        state.setColor(.clay, of: "/n/a")
        state.setColor(.plum, of: "/n/not-pinned")
        state.save(to: defaults)
        let restored = PaperDeskState.restore(from: defaults)
        XCTAssertEqual(restored.pinColors, ["/n/a": .clay])
        XCTAssertEqual(PaperTab.pinned("/n/a").color(pins: restored.pinColors), .clay)
    }

    func testEachFixedTabHasItsColorAndANewPinTakesAFreeColor() {
        XCTAssertEqual(PaperTab.fixed.map { $0.color(pins: [:]) }, [.indigo, .zinc, .sky, .emerald, .plum])
        var state = PaperDeskState()
        state.togglePin("/n/a", fixedTabs: 4)
        state.togglePin("/n/b", fixedTabs: 4)
        state.setColor(.teal, of: "/n/b")
        state.togglePin("/n/c", fixedTabs: 4)
        XCTAssertEqual(state.pinColors, ["/n/a": .teal, "/n/b": .teal, "/n/c": .rose])
        state.togglePin("/n/c", fixedTabs: 4)
        XCTAssertNil(state.pinColors["/n/c"], "An unpin forgets the color.")
    }

    // MARK: - Pins And Folders

    func testUnpinningTheActiveTabGoesToFolders() {
        var state = PaperDeskState()
        XCTAssertEqual(state.togglePin("/tmp/a", fixedTabs: 5), .pinned)
        state.togglePin("/tmp/b", fixedTabs: 5)
        XCTAssertEqual(state.pinnedFolders, ["/tmp/a", "/tmp/b"])
        state.tab = .pinned("/tmp/a")
        XCTAssertEqual(state.togglePin("/tmp/a", fixedTabs: 5), .unpinned)
        XCTAssertEqual(state.pinnedFolders, ["/tmp/b"])
        XCTAssertEqual(state.tab, .folders)
    }

    /// The edge holds eight tabs. A pin past the eighth tab changes nothing,
    /// and an unpin still works.
    func testAPinPastTheEighthTabIsRefused() {
        var state = PaperDeskState()
        for path in ["/n/a", "/n/b", "/n/c"] { XCTAssertEqual(state.togglePin(path, fixedTabs: 5), .pinned) }
        XCTAssertEqual(state.togglePin("/n/d", fixedTabs: 5), .full)
        XCTAssertEqual(state.pinnedFolders, ["/n/a", "/n/b", "/n/c"])
        XCTAssertNil(state.pinColors["/n/d"])
        // Without the Agents tab, the column has room for a fourth pin.
        XCTAssertEqual(state.togglePin("/n/d", fixedTabs: 4), .pinned)
        XCTAssertEqual(state.togglePin("/n/a", fixedTabs: 5), .unpinned)
    }

    func testAFolderChangeKeepsThePinsAndForgetsTheRest() {
        var state = PaperDeskState()
        state.tab = .pinned("/tmp/a")
        state.scope = .folder("a/b")
        state.expandedFolders = ["/tmp/a"]
        state.pinnedFolders = ["/tmp/a"]
        state.selectedFile = "a/b/c.md"
        state.resetForVault()
        XCTAssertEqual(state.tab, .folders)
        XCTAssertEqual(state.scope, .folder(""))
        XCTAssertEqual(state.expandedFolders, ["/tmp/a"], "The open folders hold absolute paths, so they stay.")
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

    /// A paper that opens after another paper closed takes the free place, and
    /// does not cover a paper that is still open.
    func testThePaperWindowHoldsTheMarginOfTheShadow() {
        let paper = NSRect(x: 100, y: 200, width: 520, height: 760)
        let margin = AppDefaults.Papers.shadowMargin
        let window = PaperWindow.windowFrame(of: paper)
        XCTAssertEqual(window.width, paper.width + margin.left + margin.right)
        XCTAssertEqual(window.height, paper.height + margin.top + margin.bottom)
        XCTAssertEqual(PaperWindow.paperFrame(of: window), paper)
    }

    func testANewPaperTakesTheFirstFreePlace() {
        let screen = NSRect(x: 0, y: 0, width: 2000, height: 1200)
        let feed = NSRect(x: 100, y: 200, width: 520, height: 760)
        let note = NSSize(width: 600, height: 560)
        let file = NSSize(width: 712, height: 860)
        let first = PaperDesk.frame(index: 0, size: note, feed: feed, screen: screen)
        let third = PaperDesk.frame(index: 2, size: file, feed: feed, screen: screen)
        // The first paper closed. The papers in the second and the third place stay.
        let second = PaperDesk.frame(index: 1, size: file, feed: feed, screen: screen)
        XCTAssertEqual(PaperDesk.frame(size: note, feed: feed, screen: screen, open: [second, third]), first)

        let fourth = PaperDesk.frame(size: note, feed: feed, screen: screen, open: [first, second, third])
        XCTAssertEqual(fourth, PaperDesk.frame(index: 3, size: note, feed: feed, screen: screen))
        XCTAssertNotEqual(fourth.origin, third.origin)
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

    // MARK: - Tab Stubs

    func testTheColumnHeightCountsTheOverlapAndTheAddTab() {
        let metrics = AppDefaults.Papers.self
        let one = 60 + 2 * metrics.tabLabelPadding
        XCTAssertEqual(TabColumn.height(of: [60], add: false), one)
        XCTAssertEqual(TabColumn.height(of: [60, 60], add: false), 2 * one - metrics.tabShoulder)
        XCTAssertEqual(TabColumn.height(of: [60], add: true), one + metrics.addTabGap + metrics.addTabHeight)
        XCTAssertEqual(TabColumn.height(of: [], add: true), 0)
    }

    /// The pinned tabs show their first letter when the column with full
    /// labels is taller than the paper less its top and its foot room.
    func testPinnedTabsBecomeStubsOnAShortPaper() {
        let metrics = AppDefaults.Papers.self
        let lengths: [CGFloat] = [60, 90, 60, 70, 70, 90, 80, 80]
        let column = TabColumn.height(of: lengths, add: false)
        let fits = column + metrics.tabsTop + metrics.tabRoom
        XCTAssertFalse(TabColumn.usesStubs(lengths: lengths, add: false, paperHeight: fits))
        XCTAssertTrue(TabColumn.usesStubs(lengths: lengths, add: false, paperHeight: fits - 1))
        XCTAssertTrue(TabColumn.usesStubs(lengths: lengths, add: true, paperHeight: fits))
    }

    /// The paper grows to hold its tabs, as far as the screen permits. A taller paper stays.
    func testThePaperGrowsToHoldItsTabs() {
        let metrics = AppDefaults.Papers.self
        XCTAssertEqual(TabColumn.paperHeight(of: [60], add: false), TabColumn.height(of: [60], add: false) + metrics.tabsTop + metrics.tabRoom)
        XCTAssertEqual(TabColumn.fittedHeight(current: 700, needed: 760, screen: 1000), 760)
        XCTAssertEqual(TabColumn.fittedHeight(current: 700, needed: 760, screen: 720), 720)
        XCTAssertEqual(TabColumn.fittedHeight(current: 900, needed: 760, screen: 1000), 900)
    }

    func testATabCountStopsAtItsLimit() {
        XCTAssertEqual(TabColumn.countText(4), "4")
        XCTAssertEqual(TabColumn.countText(AppDefaults.Papers.countLimit + 1), "\(AppDefaults.Papers.countLimit)+")
    }

    // MARK: - Folder Tree

    private let paths = ["index.md", "Field Notes/journal.md", "Field Notes/Essays/margins.md", "Work Log/sync.md"]

    private func tree(top: String? = nil, roots: [String] = ["/n"], expanded: Set<String> = []) -> [FolderTreeRow] {
        FolderTree.rows(paths: paths, folders: ["Talks"], roots: roots, activeRoot: "/n", top: top, expanded: expanded)
    }

    func testTheTreeShowsOnlyTheOpenFolders() {
        let closed = tree()
        XCTAssertEqual(closed.map(\.name), ["Field Notes", "Talks", "Work Log", "index.md"])
        XCTAssertEqual(closed.map(\.count), [2, 0, 1, 1])
        XCTAssertEqual(closed.first?.id, "/n/Field Notes")

        let open = tree(expanded: ["/n/Field Notes", "/n/Field Notes/Essays"])
        XCTAssertEqual(open.map(\.path), ["Field Notes", "Field Notes/Essays", "Field Notes/Essays/margins.md",
                                          "Field Notes/journal.md", "Talks", "Work Log", "index.md"])
        XCTAssertEqual(open.map(\.depth), [0, 1, 2, 1, 0, 0, 0])
        XCTAssertEqual(open[2].parent, "/n/Field Notes/Essays")
        XCTAssertNil(open[0].parent)
    }

    /// A pinned tab shows its folder only, and it shares the open folders with Folders.
    func testAPinnedTabShowsTheTreeInItsFolder() {
        let rows = tree(top: "/n/Field Notes", expanded: ["/n/Field Notes/Essays"])
        XCTAssertEqual(rows.map(\.name), ["Essays", "margins.md", "journal.md"])
        XCTAssertEqual(rows.map(\.depth), [0, 1, 0])
        XCTAssertNil(rows[0].parent)
        XCTAssertEqual(tree(top: "/elsewhere/a"), [])
    }

    func testSeveralRootsShowAsTheTopOfTheTree() {
        let rows = tree(roots: ["/n", "/other"], expanded: ["/n", "/other"])
        XCTAssertEqual(rows.first?.id, "/n")
        XCTAssertEqual(rows.first?.depth, 0)
        XCTAssertEqual(rows[1].depth, 1)
        XCTAssertEqual(rows[1].parent, "/n")
        XCTAssertEqual(rows.last?.id, "/other")
        XCTAssertEqual(rows.last?.isOtherRoot, true)
        XCTAssertEqual(rows.last?.expanded, false, "Another root shows its files after it becomes the active folder.")
    }

    func testTheTopFolderCountAndTheFileCount() {
        XCTAssertEqual(FolderTree.topFolderCount(paths: paths, folders: ["Talks", "Field Notes/Essays"]), 3)
        XCTAssertEqual(FolderTree.fileCount(paths: paths, in: "Field Notes"), 2)
        XCTAssertEqual(FolderTree.fileCount(paths: paths, in: ""), 4)
        XCTAssertEqual(FolderTree.fileCount(paths: paths, in: "Field"), 0)
    }

    // MARK: - Tree Keys

    func testUpAndDownMoveThroughTheRowsThatShowAndStopAtTheEnds() {
        let rows = tree()
        XCTAssertEqual(FolderTree.action(.down, cursor: nil, rows: rows), .select("/n/Field Notes"))
        XCTAssertEqual(FolderTree.action(.down, cursor: "/n/Field Notes", rows: rows), .select("/n/Talks"))
        XCTAssertEqual(FolderTree.action(.up, cursor: "/n/Field Notes", rows: rows), .select("/n/Field Notes"))
        XCTAssertEqual(FolderTree.action(.down, cursor: "/n/index.md", rows: rows), .select("/n/index.md"))
        XCTAssertEqual(FolderTree.action(.down, cursor: nil, rows: []), FolderTreeAction.none)
    }

    func testRightOpensAFolderThenStepsIn() {
        XCTAssertEqual(FolderTree.action(.right, cursor: "/n/Field Notes", rows: tree()), .expand("/n/Field Notes"))
        let open = tree(expanded: ["/n/Field Notes"])
        XCTAssertEqual(FolderTree.action(.right, cursor: "/n/Field Notes", rows: open), .select("/n/Field Notes/Essays"))
        XCTAssertEqual(FolderTree.action(.right, cursor: "/n/index.md", rows: open), FolderTreeAction.none)
        // An open folder with nothing in it has no row to step into.
        let empty = tree(expanded: ["/n/Talks"])
        XCTAssertEqual(FolderTree.action(.right, cursor: "/n/Talks", rows: empty), FolderTreeAction.none)
    }

    func testLeftClosesAFolderThenStepsToItsParent() {
        let open = tree(expanded: ["/n/Field Notes", "/n/Field Notes/Essays"])
        XCTAssertEqual(FolderTree.action(.left, cursor: "/n/Field Notes/Essays", rows: open), .collapse("/n/Field Notes/Essays"))
        XCTAssertEqual(FolderTree.action(.left, cursor: "/n/Field Notes/Essays/margins.md", rows: open),
                       .select("/n/Field Notes/Essays"))
        XCTAssertEqual(FolderTree.action(.left, cursor: "/n/Field Notes/journal.md", rows: open), .select("/n/Field Notes"))
        XCTAssertEqual(FolderTree.action(.left, cursor: "/n/Talks", rows: open), FolderTreeAction.none)
    }

    func testReturnOpensAFileAndTogglesAFolder() {
        let open = tree(expanded: ["/n/Field Notes"])
        XCTAssertEqual(FolderTree.action(.enter, cursor: "/n/Field Notes", rows: open), .collapse("/n/Field Notes"))
        XCTAssertEqual(FolderTree.action(.enter, cursor: "/n/Work Log", rows: open), .expand("/n/Work Log"))
        XCTAssertEqual(FolderTree.action(.enter, cursor: "/n/index.md", rows: open), .openFile("/n/index.md"))
    }

    func testTheSummaryOfTheFoldersTab() {
        XCTAssertEqual(FolderTreeView.summary(folders: 4, tabs: 3), "4 folders. 3 have a tab.")
        XCTAssertEqual(FolderTreeView.summary(folders: 1, tabs: 1), "1 folder. 1 has a tab.")
        XCTAssertEqual(FolderTreeView.summary(folders: 2, tabs: 0), "2 folders. None has a tab.")
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

    /// The tree keys of the feed paper: Right Arrow opens and steps in, Left
    /// Arrow closes, Return opens a file, and P pins up to the eighth tab.
    func testTheTreeKeysOpenFoldersAndPinUpToTheCap() async throws {
        for folder in ["a", "b", "c", "d"] {
            try FileManager.default.createDirectory(at: root.appendingPathComponent(folder), withIntermediateDirectories: true)
            try Data("x\n".utf8).write(to: root.appendingPathComponent("\(folder)/x.md"))
        }
        let model = AppModel(store: CaptureStore(url: root.appendingPathComponent(".captures.sqlite")), wikiPath: root.path)
        model.reload()
        for _ in 0..<400 where model.loading || model.files.isEmpty { try await Task.sleep(for: .milliseconds(20)) }
        let suite = "piper-paper-tree-tests"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defaults.removePersistentDomain(forName: suite)
        defer { defaults.removePersistentDomain(forName: suite) }
        let paper = FeedPaperModel(model: model, defaults: defaults)
        var opened: [PaperItem] = []
        paper.open = { opened.append($0) }
        paper.choose(.folders)

        let a = URL(fileURLWithPath: model.wikiPath).appendingPathComponent("a").path
        XCTAssertEqual(paper.treeCursor(in: paper.treeRows), a)
        paper.treeKey(.right)
        XCTAssertEqual(paper.state.expandedFolders, [a])
        paper.treeKey(.right)
        XCTAssertEqual(paper.treeCursor(in: paper.treeRows), a + "/x.md")
        paper.treeKey(.enter)
        XCTAssertEqual(opened, [.file])
        XCTAssertEqual(model.selectedDocument, "a/x.md")
        paper.treeKey(.left)
        paper.treeKey(.left)
        XCTAssertEqual(paper.state.expandedFolders, [])
        XCTAssertEqual(FeedPaperModel(model: model, defaults: defaults).state.expandedFolders, [], "The open folders save.")

        // The column shows Inbox, Clipboard, Feeds, and Folders, so it has room for four pins.
        for _ in 0..<4 {
            paper.pinTreeCursor()
            paper.treeKey(.down)
        }
        XCTAssertEqual(paper.state.pinnedFolders.count, 4)
        XCTAssertEqual(paper.column.tabs.count, 8)
        // The cursor is on notes, the fifth folder.
        paper.pinTreeCursor()
        XCTAssertEqual(paper.treeMessage, "The edge holds 8 tabs. Remove a tab, then pin notes.")
        XCTAssertEqual(paper.state.pinnedFolders.count, 4)
        paper.treeKey(.up)
        paper.pinTreeCursor()
        XCTAssertEqual(paper.treeMessage, "d has no tab now.")
        XCTAssertEqual(paper.state.pinnedFolders.count, 3)

        paper.choose(.pinned(a))
        XCTAssertNil(paper.treeMessage)
        XCTAssertEqual(paper.treeRows.map(\.name), ["x.md"])
        XCTAssertTrue(paper.state.expandedFolders.contains(a), "A pinned tab opens its folder in the shared tree.")
        paper.setTabColor(.plum)
        XCTAssertEqual(paper.color(of: .pinned(a)), .plum)
    }

    /// The paper fills its frame in the window. The hidden title bar takes no
    /// room, so the column of tabs has the whole height of the paper.
    func testTheFeedPaperFillsItsFrame() async throws {
        let model = AppModel(store: CaptureStore(url: root.appendingPathComponent(".captures.sqlite")), wikiPath: root.path)
        let suite = "piper-paper-frame-tests"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defaults.removePersistentDomain(forName: suite)
        defer { defaults.removePersistentDomain(forName: suite) }
        let paper = FeedPaperModel(model: model, defaults: defaults)
        let controller = FeedPaperController(model: model, paper: paper)
        let window = try XCTUnwrap(controller.window as? PaperWindow)
        window.setPaperFrame(NSRect(x: 100, y: 100, width: 560, height: 700), display: true)
        window.contentView?.layoutSubtreeIfNeeded()
        for _ in 0..<50 where paper.paperHeight != 700 {
            try await Task.sleep(for: .milliseconds(20))
            window.contentView?.layoutSubtreeIfNeeded()
        }
        XCTAssertEqual(paper.paperHeight, 700)
    }
}
