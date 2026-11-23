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
        state.tab = .folder("/tmp/notes")
        state.scope = .feed(.feed("harbor"))
        state.expandedFolders = ["/tmp/notes/Field Notes", "/tmp/notes/Field Notes/Essays"]
        state.folderColors = ["/tmp/notes": .rose]
        state.folderCounts = ["/tmp/notes": 12]
        state.feedFrame = NSStringFromRect(NSRect(x: 40, y: 80, width: 520, height: 760))
        state.selectedFile = "Field Notes/reading-journal.md"
        state.save(to: defaults)

        XCTAssertEqual(PaperDeskState.restore(from: defaults), state)
    }

    func testEveryScopeRestores() {
        let scopes: [PaperScope] = [.inbox(section: nil), .inbox(section: "Work"), .done, .clipboard,
                                    .feed(.discover), .feed(.allUnread), .feed(.starred), .feed(.feed("a")),
                                    .folder, .sessions("/tmp/a")]
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

    /// A key that this version cannot read takes its default, and the other keys stay.
    func testAStateWithATabThatNoLongerExistsOpensOnInbox() throws {
        let old = [#"{"tab":{"pinned":{"_0":"/n/a"}},"scope":{"clipboard":{}},"expandedFolders":["/n/a"]}"#,
                   #"{"tab":{"folders":{}},"scope":{"clipboard":{}},"expandedFolders":["/n/a"]}"#]
        for json in old {
            defaults.set(Data(json.utf8), forKey: AppDefaults.Key.paperDeskState)
            let state = PaperDeskState.restore(from: defaults)
            XCTAssertEqual(state.tab, .inbox)
            XCTAssertEqual(state.scope, .clipboard)
            XCTAssertEqual(state.expandedFolders, ["/n/a"])
            XCTAssertEqual(state.folderColors, [:])
        }
    }

    // MARK: - Folder Tabs

    func testTheColumnHasTheFixedTabsThenOneTabForEachFolder() {
        let folders = ["/n/a", "/n/b", "/n/c"]
        XCTAssertEqual(PaperTab.column(folders: folders, showsAgents: true),
                       [.inbox, .clipboard, .feeds, .agents, .folder("/n/a"), .folder("/n/b"), .folder("/n/c")])
        XCTAssertEqual(PaperTab.column(folders: folders, showsAgents: false),
                       [.inbox, .clipboard, .feeds, .folder("/n/a"), .folder("/n/b"), .folder("/n/c")])
        let many = (1...12).map { "/n/\($0)" }
        XCTAssertEqual(PaperTab.column(folders: many, showsAgents: false).count, 15, "The column has no limit.")
        XCTAssertEqual(PaperTab.folder("/n/Field Notes").title, "Field Notes")
    }

    func testEachFixedTabHasItsColorAndNewFoldersTakeTheFolderColorsInOrder() {
        XCTAssertEqual(PaperTab.fixed.map { $0.color(folders: [:]) }, [.indigo, .zinc, .sky, .plum])
        var state = PaperDeskState()
        state.assignColors(to: ["/n/a", "/n/b", "/n/c"])
        XCTAssertEqual(state.folderColors, ["/n/a": .teal, "/n/b": .rose, "/n/c": .clay])
        state.assignColors(to: ["/n/a", "/n/b", "/n/c", "/n/d", "/n/e"])
        XCTAssertEqual(state.folderColors["/n/d"], .emerald)
        XCTAssertEqual(state.folderColors["/n/e"], .teal, "When each color is in use, the colors go round.")
        XCTAssertTrue(Set(TabColor.folderOrder).isDisjoint(with: PaperTab.fixed.map { $0.color(folders: [:]) }))
    }

    /// A removed folder gives back its color, and the next new folder takes it.
    func testARemovedFolderForgetsItsColorAndItsCount() {
        var state = PaperDeskState()
        state.assignColors(to: ["/n/a", "/n/b"])
        state.folderCounts = ["/n/a": 3, "/n/b": 4]
        state.assignColors(to: ["/n/b"])
        XCTAssertEqual(state.folderColors, ["/n/b": .rose])
        XCTAssertEqual(state.folderCounts, ["/n/b": 4])
        state.assignColors(to: ["/n/b", "/n/c"])
        XCTAssertEqual(state.folderColors["/n/c"], .teal)
    }

    func testAChosenTabColorRestoresAfterASave() {
        var state = PaperDeskState()
        state.assignColors(to: ["/n/a"])
        state.folderColors["/n/a"] = .clay
        state.assignColors(to: ["/n/a", "/n/b"])
        XCTAssertEqual(state.folderColors["/n/a"], .clay, "A new folder does not change a chosen color.")
        state.save(to: defaults)
        let restored = PaperDeskState.restore(from: defaults)
        XCTAssertEqual(PaperTab.folder("/n/a").color(folders: restored.folderColors), .clay)
    }

    func testAFolderChangeMovesTheFolderTabAndForgetsTheFile() {
        var state = PaperDeskState()
        state.tab = .folder("/tmp/a")
        state.scope = .folder
        state.expandedFolders = ["/tmp/a/x"]
        state.selectedFile = "x/c.md"
        state.resetForVault(root: "/tmp/b")
        XCTAssertEqual(state.tab, .folder("/tmp/b"))
        XCTAssertEqual(state.scope, .folder)
        XCTAssertEqual(state.expandedFolders, ["/tmp/a/x"], "The open folders hold absolute paths, so they stay.")
        XCTAssertNil(state.selectedFile)

        var feeds = PaperDeskState()
        feeds.tab = .feeds
        feeds.scope = .feed(.starred)
        feeds.resetForVault(root: "/tmp/b")
        XCTAssertEqual(feeds.tab, .feeds)
        XCTAssertEqual(feeds.scope, .feed(.starred))
    }

    func testRelativePathsStayInsideTheRoot() {
        XCTAssertEqual(PaperDeskState.relativePath(of: "/tmp/root", in: "/tmp/root"), "")
        XCTAssertEqual(PaperDeskState.relativePath(of: "/tmp/root/a/b", in: "/tmp/root/"), "a/b")
        XCTAssertNil(PaperDeskState.relativePath(of: "/tmp/rooted/a", in: "/tmp/root"))
        XCTAssertNil(PaperDeskState.relativePath(of: "/tmp/other", in: "/tmp/root"))
    }

    func testEachTabHasItsDefaultScope() {
        let state = PaperDeskState()
        XCTAssertEqual(state.defaultScope(for: .folder("/tmp/a"), root: "/tmp/root", sessionFolders: []), .folder)
        XCTAssertEqual(state.defaultScope(for: .feeds, root: "/tmp/root", sessionFolders: []), .feed(.allUnread))
        XCTAssertEqual(state.defaultScope(for: .agents, root: "/tmp/root", sessionFolders: ["/tmp/s"]), .sessions("/tmp/s"))
        XCTAssertEqual(state.defaultScope(for: .agents, root: "/tmp/root", sessionFolders: []), .sessions("/tmp/root"))
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
        let add = metrics.addTabGap + 50 + 2 * metrics.tabLabelPadding
        XCTAssertEqual(TabColumn.height(of: [60], addLength: 50), one + add)
        XCTAssertEqual(TabColumn.height(of: [60, 60], addLength: 50), 2 * one - metrics.tabShoulder + add)
        XCTAssertEqual(TabColumn.height(of: [], addLength: 50), 50 + 2 * metrics.tabLabelPadding)
    }

    /// The folder tabs show their first letter when the column with full
    /// labels is taller than the paper less its top and its foot room.
    func testFolderTabsBecomeStubsOnAShortPaper() {
        let metrics = AppDefaults.Papers.self
        let lengths: [CGFloat] = [60, 90, 60, 70, 70, 90, 80, 80, 90, 70]
        let column = TabColumn.height(of: lengths, addLength: 50)
        let fits = column + metrics.tabsTop + metrics.tabRoom
        XCTAssertFalse(TabColumn.usesStubs(lengths: lengths, addLength: 50, paperHeight: fits))
        XCTAssertTrue(TabColumn.usesStubs(lengths: lengths, addLength: 50, paperHeight: fits - 1))
        XCTAssertTrue(TabColumn.usesStubs(lengths: lengths + [60], addLength: 50, paperHeight: fits),
                      "One more folder past the height of the paper makes stubs.")
    }

    func testATabCountStopsAtItsLimit() {
        XCTAssertEqual(TabColumn.countText(4), "4")
        XCTAssertEqual(TabColumn.countText(AppDefaults.Papers.countLimit + 1), "\(AppDefaults.Papers.countLimit)+")
    }

    // MARK: - Folder Tree

    private let paths = ["index.md", "Field Notes/journal.md", "Field Notes/Essays/margins.md", "Work Log/sync.md"]

    private func tree(expanded: Set<String> = []) -> [FolderTreeRow] {
        FolderTree.rows(paths: paths, folders: ["Talks"], root: "/n", expanded: expanded)
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
    /// Arrow closes, and Return opens a file.
    func testTheTreeKeysOpenAndCloseFolders() async throws {
        for folder in ["a", "b"] {
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
        paper.choose(.folder(model.wikiPath))
        XCTAssertEqual(paper.state.scope, .folder)
        XCTAssertFalse(paper.showsIndex, "A folder tab has no index.")

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
    }

    /// A click on a folder tab makes its folder the active folder, and the
    /// tree shows the files of that folder. Each folder keeps its color.
    func testAFolderTabMakesItsFolderTheActiveFolder() async throws {
        let roots = ["Field Notes", "Talks", "Work Log"].map { root.appendingPathComponent($0) }
        for (index, folder) in roots.enumerated() {
            try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
            for file in 0...index { try Data("x\n".utf8).write(to: folder.appendingPathComponent("\(file).md")) }
        }
        let suite = "piper-paper-folder-tabs-" + UUID().uuidString
        let preferences = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { preferences.removePersistentDomain(forName: suite) }
        preferences.set(roots[0].path, forKey: AppDefaults.Key.vaultPath)
        let model = AppModel(store: CaptureStore(url: root.appendingPathComponent(".captures.sqlite")), preferences: preferences)
        model.addWikiFolders(Array(roots.dropFirst()))
        let paper = FeedPaperModel(model: model, defaults: preferences)
        paper.syncFolders()
        XCTAssertEqual(paper.tabs.filter(\.isFolder), roots.map { .folder($0.path) })
        XCTAssertEqual(roots.map { paper.color(of: .folder($0.path)) }, [.teal, .rose, .clay])

        for (index, folder) in roots.enumerated() {
            paper.choose(.folder(folder.path))
            for _ in 0..<400 where model.loading || model.files.count != index + 1 { try await Task.sleep(for: .milliseconds(20)) }
            XCTAssertEqual(model.wikiPath, folder.path)
            XCTAssertEqual(paper.state.tab, .folder(folder.path))
            XCTAssertEqual(paper.treeRows.map(\.name), (0...index).map { "\($0).md" })
            paper.recordFileCount()
            XCTAssertEqual(paper.fileCount(of: folder.path), index + 1)
        }
        XCTAssertEqual(paper.fileCount(of: roots[0].path), 1, "Another folder shows the count of its last scan.")

        paper.setTabColor(.plum)
        XCTAssertEqual(paper.color(of: .folder(roots[2].path)), .plum)
        XCTAssertEqual(paper.color(of: .folder(roots[0].path)), .teal)
        model.removeWikiFolder(roots[2].path)
        paper.syncFolders()
        XCTAssertEqual(paper.state.tab, .folder(model.wikiPath), "The tab moves to the next active folder.")
        XCTAssertNil(paper.state.folderColors[roots[2].path])
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
