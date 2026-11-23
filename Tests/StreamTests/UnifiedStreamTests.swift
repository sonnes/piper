import XCTest
import Captures
import Feeds
@testable import Stream

final class UnifiedStreamTests: XCTestCase {

    private let now = ISO8601DateFormatter().date(from: "2026-11-23T12:00:00Z")!
    private var calendar: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC")!
        return calendar
    }

    private func note(_ text: String, hoursAgo: Double, section: String = "Inbox", reading: Reading? = nil,
                      parent: UUID? = nil, tags: [String] = [], done: Bool = false) -> Note {
        Note(text: text, section: section, isDone: done, createdAt: now.addingTimeInterval(-hoursAgo * 3_600),
             modifiedAt: now, parent: parent, tags: tags, reading: reading)
    }

    private func article(_ id: String, feed: String = "f", url: String? = nil, title: String? = nil,
                         hoursAgo: Double = 1, read: Bool = false) -> Article {
        let date = now.addingTimeInterval(-hoursAgo * 3_600)
        return Article(id: id, feedID: feed, url: url ?? "https://\(feed).example/\(id)", title: title ?? id,
                       summary: "", published: date, arrived: date, read: read)
    }

    private func feed(_ id: String = "f", mode: FeedMode = .best) -> Feed {
        Feed(id: id, title: id.uppercased() + " Weekly", home: "https://\(id).example", mode: mode)
    }

    // MARK: - Merge

    func testAllJoinsCapturesAndArticlesByDay() {
        let started = note("https://a.example/started", hoursAgo: 30, reading: Reading(title: "Started", openedAt: now))
        let input = UnifiedStream.Input(
            notes: [started, note("A note", hoursAgo: 2), note("Yesterday's note", hoursAgo: 20)],
            clips: [ClipboardEntry(text: "ssh harbor", copiedAt: now)],
            articles: [article("one", hoursAgo: 1)], feeds: [feed()])
        let stream = UnifiedStream(input, lens: .all, now: now, calendar: calendar)
        XCTAssertEqual(stream.groups.map(\.title), ["Continue Reading", "Today", "Yesterday"])
        XCTAssertEqual(stream.groups[1].items.map(\.title), ["one", "A note"])
        XCTAssertEqual(stream.groups[1].items.map(\.kind), [.article, .note])
        XCTAssertEqual(stream.tray.map(\.title), ["ssh harbor"])
        XCTAssertEqual(stream.counts[.all], 4)
    }

    func testAKeptArticleAndItsLinkCaptureShowAsOneRow() {
        let capture = note("https://www.f.example/one?utm_source=rss", hoursAgo: 3, tags: [Note.keptTag])
        let input = UnifiedStream.Input(notes: [capture], articles: [article("one"), article("two")], feeds: [feed()])
        let stream = UnifiedStream(input, lens: .all, now: now, calendar: calendar)
        XCTAssertEqual(stream.items.map(\.id), [.article("two"), .note(capture.id)])
        XCTAssertEqual(stream.items.last?.kind, .link)
    }

    func testASectionShowsNoArticles() {
        let input = UnifiedStream.Input(notes: [note("Research", hoursAgo: 1, section: "Research"), note("Other", hoursAgo: 1)],
                                        articles: [article("one")], feeds: [feed()])
        let stream = UnifiedStream(input, lens: .all, section: "Research", now: now, calendar: calendar)
        XCTAssertEqual(stream.items.map(\.title), ["Research"])
    }

    func testLenses() {
        let link = note("https://a.example/up-next", hoursAgo: 4)
        let kept = note("Kept note", hoursAgo: 3, tags: [Note.keptTag])
        let highlighted = note("https://a.example/marked", hoursAgo: 5)
        let input = UnifiedStream.Input(notes: [
            link, kept, highlighted, note("Plain note", hoursAgo: 2),
            note("A quote", hoursAgo: 1, parent: highlighted.id, tags: [ReadingList.highlightTag]),
            note("Done note", hoursAgo: 1, done: true)
        ], articles: [article("one")], feeds: [feed()])
        let notes = UnifiedStream(input, lens: .notes, now: now, calendar: calendar)
        XCTAssertEqual(notes.items.map(\.title), ["Plain note", "Kept note"])
        let reading = UnifiedStream(input, lens: .reading, now: now, calendar: calendar)
        XCTAssertEqual(reading.groups.map(\.title), ["Continue", "Up Next"])
        let keptLens = UnifiedStream(input, lens: .kept, now: now, calendar: calendar)
        XCTAssertEqual(keptLens.items.map(\.title), ["Kept note", "https://a.example/marked"])
        XCTAssertEqual(keptLens.items.last?.children.map(\.text), ["A quote"])
        XCTAssertEqual(notes.counts, [.all: 5, .notes: 2, .reading: 2, .kept: 2])
    }

    func testDoneGroupsByMonth() {
        let input = [note("Done", hoursAgo: 1, done: true), note("Open", hoursAgo: 1)]
        let groups = UnifiedStream.done(notes: input, calendar: calendar)
        XCTAssertEqual(groups.map(\.title), ["November 2026"])
        XCTAssertEqual(groups[0].items.map(\.title), ["Done"])
    }

    // MARK: - Lifecycle

    func testCaptureStates() {
        XCTAssertEqual(StreamItem.state(of: note("New", hoursAgo: 1), children: []), .new)
        let opened = note("https://a.example/x", hoursAgo: 1, reading: Reading(openedAt: now))
        XCTAssertEqual(StreamItem.state(of: opened, children: []), .reading)
        XCTAssertEqual(StreamItem.state(of: opened, children: [note("quote", hoursAgo: 0)]), .kept)
        XCTAssertEqual(StreamItem.state(of: note("Kept", hoursAgo: 1, tags: [Note.keptTag]), children: []), .kept)
        XCTAssertEqual(StreamItem.state(of: note("Done", hoursAgo: 1, tags: [Note.keptTag], done: true), children: []), .done)
        let finished = note("https://a.example/y", hoursAgo: 1, reading: Reading(finishedAt: now))
        XCTAssertEqual(StreamItem.state(of: finished, children: []), .done)
    }

    func testArticleStates() {
        XCTAssertEqual(StreamItem.state(of: article("a")), .new)
        XCTAssertEqual(StreamItem.state(of: article("a", read: true)), .reading)
    }

    func testOldArticlesHaveNoRow() {
        let input = UnifiedStream.Input(notes: [], articles: [
            article("fresh", hoursAgo: 2),
            article("old", hoursAgo: 24 * 8)
        ], feeds: [feed(mode: .every)])
        XCTAssertEqual(UnifiedStream(input, lens: .all, now: now, calendar: calendar).items.map(\.title), ["fresh"])
    }

    // MARK: - Digest

    func testABusyFeedDayBecomesOneDigestRow() {
        let articles = (1...9).map { article("post-\($0)", hoursAgo: Double($0) / 10) }
        let input = UnifiedStream.Input(notes: [], articles: articles + [article("quiet", feed: "q")],
                                        feeds: [feed(), feed("q")])
        let stream = UnifiedStream(input, lens: .all, now: now, calendar: calendar)
        XCTAssertEqual(stream.items.map(\.kind), [.digest, .article])
        XCTAssertEqual(stream.items[0].title, "F Weekly")
        XCTAssertEqual(stream.items[0].articles.count, 9)
        XCTAssertEqual(stream.items[0].articles.first?.title, "post-1")
    }

    func testDigestGroupsByDay() {
        let articles = (1...4).map { article("today-\($0)", hoursAgo: Double($0)) }
            + (1...4).map { article("yesterday-\($0)", hoursAgo: 20 + Double($0)) }
        let rows = FeedRows.rows(articles: articles, feeds: [feed()], relevance: Relevance(), calendar: calendar)
        XCTAssertEqual(rows.map(\.kind), [.digest, .digest])
        XCTAssertEqual(Set(rows.map(\.articles.count)), [4])
    }

    func testFeedModes() {
        let articles = (1...5).map { article("p\($0)", hoursAgo: Double($0)) }
        func kinds(_ mode: FeedMode) -> [StreamItem.Kind] {
            FeedRows.rows(articles: articles, feeds: [feed(mode: mode)], relevance: Relevance(), calendar: calendar).map(\.kind)
        }
        XCTAssertEqual(kinds(.every), Array(repeating: .article, count: 5))
        XCTAssertEqual(kinds(.digest), [.digest])
        XCTAssertEqual(kinds(.best), [.digest])
        XCTAssertEqual(kinds(.off), [])
        // A quiet day in Best mode gives each article a row.
        let quiet = FeedRows.rows(articles: Array(articles.prefix(3)), feeds: [feed()], relevance: Relevance(), calendar: calendar)
        XCTAssertEqual(quiet.map(\.kind), [.article, .article, .article])
        // Digest mode gives a lone article its own row.
        let lone = FeedRows.rows(articles: [articles[0]], feeds: [feed(mode: .digest)], relevance: Relevance(), calendar: calendar)
        XCTAssertEqual(lone.map(\.kind), [.article])
    }

    func testBestModeGivesHighScoresTheirOwnRow() {
        let articles = (1...6).map { article("p\($0)", title: "Post \($0) about gardens", hoursAgo: Double($0)) }
            + [article("q", title: "Slow queues in small teams", hoursAgo: 7)]
        let relevance = Relevance(terms: ["queues", "teams"])
        let rows = FeedRows.rows(articles: articles, feeds: [feed()], relevance: relevance, calendar: calendar)
        XCTAssertEqual(rows.map(\.kind), [.article, .digest])
        XCTAssertEqual(rows[0].title, "Slow queues in small teams")
        XCTAssertEqual(rows[1].articles.count, 6)
    }

    func testSearchGivesEachMatchingArticleARow() {
        let articles = (1...6).map { article("p\($0)", title: $0 == 3 ? "Tide tables" : "Post \($0)") }
        let input = UnifiedStream.Input(notes: [], articles: articles, feeds: [feed()])
        let stream = UnifiedStream(input, lens: .all, query: "tide", now: now, calendar: calendar)
        XCTAssertEqual(stream.items.map(\.title), ["Tide tables"])
    }

    // MARK: - Score

    func testScoreOrdering() {
        let relevance = Relevance(keepRates: ["kept": 1], sites: ["visited.example": 1], terms: ["harbor", "cranes"])
        let plain = article("plain", feed: "other", title: "Plain post")
        let topic = article("topic", feed: "other", title: "How harbor lifts work")
        let site = article("site", feed: "other", url: "https://www.visited.example/a", title: "Visited")
        let kept = article("kept", feed: "kept", title: "From a kept feed")
        XCTAssertEqual(relevance.ranked([plain, site, kept, topic]).map(\.id), ["kept", "site", "topic", "plain"])
        XCTAssertEqual(relevance.score(plain), 0)
        XCTAssertEqual(relevance.score(kept), 3.0 / 8.0, accuracy: 0.0001)
    }

    func testRelevanceFromLocalSignals() {
        let relevance = Relevance(stats: ["f": FeedStats(postsPerWeek: 1, keepRate: 0.5, kept: 2)],
                                  history: ["www.a.example": 10, "b.example": 5],
                                  fileNames: ["Talks/thursday-talk.md", "harbor cranes.md"])
        XCTAssertEqual(relevance.keepRates, ["f": 0.5])
        XCTAssertEqual(relevance.sites, ["a.example": 1, "b.example": 0.5])
        XCTAssertEqual(relevance.terms, ["thursday", "talk", "harbor", "cranes"])
    }

    func testFeedStats() {
        let feeds = [feed(), feed("q")]
        let notes = [note("https://www.f.example/a", hoursAgo: 1), note("https://f.example/b", hoursAgo: 1),
                     note("A note about f.example", hoursAgo: 1)]
        let stats = FeedStats.compute(feeds: feeds, counts: ["f": 8, "q": 1], notes: notes)
        XCTAssertEqual(stats["f"], FeedStats(postsPerWeek: 2, keepRate: 0.25, kept: 2))
        XCTAssertEqual(stats["q"]?.keepRate, 0)
        XCTAssertEqual(stats["q"]?.postsPerWeek ?? 0, 0.25, accuracy: 0.0001)
    }
}
