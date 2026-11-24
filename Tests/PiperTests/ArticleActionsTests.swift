import Captures
@testable import Feeds
import XCTest
@testable import Piper

/// The read marks of feed articles: a mark that the reader chose can be
/// undone, and the mark of an opened article cannot.
@MainActor
final class ArticleActionsTests: XCTestCase {

    private var root: URL!
    private var model: AppModel!
    private let feed = "https://f.example/feed"

    override func setUp() async throws {
        root = FileManager.default.temporaryDirectory.appendingPathComponent("piper-article-actions-" + UUID().uuidString)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        let feedsURL = root.appendingPathComponent(".feeds/Feeds.sqlite")
        let database = try FeedDatabase(url: feedsURL)
        try database.save(Feed(id: feed, title: "Fieldstone Weekly", nextFetch: .distantFuture))
        try database.insert(["one", "two", "three"].map {
            Article(id: $0, feedID: feed, url: "https://f.example/\($0)", title: "Post \($0)", summary: "",
                    published: Date(), arrived: Date())
        })
        model = AppModel(databaseURL: root.appendingPathComponent(".captures.sqlite"), wikiPath: root.path,
                         preferences: temporaryDefaults(), feeds: FeedStore(url: feedsURL) { XCTFail("\($0)") })
    }

    override func tearDown() async throws {
        try? FileManager.default.removeItem(at: root)
    }

    private var unread: Set<String> {
        Set(model.feeds.articles(.feed(feed)).filter { !$0.read }.map(\.id))
    }

    func testMarkAllAsReadThenUndoRestoresTheUnreadArticles() {
        model.articleActions.setRead(true, ids: ["one"], undoable: false)
        model.articleActions.markAllRead(feed: feed)
        XCTAssertTrue(unread.isEmpty)
        model.undoManager.undo()
        XCTAssertEqual(unread, ["two", "three"])
        model.undoManager.redo()
        XCTAssertTrue(unread.isEmpty)
    }

    func testMarkAsUnreadCanBeUndone() {
        model.articleActions.setRead(true, ids: ["one"], undoable: false)
        model.articleActions.setRead(false, ids: ["one"], undoable: true)
        XCTAssertTrue(unread.contains("one"))
        model.undoManager.undo()
        XCTAssertFalse(unread.contains("one"))
    }

    func testOpeningAnArticleMarksItReadWithNoUndoStep() throws {
        model.articleActions.openURL = { _ in }
        model.articleActions.openInBrowser(try XCTUnwrap(model.feeds.article("one")))
        XCTAssertFalse(unread.contains("one"))
        XCTAssertFalse(model.undoManager.canUndo)
    }
}
