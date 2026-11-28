import Captures
@testable import Feeds
import XCTest
@testable import Piper

/// The Hacker News tab shows the front page and saves nothing until the reader keeps a story.
@MainActor
final class HackerNewsModelTests: XCTestCase {

    private var root: URL!
    private var model: AppModel!

    override func setUp() async throws {
        root = FileManager.default.temporaryDirectory.appendingPathComponent("piper-hacker-news-" + UUID().uuidString)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        model = AppModel(databaseURL: root.appendingPathComponent(".captures.sqlite"), wikiPath: root.path,
                         preferences: temporaryDefaults(),
                         feeds: FeedStore(url: root.appendingPathComponent(".feeds/Feeds.sqlite")) { XCTFail("\($0)") })
    }

    override func tearDown() async throws {
        try? FileManager.default.removeItem(at: root)
    }

    private let stories = [
        HackerNews.Story(id: 1, title: "Tide tables", url: "https://harbor.example/tides", author: "ada", points: 40,
                         comments: 3, time: Date()),
        HackerNews.Story(id: 2, title: "Ask HN: Ferries?", url: nil, author: "bo", points: 12, comments: 0, time: Date())
    ]

    func testTheFirstShowLoadsTheStoriesAndWritesNoFeedOrArticle() async {
        let stories = stories
        var fetches = 0
        let hackerNews = HackerNewsModel()
        hackerNews.fetch = { fetches += 1; return stories }
        hackerNews.loadIfEmpty()
        await hackerNews.task?.value
        hackerNews.loadIfEmpty()
        XCTAssertEqual(fetches, 1, "A second show keeps the stories.")
        XCTAssertEqual(hackerNews.stories.map(\.id), [1, 2])
        XCTAssertTrue(model.feeds.feeds.isEmpty)
        XCTAssertNil(model.feeds.article(stories[0].article.id))
    }

    func testAFailedRefreshShowsTheErrorAndKeepsTheStories() async {
        let stories = stories
        var fails = false
        let hackerNews = HackerNewsModel()
        hackerNews.fetch = {
            if fails { throw FeedError("Hacker News answered 500.") }
            return stories
        }
        hackerNews.refresh()
        await hackerNews.task?.value
        fails = true
        hackerNews.refresh()
        await hackerNews.task?.value
        XCTAssertEqual(hackerNews.error, "Hacker News answered 500.")
        XCTAssertEqual(hackerNews.stories.count, 2)
    }

    func testKeepSavesALinkCaptureWithHackerNewsAsItsSource() throws {
        let story = stories[0]
        XCTAssertTrue(model.articleActions.keep([story.article]))
        let note = try XCTUnwrap(PaperItem.keptNote(of: story.article, in: model.store))
        XCTAssertEqual(note.sources, ["Hacker News"])
        XCTAssertEqual(PaperItem.story(story).identity(in: model), .note(note.id))
        XCTAssertEqual(PaperItem.comments(story).identity(in: model), .comments(story), "The comments stay their own paper.")
        XCTAssertTrue(model.feeds.feeds.isEmpty, "Keep saves the story, not a feed.")
    }
}
