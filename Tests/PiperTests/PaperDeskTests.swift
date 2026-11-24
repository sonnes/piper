import AppKit
import Captures
import Feeds
import Vault
import XCTest
@testable import Piper

final class PaperDeskStateTests: XCTestCase {
    private var defaults: UserDefaults!
    private let suite = "piper-paper-desk-tests-" + UUID().uuidString

    override func setUp() {
        defaults = UserDefaults(suiteName: suite)
    }

    override func tearDown() { defaults.removePersistentDomain(forName: suite) }

    // MARK: - Save And Restore

    func testStateRestoresAfterASave() {
        var state = PaperDeskState()
        state.tab = .folder("/tmp/notes")
        state.scope = .folder
        state.lens = .kept
        state.expandedFolders = ["/tmp/notes/Field Notes", "/tmp/notes/Field Notes/Essays"]
        state.folderColors = ["/tmp/notes": .rose]
        state.folderCounts = ["/tmp/notes": 12]
        state.selectedFile = "Field Notes/reading-journal.md"
        state.save(to: defaults)

        XCTAssertEqual(PaperDeskState.restore(from: defaults), state)
    }

    func testEveryScopeRestores() {
        let scopes: [PaperScope] = [.today(section: nil), .today(section: "Work"), .done, .feed("a"),
                                    .folder, .sessions("/tmp/a")]
        for scope in scopes {
            var state = PaperDeskState()
            state.scope = scope
            state.save(to: defaults)
            XCTAssertEqual(PaperDeskState.restore(from: defaults).scope, scope)
        }
    }

    func testNoSavedStateOrABadStateOpensOnToday() {
        XCTAssertEqual(PaperDeskState.restore(from: defaults), PaperDeskState())
        defaults.set(Data("not json".utf8), forKey: AppDefaults.Key.paperDeskState)
        let state = PaperDeskState.restore(from: defaults)
        XCTAssertEqual(state.tab, .today)
        XCTAssertEqual(state.scope, .today(section: nil))
        XCTAssertEqual(state.lens, .all)
    }

    /// A key that this version cannot read takes its default, and the other keys stay.
    func testAStateWithATabThatNoLongerExistsOpensOnToday() throws {
        let old = [#"{"tab":{"inbox":{}},"scope":{"clipboard":{}},"expandedFolders":["/n/a"]}"#]
        for json in old {
            defaults.set(Data(json.utf8), forKey: AppDefaults.Key.paperDeskState)
            let state = PaperDeskState.restore(from: defaults)
            XCTAssertEqual(state.tab, .today)
            XCTAssertEqual(state.scope, .today(section: nil))
            XCTAssertEqual(state.expandedFolders, ["/n/a"])
            XCTAssertEqual(state.folderColors, [:])
        }
    }

    /// A feed scope restores on the Feeds tab, and the Feeds tab restores with a feed scope.
    func testAFeedScopeRestoresOnTheFeedsTab() {
        let saved: [(PaperTab, PaperScope, PaperTab, PaperScope)] = [
            (.today, .sources, .feeds, .sources),
            (.today, .feed("a"), .feeds, .feed("a")),
            (.folder("/n/a"), .feed("a"), .feeds, .feed("a")),
            (.feeds, .done, .feeds, .sources),
            (.feeds, .feed("a"), .feeds, .feed("a")),
        ]
        for (tab, scope, restoredTab, restoredScope) in saved {
            var state = PaperDeskState()
            state.tab = tab
            state.scope = scope
            state.save(to: defaults)
            let restored = PaperDeskState.restore(from: defaults)
            XCTAssertEqual(restored.tab, restoredTab)
            XCTAssertEqual(restored.scope, restoredScope)
        }
    }

    // MARK: - Folder Tabs

    func testTheColumnHasTheFixedTabsThenOneTabForEachFolder() {
        let folders = ["/n/a", "/n/b", "/n/c"]
        XCTAssertEqual(PaperTab.column(folders: folders, showsAgents: true),
                       [.today, .feeds, .agents, .folder("/n/a"), .folder("/n/b"), .folder("/n/c")])
        XCTAssertEqual(PaperTab.column(folders: folders, showsAgents: false),
                       [.today, .feeds, .folder("/n/a"), .folder("/n/b"), .folder("/n/c")])
        let many = (1...12).map { "/n/\($0)" }
        XCTAssertEqual(PaperTab.column(folders: many, showsAgents: false).count, 14, "The column has no limit.")
        XCTAssertEqual(PaperTab.folder("/n/Field Notes").title, "Field Notes")
    }

    func testNewFoldersTakeTheFolderColorsInOrderAndNoFixedTabColor() {
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

    func testEachTabHasItsDefaultScope() {
        let state = PaperDeskState()
        XCTAssertEqual(state.defaultScope(for: .folder("/tmp/a"), root: "/tmp/root", sessionFolders: []), .folder)
        XCTAssertEqual(state.defaultScope(for: .today, root: "/tmp/root", sessionFolders: []), .today(section: nil))
        XCTAssertEqual(state.defaultScope(for: .feeds, root: "/tmp/root", sessionFolders: []), .sources)
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

    func testThePaperWindowHoldsTheMarginOfTheShadow() {
        let paper = NSRect(x: 100, y: 200, width: 520, height: 760)
        let margin = PaperWindow.Metrics.shadowMargin
        let window = PaperWindow.windowFrame(of: paper)
        XCTAssertEqual(window.width, paper.width + margin.left + margin.right)
        XCTAssertEqual(window.height, paper.height + margin.top + margin.bottom)
        XCTAssertEqual(PaperWindow.paperFrame(of: window), paper)
    }

    /// A paper that opens after another paper closed takes the free place, and
    /// does not cover a paper that is still open.
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
        XCTAssertEqual(right.maxX, 2000 - PaperDesk.Metrics.screenInset)

        let centered = PaperDesk.frame(index: 0, size: size, feed: nil, screen: screen)
        XCTAssertEqual(centered, NSRect(x: 700, y: 616, width: 600, height: 560))

        let small = PaperDesk.frame(index: 0, size: NSSize(width: 712, height: 860), feed: nil,
                                    screen: NSRect(x: 0, y: 0, width: 800, height: 600))
        XCTAssertEqual(small, NSRect(x: 44, y: 24, width: 712, height: 552))
    }

    // MARK: - Saved Frames

    func testAReaderPaperFrameRestoresForItsItem() {
        let note = UUID()
        var frames = PaperFrames()
        frames.set(NSRect(x: 10, y: 20, width: 500, height: 400), of: .note(note), kind: .note)
        frames.set(NSRect(x: 30, y: 40, width: 640, height: 700), of: .article("harbor-1"), kind: .reader)
        frames.set(NSRect(x: 50, y: 60, width: 520, height: 410), of: .note(note), kind: .note)
        frames.save(to: defaults)

        let restored = PaperFrames.restore(from: defaults)
        XCTAssertEqual(restored.frame(of: .note(note)), NSRect(x: 50, y: 60, width: 520, height: 410))
        XCTAssertEqual(restored.frame(of: .article("harbor-1")), NSRect(x: 30, y: 40, width: 640, height: 700))
        XCTAssertNil(restored.frame(of: .file))
        XCTAssertEqual(restored.entries.count, 2)
    }

    func testANewPaperTakesTheLastSizeOfItsKind() {
        var frames = PaperFrames()
        XCTAssertNil(frames.lastSize(of: .reader))
        frames.set(NSRect(x: 10, y: 20, width: 640, height: 720), of: .article("harbor-1"), kind: .reader)
        frames.set(NSRect(x: 30, y: 40, width: 820, height: 900), of: .file, kind: .reader)
        frames.set(NSRect(x: 50, y: 60, width: 480, height: 360), of: .note(UUID()), kind: .note)
        frames.save(to: defaults)

        let restored = PaperFrames.restore(from: defaults)
        XCTAssertEqual(restored.lastSize(of: .reader), NSSize(width: 820, height: 900))
        XCTAssertEqual(restored.lastSize(of: .note), NSSize(width: 480, height: 360))
        XCTAssertNil(restored.lastSize(of: .session))
    }

    func testTheFeedPaperFrameRestoresApartFromTheReaderFrames() {
        var frames = PaperFrames()
        XCTAssertNil(frames.feedFrame)
        frames.setFeedFrame(NSRect(x: 40, y: 80, width: 560, height: 760))
        for index in 0...PaperFrames.savedFrameLimit {
            frames.set(NSRect(x: 1, y: 2, width: 600, height: 700), of: .article("article-\(index)"), kind: .reader)
        }
        frames.save(to: defaults)
        XCTAssertEqual(PaperFrames.restore(from: defaults).feedFrame, NSRect(x: 40, y: 80, width: 560, height: 760))
    }

    /// A new feed paper lies at the left of the main screen. A saved frame
    /// comes back, moved onto a screen.
    func testTheFeedPaperOpensAtItsSavedFrameOrAtTheLeftOfTheScreen() {
        let screen = NSRect(x: 0, y: 0, width: 1440, height: 900)
        let size = FeedPaperController.paperSize
        XCTAssertEqual(PaperDesk.feedFrame(saved: nil, screens: [screen], main: screen),
                       NSRect(x: PaperDesk.Metrics.screenInset * 2, y: 450 - size.height / 2, width: size.width, height: size.height))
        XCTAssertEqual(PaperDesk.feedFrame(saved: NSRect(x: 40, y: 80, width: 560, height: 760), screens: [screen], main: screen),
                       NSRect(x: 40, y: 80, width: 560, height: 760))
        XCTAssertEqual(PaperDesk.feedFrame(saved: NSRect(x: 3000, y: 80, width: 560, height: 760), screens: [screen], main: screen),
                       NSRect(x: 880, y: 80, width: 560, height: 760))
    }

    func testFramesSavedWithoutLastSizesStillRestore() throws {
        let old = #"{"entries":[{"key":"file","frame":"{{1, 2}, {600, 700}}"}]}"#
        defaults.set(Data(old.utf8), forKey: AppDefaults.Key.readerFrames)
        let restored = PaperFrames.restore(from: defaults)
        XCTAssertEqual(restored.frame(of: .file), NSRect(x: 1, y: 2, width: 600, height: 700))
        XCTAssertNil(restored.lastSize(of: .reader))
    }

    func testTheStoreOfFramesForgetsTheOldestFrameWhenItIsFull() {
        var frames = PaperFrames()
        let limit = PaperFrames.savedFrameLimit
        for index in 0...limit {
            frames.set(NSRect(x: index, y: 0, width: 500, height: 400), of: .article("article-\(index)"), kind: .reader)
        }
        XCTAssertEqual(frames.entries.count, limit)
        XCTAssertNil(frames.frame(of: .article("article-0")))
        XCTAssertNotNil(frames.frame(of: .article("article-\(limit)")))
    }

    func testAPaperWithoutASavedFrameCascadesAndAPaperWithOneOpensThere() {
        let screens = [NSRect(x: 0, y: 0, width: 2000, height: 1200)]
        var frames = PaperFrames()
        XCTAssertNil(PaperDesk.frame(of: .file, saved: frames, screens: screens))
        frames.set(NSRect(x: 300, y: 200, width: 700, height: 800), of: .file, kind: .reader)
        XCTAssertEqual(PaperDesk.frame(of: .file, saved: frames, screens: screens),
                       NSRect(x: 300, y: 200, width: 700, height: 800))
        // A frame from a display that is gone comes back onto the screen.
        frames.set(NSRect(x: 3000, y: 200, width: 700, height: 800), of: .file, kind: .reader)
        XCTAssertEqual(PaperDesk.frame(of: .file, saved: frames, screens: screens),
                       NSRect(x: 1300, y: 200, width: 700, height: 800))
    }

    // MARK: - On The Screen

    func testAPaperOffTheScreenMovesOntoTheFirstScreen() {
        let screens = [NSRect(x: 0, y: 0, width: 1440, height: 900), NSRect(x: 1440, y: 0, width: 1920, height: 1080)]
        let minimum = ReaderPaperController.Metrics.minimumSize
        XCTAssertEqual(PaperPlacement.clamp(NSRect(x: -2000, y: 1500, width: 600, height: 500), to: screens, minimum: minimum),
                       NSRect(x: 0, y: 400, width: 600, height: 500))
        XCTAssertEqual(PaperPlacement.clamp(NSRect(x: 100, y: -300, width: 600, height: 500), to: screens, minimum: minimum),
                       NSRect(x: 100, y: 0, width: 600, height: 500))
    }

    func testAPaperStaysOnTheScreenThatHoldsMostOfIt() {
        let screens = [NSRect(x: 0, y: 0, width: 1440, height: 900), NSRect(x: 1440, y: 0, width: 1920, height: 1080)]
        let frame = NSRect(x: 1300, y: 100, width: 600, height: 500)
        XCTAssertEqual(PaperPlacement.clamp(frame, to: screens, minimum: ReaderPaperController.Metrics.minimumSize),
                       NSRect(x: 1440, y: 100, width: 600, height: 500))
    }

    func testAPaperLargerThanItsScreenShrinksButNotBelowItsMinimum() {
        let screens = [NSRect(x: 0, y: 0, width: 1000, height: 700)]
        let minimum = ReaderPaperController.Metrics.minimumSize
        XCTAssertEqual(PaperPlacement.clamp(NSRect(x: 100, y: 100, width: 1400, height: 900), to: screens, minimum: minimum),
                       NSRect(x: 0, y: 0, width: 1000, height: 700))
        let tiny = [NSRect(x: 0, y: 0, width: 300, height: 200)]
        XCTAssertEqual(PaperPlacement.clamp(NSRect(x: 0, y: 0, width: 800, height: 600), to: tiny, minimum: minimum).size, minimum)
    }

    // MARK: - Resize

    func testTheEdgeUnderThePointerPicksTheResize() {
        let paper = NSRect(x: 100, y: 100, width: 600, height: 500)
        XCTAssertEqual(PaperResize.edges(at: NSPoint(x: 97, y: 300), paper: paper), .left)
        XCTAssertEqual(PaperResize.edges(at: NSPoint(x: 701, y: 300), paper: paper), .right)
        XCTAssertEqual(PaperResize.edges(at: NSPoint(x: 400, y: 599), paper: paper), .top)
        XCTAssertEqual(PaperResize.edges(at: NSPoint(x: 400, y: 98), paper: paper), .bottom)
        XCTAssertEqual(PaperResize.edges(at: NSPoint(x: 108, y: 98), paper: paper), [.left, .bottom])
        XCTAssertEqual(PaperResize.edges(at: NSPoint(x: 698, y: 590), paper: paper), [.right, .top])
        // The text inside the paper and the margin far outside it take no resize.
        XCTAssertEqual(PaperResize.edges(at: NSPoint(x: 400, y: 300), paper: paper), [])
        XCTAssertEqual(PaperResize.edges(at: NSPoint(x: 80, y: 300), paper: paper), [])
    }

    func testAResizeKeepsTheMinimumAndTheScreen() {
        let screen = NSRect(x: 0, y: 0, width: 1440, height: 900)
        let start = NSRect(x: 100, y: 100, width: 600, height: 500)
        let minimum = NSSize(width: 420, height: 320)
        XCTAssertEqual(PaperResize.frame(from: start, edges: [.right, .bottom], delta: CGSize(width: 50, height: -40),
                                         minimum: minimum, screen: screen),
                       NSRect(x: 100, y: 60, width: 650, height: 540))
        XCTAssertEqual(PaperResize.frame(from: start, edges: .left, delta: CGSize(width: 400, height: 0),
                                         minimum: minimum, screen: screen),
                       NSRect(x: 280, y: 100, width: 420, height: 500))
        XCTAssertEqual(PaperResize.frame(from: start, edges: [.left, .top], delta: CGSize(width: -500, height: 900),
                                         minimum: minimum, screen: screen),
                       NSRect(x: 0, y: 100, width: 700, height: 800))
    }

    /// The band takes a click on each edge of the paper, the top edge under
    /// the hidden title bar too. A click inside the paper reaches the content.
    func testTheResizeBandTakesTheEdgesOfThePaperOnly() throws {
        let window = PaperWindow(paperSize: NSSize(width: 600, height: 560), minimumPaperSize: ReaderPaperController.Metrics.minimumSize)
        window.contentView = NSView()
        window.setPaperFrame(NSRect(x: 100, y: 100, width: 600, height: 560), display: true)
        let frameView = try XCTUnwrap(window.contentView?.superview)
        frameView.layoutSubtreeIfNeeded()
        let paper = PaperWindow.paperFrame(of: NSRect(origin: .zero, size: window.frame.size))
        for point in [NSPoint(x: paper.midX, y: paper.maxY - 1), NSPoint(x: paper.midX, y: paper.minY + 1),
                      NSPoint(x: paper.minX - 2, y: paper.midY), NSPoint(x: paper.maxX + 2, y: paper.midY)] {
            XCTAssertTrue(frameView.hitTest(point) is PaperResizeView, "\(point)")
        }
        XCTAssertFalse(frameView.hitTest(NSPoint(x: paper.midX, y: paper.midY)) is PaperResizeView)
    }

    func testADoubleClickOnTheHeaderFollowsTheSettingOfMacOS() {
        XCTAssertEqual(TitleBarDoubleClick.action(for: nil), .zoom)
        XCTAssertEqual(TitleBarDoubleClick.action(for: "Maximize"), .zoom)
        XCTAssertEqual(TitleBarDoubleClick.action(for: "Fill"), .zoom)
        XCTAssertEqual(TitleBarDoubleClick.action(for: "Minimize"), .minimize)
        XCTAssertEqual(TitleBarDoubleClick.action(for: "None"), .none)
    }

    func testAZoomFillsTheScreenAndASecondZoomPutsThePaperBack() throws {
        let window = PaperWindow(paperSize: NSSize(width: 600, height: 560), minimumPaperSize: ReaderPaperController.Metrics.minimumSize)
        let screen = try XCTUnwrap(window.screen ?? NSScreen.main, "The test needs a display.")
        let start = NSRect(x: screen.visibleFrame.minX + 100, y: screen.visibleFrame.minY + 100, width: 600, height: 560)
        window.setPaperFrame(start, display: false)
        window.zoom(nil)
        XCTAssertEqual(window.paperFrame, PaperPlacement.zoomed(in: (window.screen ?? screen).visibleFrame))
        window.zoom(nil)
        XCTAssertEqual(window.paperFrame, start)
    }

    // MARK: - Tab Stubs

    func testTheColumnHeightCountsTheOverlapAndTheAddTab() {
        let metrics = PaperTabs.Metrics.self
        let one = 60 + 2 * metrics.tabLabelPadding
        let add = metrics.addTabGap + 50 + 2 * metrics.tabLabelPadding
        XCTAssertEqual(TabColumn.height(of: [60], addLength: 50), one + add)
        XCTAssertEqual(TabColumn.height(of: [60, 60], addLength: 50), 2 * one - metrics.tabShoulder + add)
        XCTAssertEqual(TabColumn.height(of: [], addLength: 50), 50 + 2 * metrics.tabLabelPadding)
    }

    /// The folder tabs show their first letter when the column with full
    /// labels is taller than the paper less its top and its foot room.
    func testFolderTabsBecomeStubsOnAShortPaper() {
        let metrics = PaperTabs.Metrics.self
        let lengths: [CGFloat] = [60, 90, 60, 70, 70, 90, 80, 80, 90, 70]
        let column = TabColumn.height(of: lengths, addLength: 50)
        let fits = column + metrics.tabsTop + metrics.tabRoom
        XCTAssertFalse(TabColumn.usesStubs(lengths: lengths, addLength: 50, paperHeight: fits))
        XCTAssertTrue(TabColumn.usesStubs(lengths: lengths, addLength: 50, paperHeight: fits - 1))
        XCTAssertTrue(TabColumn.usesStubs(lengths: lengths + [60], addLength: 50, paperHeight: fits),
                      "One more folder past the height of the paper makes stubs.")
    }

    /// A selected row is indigo while its paper has the focus and gray when
    /// it does not, as in Finder. A row under the pointer has a faint fill.
    func testARowFillFollowsTheSelectionTheFocusAndThePointer() {
        XCTAssertEqual(PiperTheme.rowFill(selected: true, focused: true, hovered: false), PiperTheme.rowSelection)
        XCTAssertEqual(PiperTheme.rowFill(selected: true, focused: false, hovered: true), PiperTheme.paperTint)
        XCTAssertEqual(PiperTheme.rowFill(selected: false, focused: true, hovered: true), PiperTheme.rowHover)
        XCTAssertEqual(PiperTheme.rowFill(selected: false, focused: true, hovered: false), .clear)
    }

    func testATabCountStopsAtItsLimit() {
        XCTAssertEqual(TabColumn.countText(4), "4")
        XCTAssertEqual(TabColumn.countText(PaperTabs.Metrics.countLimit + 1), "\(PaperTabs.Metrics.countLimit)+")
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

    func testFoldersComeBeforeFilesInNaturalOrder() {
        let rows = FolderTree.rows(paths: ["page10.md", "page2.md", "Zeta/a.md", "alpha/b.md", "docs/docs/deep.md", "docs/top.md"],
                                   folders: [], root: "/n", expanded: ["/n/docs"])
        XCTAssertEqual(rows.map(\.path), ["alpha", "docs", "docs/docs", "docs/top.md", "Zeta", "page2.md", "page10.md"])
        XCTAssertEqual(rows.map(\.count), [1, 2, 1, 1, 1, 1, 1])
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

    /// Back, Forward, and a link in the editor change the file of the file
    /// paper. The "on the desk" mark and the file that the feed paper
    /// restores follow each change.
    func testTheDeskFollowsBackForwardAndLinks() async throws {
        try Data("# Harbor\n".utf8).write(to: root.appendingPathComponent("notes/harbor.md"))
        let model = AppModel(store: CaptureStore(url: root.appendingPathComponent(".captures.sqlite")), wikiPath: root.path, preferences: temporaryDefaults())
        model.library.reload()
        try await waitFor("The scan finds both files.") { !model.library.loading && model.library.files.count == 2 }
        let suite = "piper-paper-desk-window-tests-" + UUID().uuidString
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let desk = PaperDesk(model: model, defaults: defaults)
        defer { desk.hide() }

        desk.openFile("notes/journal.md")
        desk.openFile("notes/harbor.md")
        XCTAssertTrue(desk.paper.marks.isOpenFile("notes/harbor.md"))

        model.files.navigate(-1)
        XCTAssertEqual(desk.paper.state.selectedFile, "notes/journal.md")
        XCTAssertEqual(PaperDeskState.restore(from: defaults).selectedFile, "notes/journal.md")
        XCTAssertTrue(desk.paper.marks.isOpenFile("notes/journal.md"))
        XCTAssertFalse(desk.paper.marks.isOpenFile("notes/harbor.md"))

        model.files.navigate(1)
        XCTAssertEqual(desk.paper.state.selectedFile, "notes/harbor.md")
        XCTAssertTrue(desk.paper.marks.isOpenFile("notes/harbor.md"))

        model.files.openEditorLink(kind: "link", target: "journal.md")
        XCTAssertEqual(model.files.selectedDocument, "notes/journal.md")
        XCTAssertEqual(PaperDeskState.restore(from: defaults).selectedFile, "notes/journal.md")
        XCTAssertTrue(desk.paper.marks.isOpenFile("notes/journal.md"))
    }

    /// A kept feed article and its link capture are one paper: they share
    /// the "on the desk" mark and the saved frame.
    func testAKeptArticleAndItsCaptureAreOnePaper() throws {
        let feedsURL = root.appendingPathComponent(".feeds/Feeds.sqlite")
        let database = try FeedDatabase(url: feedsURL)
        try database.save(Feed(id: "https://example.com/feed", title: "Example", nextFetch: .distantFuture))
        try database.insert([Article(id: "a1", feedID: "https://example.com/feed", url: "https://example.com/harbor",
                                     title: "Harbor", summary: "", published: Date(), arrived: Date())])
        let model = AppModel(store: CaptureStore(url: root.appendingPathComponent(".captures.sqlite")), wikiPath: root.path, preferences: temporaryDefaults(),
                             feeds: FeedStore(url: feedsURL) { XCTFail("\($0)") })
        let article = PaperItem.article("a1")
        XCTAssertEqual(article.identity(in: model), article, "An article that nobody kept is its own paper.")

        model.articleActions.keep([try XCTUnwrap(model.feeds.article("a1"))])
        let note = try XCTUnwrap(model.store.article(for: URL(string: "https://example.com/harbor")!))
        XCTAssertEqual(article.identity(in: model), .note(note.id))
        XCTAssertTrue(article.isArticle(in: model))
        XCTAssertTrue(PaperItem.note(note.id).isArticle(in: model))

        let marks = DeskMarks()
        marks.identity = { $0.identity(in: model) }
        marks.open = [article]
        XCTAssertTrue(marks.isOpen(.note(note.id)))
    }

    /// Window > Feeds, the command palette, and a pasted feed address open
    /// Sources on the Feeds tab. A pasted address waits for Sources to look it up.
    func testShowSourcesOpensSourcesOnTheFeedsTabWithTheAddress() async throws {
        let model = AppModel(store: CaptureStore(url: root.appendingPathComponent(".captures.sqlite")), wikiPath: root.path, preferences: temporaryDefaults())
        let suite = "piper-paper-desk-sources-tests-" + UUID().uuidString
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let desk = PaperDesk(model: model, defaults: defaults)
        defer { desk.hide() }
        desk.paper.state.tab = .agents
        desk.showSources()
        XCTAssertTrue(desk.isVisible)
        XCTAssertEqual(desk.paper.state.tab, .feeds)
        XCTAssertEqual(desk.paper.state.scope, .sources)
        XCTAssertNil(desk.paper.sourcesAddress)

        desk.paper.pick(.today(section: nil))
        XCTAssertEqual(desk.paper.state.tab, .today)
        desk.paper.pick(.feed("https://tides.example/feed.xml"))
        XCTAssertEqual(desk.paper.state.tab, .feeds, "A feed shows on the Feeds tab.")
        desk.paper.choose(.folder(model.library.wikiPath))
        desk.paper.pick(.sources)
        XCTAssertEqual(desk.paper.state.tab, .feeds, "Sources leaves a folder tab for the Feeds tab.")

        let request = desk.paper.addressRequest
        desk.addFeed()
        XCTAssertEqual(desk.paper.state.scope, .sources)
        XCTAssertNotEqual(desk.paper.addressRequest, request, "Add Feed asks for the cursor in the address field.")

        desk.paper.pick(.today(section: nil))
        desk.paper.showSources(address: "https://tides.example/feed.xml")
        XCTAssertEqual(desk.paper.state.scope, .sources)
        XCTAssertEqual(desk.paper.sourcesAddress, "https://tides.example/feed.xml")
    }

    /// New Capture, Window > Today, and the menu bar item show the feed paper
    /// on Today with an empty search and a request for the capture field.
    func testNewCaptureShowsTodayWithTheCaptureField() async throws {
        let model = AppModel(store: CaptureStore(url: root.appendingPathComponent(".captures.sqlite")), wikiPath: root.path, preferences: temporaryDefaults())
        let suite = "piper-paper-desk-capture-tests-" + UUID().uuidString
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let desk = PaperDesk(model: model, defaults: defaults)
        defer { desk.hide() }
        XCTAssertNoThrow(try model.store.add("Fictional note", section: model.store.activeSection))
        desk.paper.pick(.done)
        desk.paper.today.query = "fictional"
        desk.paper.today.selection = Set(model.store.notes.map { .note($0.id) })
        XCTAssertNil(desk.paper.composerRequest)

        desk.newCapture()
        XCTAssertTrue(desk.isVisible)
        XCTAssertEqual(desk.paper.state.tab, .today)
        XCTAssertEqual(desk.paper.state.scope, .today(section: nil))
        XCTAssertFalse(desk.paper.showsIndex)
        XCTAssertEqual(desk.paper.today.query, "")
        XCTAssertTrue(desk.paper.today.selection.isEmpty)
        let first = try XCTUnwrap(desk.paper.composerRequest)

        desk.newCapture()
        XCTAssertNotEqual(desk.paper.composerRequest, first, "Each request focuses the add field again.")
    }

    /// The tree keys of the feed paper: Right Arrow opens and steps in, Left
    /// Arrow closes, and Return opens a file.
    func testTheTreeKeysOpenAndCloseFolders() async throws {
        for folder in ["a", "b"] {
            try FileManager.default.createDirectory(at: root.appendingPathComponent(folder), withIntermediateDirectories: true)
            try Data("x\n".utf8).write(to: root.appendingPathComponent("\(folder)/x.md"))
        }
        let model = AppModel(store: CaptureStore(url: root.appendingPathComponent(".captures.sqlite")), wikiPath: root.path, preferences: temporaryDefaults())
        model.library.reload()
        try await waitFor("The scan finds the files.") { !model.library.loading && !model.library.files.isEmpty }
        let suite = "piper-paper-tree-tests-" + UUID().uuidString
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let desk = PaperDesk(model: model, defaults: defaults)
        defer { desk.hide() }
        let paper = desk.paper
        paper.choose(.folder(model.library.wikiPath))
        XCTAssertEqual(paper.state.scope, .folder)
        XCTAssertFalse(paper.showsIndex, "A folder tab has no index.")

        let a = URL(fileURLWithPath: model.library.wikiPath).appendingPathComponent("a").path
        XCTAssertEqual(paper.treeCursor(in: paper.treeRows), a)
        paper.treeKey(.right)
        XCTAssertEqual(paper.state.expandedFolders, [a])
        paper.treeKey(.right)
        XCTAssertEqual(paper.treeCursor(in: paper.treeRows), a + "/x.md")
        paper.treeKey(.enter)
        XCTAssertTrue(paper.marks.isOpen(.file))
        XCTAssertEqual(model.files.selectedDocument, "a/x.md")
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
        model.library.addWikiFolders(roots.dropFirst().map(\.path))
        let paper = FeedPaperModel(model: model, defaults: preferences)
        XCTAssertEqual(paper.tabs.filter(\.isFolder), roots.map { .folder($0.path) })
        XCTAssertEqual(roots.map { paper.color(of: .folder($0.path)) }, [.teal, .rose, .clay])

        for (index, folder) in roots.enumerated() {
            paper.choose(.folder(folder.path))
            try await waitFor("The scan of \(folder.lastPathComponent) finishes.") {
                !model.library.loading && model.library.files.count == index + 1
            }
            XCTAssertEqual(model.library.wikiPath, folder.path)
            XCTAssertEqual(paper.state.tab, .folder(folder.path))
            XCTAssertEqual(paper.treeRows.map(\.name), (0...index).map { "\($0).md" })
            paper.recordFileCount()
            XCTAssertEqual(paper.fileCount(of: folder.path), index + 1)
        }
        XCTAssertEqual(paper.fileCount(of: roots[0].path), 1, "Another folder shows the count of its last scan.")

        paper.setTabColor(.plum)
        XCTAssertEqual(paper.color(of: .folder(roots[2].path)), .plum)
        XCTAssertEqual(paper.color(of: .folder(roots[0].path)), .teal)
        model.library.removeWikiFolder(roots[2].path)
        paper.assignColors()
        XCTAssertEqual(paper.state.tab, .folder(model.library.wikiPath), "The tab moves to the next active folder.")
        XCTAssertNil(paper.state.folderColors[roots[2].path])
    }

    /// The paper fills its frame in the window. The hidden title bar takes no
    /// room, so the column of tabs has the whole height of the paper.
    func testTheFeedPaperFillsItsFrame() async throws {
        let model = AppModel(store: CaptureStore(url: root.appendingPathComponent(".captures.sqlite")), wikiPath: root.path, preferences: temporaryDefaults())
        let suite = "piper-paper-frame-tests-" + UUID().uuidString
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let paper = FeedPaperModel(model: model, defaults: defaults)
        let desk = PaperDesk(model: model, defaults: defaults)
        let controller = FeedPaperController(model: model, paper: paper, desk: desk,
                                             frame: NSRect(origin: .zero, size: FeedPaperController.paperSize))
        let window = try XCTUnwrap(controller.window as? PaperWindow)
        window.setPaperFrame(NSRect(x: 100, y: 100, width: 560, height: 700), display: true)
        window.contentView?.layoutSubtreeIfNeeded()
        try await waitFor("The paper takes the height of its frame.") {
            window.contentView?.layoutSubtreeIfNeeded()
            return paper.paperHeight == 700
        }
    }
}
