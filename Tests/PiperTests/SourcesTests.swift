import Feeds
import Stream
import XCTest
@testable import Piper

/// The text and the site list of Sources, and the ways to open it.
@MainActor
final class SourcesTests: XCTestCase {

    func testTheRateSaysPostsAWeekOrAMonthAndTheKeepRate() {
        XCTAssertEqual(SourcesView.rate(FeedStats(postsPerWeek: 2, keepRate: 0.7, kept: 3)), "2 posts a week · you keep 70%")
        XCTAssertEqual(SourcesView.rate(FeedStats(postsPerWeek: 1, keepRate: 0, kept: 0)), "1 post a week · you keep 0%")
        XCTAssertEqual(SourcesView.rate(FeedStats(postsPerWeek: 0.5, keepRate: 0.4, kept: 1)), "2 posts a month · you keep 40%")
        XCTAssertEqual(SourcesView.rate(FeedStats(postsPerWeek: 0, keepRate: 0, kept: 0)), "No posts in 4 weeks")
        XCTAssertEqual(SourcesView.rate(nil), "No posts in 4 weeks")
    }

    func testSitesYouReadOftenLeaveOutAddedIgnoredAndFeedlessSites() {
        let feeds = [Feed(id: "https://lattice.example/feed", title: "Lattice Notes", home: "https://www.lattice.example")]
        let suggestions = [
            Suggestion(host: "portlog.example", feedURL: "https://portlog.example/rss", title: "Portlog", visits: 12, score: 9),
            Suggestion(host: "tidewater.example", feedURL: "https://tidewater.example/feed", title: nil, visits: 7, score: 12),
            Suggestion(host: "lattice.example", feedURL: "https://lattice.example/atom", title: nil, visits: 30, score: 40),
            Suggestion(host: "nofeed.example", feedURL: nil, title: nil, visits: 50, score: 50),
            Suggestion(host: "quiet.example", feedURL: "https://quiet.example/feed", title: nil, visits: 3, score: 2, ignored: true),
        ]
        XCTAssertEqual(SourcesView.sites(suggestions, feeds: feeds).map(\.host), ["tidewater.example", "portlog.example"])
        XCTAssertEqual(SourcesView.sites(suggestions, feeds: feeds, limit: 1).map(\.host), ["tidewater.example"])
    }

    func testSourcesIsTheLastRowOfTheTodayIndex() {
        let entries = IndexEntry.entries(tab: .today, sections: ["Inbox"], sessionFolders: [])
        XCTAssertEqual(entries.suffix(2), [.scope(.done), .scope(.sources)])
        XCTAssertFalse(PaperScope.sources.showsCaptures)
    }
}
