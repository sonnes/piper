import CSQLite
import XCTest
import Captures
import Feeds
@testable import Stream

@MainActor
final class StarMigrationTests: XCTestCase {

    private var folder: URL!

    override func setUp() async throws {
        folder = FileManager.default.temporaryDirectory.appendingPathComponent("piper-stream-tests-" + UUID().uuidString)
    }

    override func tearDown() async throws {
        try? FileManager.default.removeItem(at: folder)
    }

    /// A feed database with two starred articles, as an older version of Piper left it.
    private func starredFeeds() throws -> FeedStore {
        let url = folder.appendingPathComponent("Feeds.sqlite")
        let database = try FeedDatabase(url: url)
        try database.save(Feed(id: "https://f.example/feed", title: "Fieldstone Weekly", nextFetch: .distantFuture))
        try database.insert(["one", "two", "three"].map {
            Article(id: $0, feedID: "https://f.example/feed", url: "https://f.example/\($0)", title: "Post \($0)",
                    summary: "", published: Date(), arrived: Date())
        })
        var handle: OpaquePointer?
        XCTAssertEqual(sqlite3_open(url.path, &handle), SQLITE_OK)
        sqlite3_exec(handle, "UPDATE articles SET starred = 1 WHERE id IN ('one', 'two')", nil, nil, nil)
        sqlite3_close(handle)
        return FeedStore(url: url) { XCTFail("\($0)") }
    }

    func testStarsBecomeKeptLinkCapturesOneTime() throws {
        let feeds = try starredFeeds()
        let captures = CaptureStore(url: folder.appendingPathComponent("notes.sqlite"))
        // A capture of the second link exists, so the copy skips it.
        try captures.add("https://www.f.example/two", section: captures.activeSection)
        XCTAssertEqual(feeds.starredArticles().count, 2)

        XCTAssertEqual(try StarMigration.run(feeds: feeds, captures: captures), 1)
        let copy = try XCTUnwrap(captures.notes.first { $0.text == "https://f.example/one" })
        XCTAssertTrue(copy.isKept)
        XCTAssertEqual(copy.reading?.title, "Post one")
        XCTAssertEqual(copy.sources, ["Fieldstone Weekly"])
        XCTAssertEqual(captures.notes.count, 2)
        XCTAssertTrue(feeds.starredArticles().isEmpty)
        // Undo does not remove the copy.
        try captures.undo()
        XCTAssertTrue(captures.notes.contains { $0.id == copy.id })

        // A second run adds nothing.
        XCTAssertEqual(try StarMigration.run(feeds: feeds, captures: captures), 0)
        XCTAssertEqual(captures.notes.count, 2)
    }

    func testARunThatStopsBeforeTheStarsClearAddsNoSecondCopy() throws {
        let feeds = try starredFeeds()
        let captures = CaptureStore(url: folder.appendingPathComponent("notes.sqlite"))
        try captures.keep(links: [KeptLink(url: URL(string: "https://f.example/one")!)], recordUndo: false)
        XCTAssertEqual(try StarMigration.run(feeds: feeds, captures: captures), 1)
        XCTAssertEqual(captures.notes.map(\.text).sorted(), ["https://f.example/one", "https://f.example/two"])
    }
}
