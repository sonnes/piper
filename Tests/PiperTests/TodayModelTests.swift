import AppKit
import Captures
import Feeds
import Stream
import XCTest
@testable import Piper

/// The verbs of Today: Keep, Done with Undo, File, Send, and the selection of several rows.
@MainActor
final class TodayModelTests: XCTestCase {

    private var root: URL!
    private var model: AppModel!
    private var today: TodayModel!

    override func setUp() async throws {
        root = FileManager.default.temporaryDirectory.appendingPathComponent("piper-today-tests-" + UUID().uuidString)
        try FileManager.default.createDirectory(at: root.appendingPathComponent("Talks"), withIntermediateDirectories: true)
        try "# Harbor talk\n".write(to: root.appendingPathComponent("Talks/harbor-talk.md"), atomically: true, encoding: .utf8)
        let feedsURL = root.appendingPathComponent(".feeds/Feeds.sqlite")
        let database = try FeedDatabase(url: feedsURL)
        try database.save(Feed(id: "https://f.example/feed", title: "Fieldstone Weekly", nextFetch: .distantFuture))
        try database.insert(["one", "two"].map {
            Article(id: $0, feedID: "https://f.example/feed", url: "https://f.example/\($0)", title: "Post \($0)",
                    summary: "", published: Date(), arrived: Date())
        })
        model = AppModel(store: CaptureStore(url: root.appendingPathComponent(".captures.sqlite")), wikiPath: root.path,
                         feeds: FeedStore(url: feedsURL))
        model.reload()
        today = TodayModel(model: model)
    }

    override func tearDown() async throws {
        try? FileManager.default.removeItem(at: root)
    }

    private func note(_ text: String) throws -> StreamItem {
        XCTAssertTrue(model.store.add(text, to: "Inbox", interpretSection: false))
        let note = try XCTUnwrap(model.store.notes.last)
        return .capture(note, children: [])
    }

    private func article(_ id: String) throws -> StreamItem {
        let article = try XCTUnwrap(model.feeds.article(id))
        return .article(article, feed: model.feeds.feed(article.feedID), score: 0)
    }

    private func clip(_ text: String) throws -> StreamItem {
        model.clipboard.receive([text])
        return .clip(try XCTUnwrap(model.clipboard.entries.first { $0.text == text }))
    }

    private func stored(_ item: StreamItem) -> Note? {
        model.store.notes.first { $0.id == item.note?.id }
    }

    // MARK: - Keep

    func testKeepMarksANoteAndASecondKeepTakesTheMarkAway() throws {
        let item = try note("Ask Mira about the lift order")
        today.keep([item])
        XCTAssertEqual(stored(item)?.isKept, true)
        today.keep([.capture(try XCTUnwrap(stored(item)), children: [])])
        XCTAssertEqual(stored(item)?.isKept, false)
    }

    func testKeepTurnsAnArticleIntoAKeptLinkCaptureAndAClipIntoAKeptNote() throws {
        today.keep([try article("one"), try clip("ssh harbor-staging-2")])
        let link = try XCTUnwrap(model.store.notes.first { $0.text == "https://f.example/one" })
        XCTAssertTrue(link.isKept)
        XCTAssertEqual(link.sources, ["Fieldstone Weekly"])
        XCTAssertEqual(model.feeds.article("one")?.read, true)
        XCTAssertTrue(model.store.notes.contains { $0.text == "ssh harbor-staging-2" && $0.isKept })
        XCTAssertTrue(model.clipboard.entries.isEmpty)
    }

    // MARK: - Done

    func testDoneOffersUndoForEachKind() throws {
        let item = try note("Crane 3 is down until the 28th")
        let entry = try clip("tail -f cranes.log")
        today.done([item, try article("one"), entry])
        XCTAssertEqual(stored(item)?.isDone, true)
        XCTAssertEqual(model.feeds.article("one")?.read, true)
        XCTAssertTrue(model.clipboard.entries.isEmpty)
        XCTAssertEqual(today.undo?.message, "Done · 3 items")

        today.runUndo()
        XCTAssertNil(today.undo)
        XCTAssertEqual(stored(item)?.isDone, false)
        XCTAssertEqual(model.feeds.article("one")?.read, false)
        XCTAssertEqual(model.clipboard.entries.map(\.text), ["tail -f cranes.log"])
    }

    func testTheUndoOfferLeavesAfterFiveSeconds() async throws {
        XCTAssertEqual(AppDefaults.Today.undoSeconds, 5)
        today.done([try note("Short-lived")])
        XCTAssertNotNil(today.undo)
    }

    func testDoneOnADigestMarksEachArticleAsRead() throws {
        let feed = try XCTUnwrap(model.feeds.feed("https://f.example/feed"))
        let digest = StreamItem.digest(model.feeds.articles(.allUnread), feed: feed, day: Date())
        today.done([digest])
        XCTAssertTrue(model.feeds.articles(.allUnread).isEmpty)
        today.runUndo()
        XCTAssertEqual(model.feeds.articles(.allUnread).count, 2)
    }

    func testDeleteRemovesACaptureWithUndo() throws {
        let item = try note("Delete me")
        today.delete([item])
        XCTAssertNil(stored(item))
        today.runUndo()
        XCTAssertNotNil(stored(item))
    }

    // MARK: - File

    func testFileIntoASectionMovesCapturesAndKeepsArticlesThere() throws {
        model.store.chooseSection("Harbor")
        let item = try note("Lift order: north dock first")
        XCTAssertTrue(today.file([item, try article("two")], to: .section("Harbor")))
        XCTAssertEqual(stored(item)?.section, "Harbor")
        let link = try XCTUnwrap(model.store.notes.first { $0.text == "https://f.example/two" })
        XCTAssertEqual(link.section, "Harbor")
        XCTAssertEqual(model.feeds.article("two")?.read, true)
    }

    func testFileIntoAFolderSavesANewFileAndMarksTheNoteDone() throws {
        let item = try note("Tide tables list heights, not currents.")
        XCTAssertTrue(today.file([item], to: .folder(root: root.path, folder: "Talks")))
        let text = try String(contentsOf: root.appendingPathComponent("Talks/tide-tables-list-heights-not-currents.md"), encoding: .utf8)
        XCTAssertEqual(text, "Tide tables list heights, not currents.\n")
        XCTAssertEqual(stored(item)?.isDone, true)
        // A second file with the same name gets a number.
        XCTAssertTrue(today.file([try note("Tide tables list heights, not currents.")], to: .folder(root: root.path, folder: "Talks")))
        XCTAssertTrue(FileManager.default.fileExists(atPath: root.appendingPathComponent("Talks/tide-tables-list-heights-not-currents-2.md").path))
    }

    func testFileIntoAFileAddsToItsEnd() throws {
        XCTAssertTrue(today.file([try note("Use this in the Thursday talk."), try article("one")], to: .file("Talks/harbor-talk.md")))
        let text = try String(contentsOf: root.appendingPathComponent("Talks/harbor-talk.md"), encoding: .utf8)
        XCTAssertEqual(text, "# Harbor talk\n\nUse this in the Thursday talk.\n\n- [Post one](https://f.example/one)\n")
    }

    func testFileTargetsListSectionsThenFoldersThenFiles() {
        let targets = FileTarget.targets(sections: ["Inbox", "Harbor"], roots: ["/n/Field Notes", "/n/Talks"], active: "/n/Talks",
                                         folders: ["Harbor"], files: ["Harbor/talk.md", "image.png"], query: "")
        XCTAssertEqual(targets, [.section("Inbox"), .section("Harbor"), .folder(root: "/n/Field Notes", folder: ""),
                                 .folder(root: "/n/Talks", folder: ""), .folder(root: "/n/Talks", folder: "Harbor"),
                                 .file("Harbor/talk.md")])
        XCTAssertEqual(targets[4].title, "Talks / Harbor")
        let search = FileTarget.targets(sections: ["Inbox", "Harbor"], roots: ["/n/Talks"], active: "/n/Talks",
                                        folders: ["Harbor"], files: ["Harbor/talk.md"], query: "harb")
        XCTAssertEqual(search, [.section("Harbor"), .folder(root: "/n/Talks", folder: "Harbor"), .file("Harbor/talk.md")])
    }

    // MARK: - Selection

    func testCommandClickShiftClickAndShiftArrowSelectSeveralRows() {
        let order: [StreamItem.Ref] = [.note(UUID()), .article("a"), .digest("f", Date(timeIntervalSince1970: 0)), .clip(UUID())]
        today.select(order[0])
        XCTAssertFalse(today.multiple)
        today.extend(to: order[2], range: true, in: order)
        XCTAssertEqual(today.selection, Set(order[0...2]))
        XCTAssertTrue(today.multiple)
        today.extend(to: order[1], range: false, in: order)
        XCTAssertEqual(today.selection, [order[0], order[2]])
        today.clearSelection()
        today.move(1, extending: false, in: order)
        XCTAssertEqual(today.selection, [order[0]])
        today.move(1, extending: true, in: order)
        XCTAssertEqual(today.selection, [order[0], order[1]])
        XCTAssertTrue(today.multiple)
        today.keepSelection(in: [order[1]])
        XCTAssertEqual(today.selection, [order[1]])
    }

    func testTheBarMergesAndCopiesTheSelection() throws {
        let first = try note("Lift order: north dock first on Tuesdays")
        let second = try note("Crane 3 is down until the 28th")
        let pasteboard = NSPasteboard(name: NSPasteboard.Name("com.piper.test." + UUID().uuidString))
        defer { pasteboard.releaseGlobally() }
        XCTAssertTrue(TodayModel.copy("x", to: pasteboard))
        today.merge([first, second])
        XCTAssertEqual(model.store.notes.filter { $0.parent == nil }.count, 1)
        XCTAssertEqual(model.store.notes.first?.text, "Lift order: north dock first on Tuesdays\n\nCrane 3 is down until the 28th")
        XCTAssertEqual(today.selection, [.note(try XCTUnwrap(first.note?.id))])
    }

    // MARK: - Capture Field

    func testTheCaptureFieldTellsNotesLinksAndSourcesApart() {
        XCTAssertEqual(CaptureDraft("Ask Mira about the lift order"), .note)
        XCTAssertEqual(CaptureDraft(" https://tides.example/guide \n"), .link(URL(string: "https://tides.example/guide")!))
        XCTAssertEqual(CaptureDraft("https://tides.example"), .source(URL(string: "https://tides.example")!))
        XCTAssertEqual(CaptureDraft("https://tides.example/feed.xml"), .source(URL(string: "https://tides.example/feed.xml")!))
        XCTAssertEqual(CaptureDraft("https://tides.example/blog/feed"), .source(URL(string: "https://tides.example/blog/feed")!))
        XCTAssertEqual(CaptureDraft("https://tides.example/?p=4"), .link(URL(string: "https://tides.example/?p=4")!))
        XCTAssertEqual(CaptureDraft("see https://tides.example/guide"), .note)
    }
}
