import CSQLite
import XCTest
@testable import Briefs

final class BriefsTests: XCTestCase {

    private var folder: URL!

    override func setUpWithError() throws {
        folder = FileManager.default.temporaryDirectory.appendingPathComponent("BriefsTests-" + UUID().uuidString)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: folder)
    }

    // MARK: - Hacker News

    func testHackerNewsAsksForTheLastDayOfPopularStories() {
        let url = HackerNews.requestURL(now: Date(timeIntervalSince1970: 200_000))
        let items = URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems ?? []
        XCTAssertEqual(items.first { $0.name == "tags" }?.value, "story")
        XCTAssertEqual(items.first { $0.name == "numericFilters" }?.value, "created_at_i>113600,points>=50")
    }

    func testHackerNewsSortsByPointsDropsBlockedAndLinksAskHN() throws {
        let data = Data(#"{"hits":[{"objectID":"1","title":"Low","url":"https://a.example/x","points":60,"num_comments":1},{"objectID":"2","title":"Ask HN","url":null,"points":90,"num_comments":5},{"objectID":"3","title":"Blocked","url":"https://b.example/y","points":500,"num_comments":9}]}"#.utf8)
        let stories = try HackerNews.stories(in: data, blocked: ["b.example"])
        XCTAssertEqual(stories.map(\.title), ["Ask HN", "Low"])
        XCTAssertEqual(stories[0].url, "https://news.ycombinator.com/item?id=2")
        XCTAssertEqual(stories[1].discussionURL, "https://news.ycombinator.com/item?id=1")
    }

    func testPicksPromptNumbersTheLinksAndHoldsTheirDetails() {
        let story = HackerNewsStory(title: "A story", url: "https://a.example/x", discussionURL: "https://news.ycombinator.com/item?id=1",
                                    points: 60, comments: 2, postedAt: Date())
        let article = FeedArticle(feed: "F", title: "An article", url: "https://b.example/y", summary: "The summary", starred: true, publishedAt: nil)
        let candidates = [
            BriefCandidate(url: story.url, title: story.title, host: "a.example", kind: .story, score: 2),
            BriefCandidate(url: article.url, title: article.title, host: "b.example", kind: .starredArticle, score: 1)
        ]
        let prompt = BriefPrompts.choosePicks(date: "Today", candidates: candidates, digest: HistoryDigest(totalSites: 0, sites: []),
                                              articles: [article], stories: [story])
        XCTAssertTrue(prompt.contains("1. A story (a.example, story), 60 points, 2 comments"))
        XCTAssertTrue(prompt.contains("2. An article (b.example, starredArticle)\n   The summary"))
        XCTAssertFalse(prompt.contains("https://"))
    }

    func testPicksKeepOnlyListedNumbersWithAReasonInRankOrder() {
        let candidates = (1...10).map {
            BriefCandidate(url: "https://a.example/\($0)", title: "T\($0)", host: "a.example", kind: .pageLink, score: Double(20 - $0))
        }
        let answer = #"Sure: [{"id": 4, "why": " Four. "}, {"id": 2, "why": "Two"}, {"id": 4, "why": "Again"}, {"id": 11, "why": "Out"}, {"id": 0, "why": "Zero"}, {"id": 3, "why": "  "}]"#

        let picks = BriefPrompts.picks(in: answer, candidates: candidates)

        XCTAssertEqual(picks.map(\.title), ["T2", "T4"])
        XCTAssertEqual(picks[1].why, "Four.")
        XCTAssertEqual(picks[1].url, "https://a.example/4")
        XCTAssertEqual(picks[1].state, .open)
        XCTAssertEqual(BriefPrompts.picks(in: "no json", candidates: candidates), [])
    }

    func testPicksStopAtTheLimit() {
        let candidates = (1...12).map {
            BriefCandidate(url: "https://a.example/\($0)", title: "T\($0)", host: "a.example", kind: .pageLink, score: 1)
        }
        let answer = "[" + (1...12).map { #"{"id": \#($0), "why": "W"}"# }.joined(separator: ",") + "]"
        XCTAssertEqual(BriefPrompts.picks(in: answer, candidates: candidates).count, BriefPrompts.pickLimit)
    }

    // MARK: - Repeats

    func testEarlierLinksDoNotComeBackButTodayCanRebuild() throws {
        let store = BriefStore(folder: folder)
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC")!
        let yesterday = Date(timeIntervalSince1970: 1_700_000_000)
        let today = yesterday.addingTimeInterval(86_400)
        try store.save(day("2023-11-14", picks: ["https://a.example/old/"]))
        try store.save(day("2023-11-15", picks: ["https://a.example/today"]))

        let seen = store.linksBefore(today, calendar: calendar)

        XCTAssertTrue(BriefLinks.isSeen("https://a.example/old#top", in: seen))
        XCTAssertFalse(BriefLinks.isSeen("https://a.example/today", in: seen))

        let data = Data(#"{"hits":[{"objectID":"1","title":"Old","url":"https://a.example/old","points":90,"num_comments":1},{"objectID":"2","title":"New","url":"https://a.example/new","points":60,"num_comments":1}]}"#.utf8)
        XCTAssertEqual(try HackerNews.stories(in: data, blocked: [], seen: seen).map(\.title), ["New"])

        let page = LoadedPage(host: "a.example", title: "A", links: [
            PageLink(label: "Old", url: "https://a.example/old"), PageLink(label: "New", url: "https://a.example/new")
        ]).removingLinks(in: seen)
        XCTAssertEqual(page.links.map(\.label), ["New"])
    }

    // MARK: - Catalog

    func testCatalogFindsEachChromiumProfileWithItsName() throws {
        let arc = folder.appendingPathComponent("Application Support/Arc/User Data")
        try makeDatabase(at: arc.appendingPathComponent("Default/History"), "CREATE TABLE t (a)")
        try makeDatabase(at: arc.appendingPathComponent("Profile 2/History"), "CREATE TABLE t (a)")
        try FileManager.default.createDirectory(at: arc.appendingPathComponent("Guest Profile"), withIntermediateDirectories: true)
        try Data(#"{"profile":{"info_cache":{"Profile 2":{"name":"Work"}}}}"#.utf8).write(to: arc.appendingPathComponent("Local State"))

        let sources = BrowserCatalog.sources(library: folder)

        XCTAssertEqual(sources.map(\.profile), ["Default", "Work"])
        XCTAssertEqual(Set(sources.map(\.name)), ["Arc"])
        XCTAssertFalse(sources.contains(where: \.needsAccess))
    }

    func testCatalogFindsFirefoxSafariAndNetNewsWire() throws {
        try makeDatabase(at: folder.appendingPathComponent("Application Support/zen/Profiles/abc.Default/places.sqlite"), "CREATE TABLE t (a)")
        try makeDatabase(at: folder.appendingPathComponent("Safari/History.db"), "CREATE TABLE t (a)")
        let accounts = "Containers/com.ranchero.NetNewsWire-Evergreen/Data/Library/Application Support/NetNewsWire/Accounts"
        try makeDatabase(at: folder.appendingPathComponent(accounts + "/OnMyMac/DB.sqlite3"), "CREATE TABLE t (a)")

        let sources = BrowserCatalog.sources(library: folder)

        XCTAssertEqual(sources.map(\.name), ["Zen", "Safari", "NetNewsWire"])
        XCTAssertEqual(sources.map(\.profile), ["Default", nil, "On My Mac"])
    }

    func testCatalogIsEmptyWithNoBrowser() {
        XCTAssertTrue(BrowserCatalog.sources(library: folder).isEmpty)
    }

    // MARK: - History

    func testEachFormatGivesTheSameDate() throws {
        let now = 1_790_000_000.0
        let chromium = folder.appendingPathComponent("chromium")
        try makeDatabase(at: chromium, """
        CREATE TABLE urls (id INTEGER, url TEXT, title TEXT);
        CREATE TABLE visits (url INTEGER, visit_time INTEGER);
        INSERT INTO urls VALUES (1, 'https://a.example/', 'A');
        INSERT INTO visits VALUES (1, \(Int64((now + 11_644_473_600) * 1_000_000)));
        INSERT INTO visits VALUES (1, 1000);
        """)
        let firefox = folder.appendingPathComponent("firefox")
        try makeDatabase(at: firefox, """
        CREATE TABLE moz_places (id INTEGER, url TEXT, title TEXT);
        CREATE TABLE moz_historyvisits (place INTEGER, visit_date INTEGER);
        INSERT INTO moz_places VALUES (1, 'https://a.example/', 'A');
        INSERT INTO moz_historyvisits VALUES (1, \(Int64(now * 1_000_000)));
        """)
        let safari = folder.appendingPathComponent("safari")
        try makeDatabase(at: safari, """
        CREATE TABLE history_items (id INTEGER, url TEXT);
        CREATE TABLE history_visits (history_item INTEGER, title TEXT, visit_time REAL);
        INSERT INTO history_items VALUES (1, 'https://a.example/');
        INSERT INTO history_visits VALUES (1, 'A', \(now - 978_307_200));
        """)
        let since = Date(timeIntervalSince1970: now - 86_400)

        for (url, format) in [(chromium, BriefSourceFormat.chromium), (firefox, .firefox), (safari, .safari)] {
            let source = BriefSource(id: url.path, name: "x", profile: nil, database: url, format: format)
            let visits = try HistoryReader.read(source, since: since)
            XCTAssertEqual(visits, [Visit(url: "https://a.example/", title: "A", date: Date(timeIntervalSince1970: now))], format.rawValue)
        }
    }

    func testReadingLeavesTheOriginalFileUnchanged() throws {
        let url = folder.appendingPathComponent("history")
        try makeDatabase(at: url, """
        CREATE TABLE urls (id INTEGER, url TEXT, title TEXT);
        CREATE TABLE visits (url INTEGER, visit_time INTEGER);
        """)
        let before = try Data(contentsOf: url)
        _ = try HistoryReader.read(BriefSource(id: "x", name: "x", profile: nil, database: url, format: .chromium), since: .distantPast)
        XCTAssertEqual(try Data(contentsOf: url), before)
    }

    // MARK: - NetNewsWire

    func testNetNewsWireReadsUnreadAndStarredAndUsesFeedNames() throws {
        let url = folder.appendingPathComponent("DB.sqlite3")
        try makeDatabase(at: url, """
        CREATE TABLE articles (articleID TEXT, feedID TEXT, title TEXT, contentText TEXT, url TEXT, externalURL TEXT, summary TEXT, datePublished DATE);
        CREATE TABLE statuses (articleID TEXT, read BOOL, starred BOOL, dateArrived DATE);
        INSERT INTO articles VALUES ('1', 'https://a.example/feed', 'Unread', 'Body', 'https://a.example/1', NULL, NULL, 100);
        INSERT INTO articles VALUES ('2', 'https://a.example/feed', 'Read', NULL, 'https://a.example/2', NULL, 'S', 100);
        INSERT INTO articles VALUES ('3', 'https://b.example/feed', 'Starred', NULL, 'https://b.example/3', NULL, 'S', 50);
        INSERT INTO articles VALUES ('4', 'https://a.example/feed', 'Old', NULL, 'https://a.example/4', NULL, 'S', 10);
        INSERT INTO articles VALUES ('5', 'https://blocked.example/feed', 'Blocked', NULL, 'https://blocked.example/5', NULL, 'S', 100);
        INSERT INTO statuses VALUES ('1', 0, 0, 1000);
        INSERT INTO statuses VALUES ('2', 1, 0, 1000);
        INSERT INTO statuses VALUES ('3', 1, 1, 1000);
        INSERT INTO statuses VALUES ('4', 0, 0, 1);
        INSERT INTO statuses VALUES ('5', 0, 0, 1000);
        """)
        try Data(#"<opml><body><outline title="Feed A" xmlUrl="https://a.example/feed"/></body></opml>"#.utf8)
            .write(to: folder.appendingPathComponent("Subscriptions.opml"))
        let source = BriefSource(id: "x", name: "NetNewsWire", profile: nil, database: url, format: .netNewsWire)

        let articles = try NetNewsWireReader.read(source, since: Date(timeIntervalSince1970: 500), blocked: ["blocked.example"])

        XCTAssertEqual(articles, [
            FeedArticle(feed: "b.example", title: "Starred", url: "https://b.example/3", summary: "S", starred: true,
                        publishedAt: Date(timeIntervalSince1970: 50)),
            FeedArticle(feed: "Feed A", title: "Unread", url: "https://a.example/1", summary: "Body", starred: false,
                        publishedAt: Date(timeIntervalSince1970: 100))
        ])
    }

    // MARK: - Blocked sites

    func testBlockCoversSubdomainsAtADomainBoundary() {
        let list = BlockedSites.normalized(["https://www.Example.com/x", "*.bank.test", "# note", ""])
        XCTAssertEqual(list, ["example.com", "bank.test"])
        XCTAssertTrue(BlockedSites.isBlocked("a.example.com", list: list))
        XCTAssertTrue(BlockedSites.isBlocked("my.bank.test", list: list))
        XCTAssertFalse(BlockedSites.isBlocked("notexample.com", list: list))
    }

    func testPrivateHostsAreAlwaysBlocked() {
        for host in ["localhost", "127.0.0.1", "10.1.2.3", "192.168.1.1", "172.20.0.1", "169.254.1.1", "server", "nas.local", "git.internal"] {
            XCTAssertTrue(BlockedSites.isBlocked(host, list: []), host)
        }
        XCTAssertFalse(BlockedSites.isBlocked("172.32.0.1", list: []))
        XCTAssertFalse(BlockedSites.allows("file:///etc/hosts", list: []))
        XCTAssertFalse(BlockedSites.allows("javascript:alert(1)", list: []))
    }

    // MARK: - Digest

    func testDigestRanksKeepsSingleVisitsDropsBlockedAndHoldsNoFullURL() {
        let now = Date(timeIntervalSince1970: 1_000_000)
        var visits = (0..<10).map { Visit(url: "https://www.top.example/secret/\($0)", title: "T\($0)", date: now) }
        visits += (0..<2).map { _ in Visit(url: "https://low.example/", title: "L", date: now.addingTimeInterval(-86_400 * 10)) }
        visits += (0..<20).map { _ in Visit(url: "https://mybank.example/", title: "B", date: now) }
        visits.append(Visit(url: "https://once.example/", title: "O", date: now))
        visits.append(Visit(url: "http://192.168.1.1/", title: "R", date: now))

        let digest = HistoryDigest(visits: visits, blocked: ["mybank.example"], now: now)

        XCTAssertEqual(digest.sites.map(\.host), ["top.example", "once.example", "low.example"])
        XCTAssertEqual(digest.totalSites, 3)
        XCTAssertEqual(digest.sites[0].sampleTitles.count, HistoryDigest.titleLimit)
        XCTAssertEqual(digest.sites[2].pages, 1)
        XCTAssertGreaterThan(digest.score(of: "once.example"), 0)
        XCTAssertFalse(digest.json.contains("secret"))
        XCTAssertFalse(digest.json.contains("mybank"))
    }

    func testDigestKeepsThirtySitesAndTheFullCount() {
        let now = Date()
        let visits = (0..<40).flatMap { index in
            (0..<2).map { _ in Visit(url: "https://s\(index).example/", title: nil, date: now) }
        }
        let digest = HistoryDigest(visits: visits, blocked: [], now: now)
        XCTAssertEqual(digest.sites.count, 30)
        XCTAssertEqual(digest.totalSites, 40)
    }

    func testDigestPutsMoreVisitsAndNewerVisitsFirst() {
        let now = Date(timeIntervalSince1970: 1_000_000)
        let hour: TimeInterval = 3_600
        var visits = (0..<5).map { _ in Visit(url: "https://many.example/", title: nil, date: now.addingTimeInterval(-hour)) }
        visits += (0..<2).map { _ in Visit(url: "https://few.example/", title: nil, date: now.addingTimeInterval(-hour)) }
        visits += (0..<2).map { _ in Visit(url: "https://new.example/", title: nil, date: now) }
        visits += (0..<2).map { _ in Visit(url: "https://old.example/", title: nil, date: now.addingTimeInterval(-48 * hour)) }

        let digest = HistoryDigest(visits: visits, blocked: [], now: now)

        XCTAssertEqual(digest.sites.map(\.host), ["many.example", "new.example", "few.example", "old.example"])
    }

    // MARK: - Ranking

    func testDecayPutsANewStoryAboveAnOldStoryWithMorePoints() {
        XCTAssertLessThan(Decay.score(points: 299, hours: 20), Decay.score(points: 99, hours: 2))
        XCTAssertEqual(Decay.score(points: 4, hours: -5), Decay.score(points: 4, hours: 0))
    }

    func testRankingUsesPointsAgeAndTheSiteOfEachLink() {
        let now = Date(timeIntervalSince1970: 1_000_000)
        let hour: TimeInterval = 3_600
        let digest = HistoryDigest(totalSites: 1, sites: [
            DigestSite(host: "fav.example", visits: 9, pages: 3, lastVisit: now, sampleTitles: [], score: 2)
        ])
        let stories = [
            HackerNewsStory(title: "Old", url: "https://a.example/old", discussionURL: "https://news.ycombinator.com/item?id=1",
                            points: 300, comments: 1, postedAt: now.addingTimeInterval(-20 * hour)),
            HackerNewsStory(title: "New", url: "https://a.example/new", discussionURL: "https://news.ycombinator.com/item?id=2",
                            points: 100, comments: 1, postedAt: now.addingTimeInterval(-2 * hour))
        ]
        let articles = [
            FeedArticle(feed: "F", title: "Plain", url: "https://plain.example/1", summary: "", starred: false,
                        publishedAt: now.addingTimeInterval(-3 * hour)),
            FeedArticle(feed: "F", title: "Favorite", url: "https://www.fav.example/1", summary: "", starred: false,
                        publishedAt: now.addingTimeInterval(-3 * hour))
        ]

        let ranked = BriefRanking.rank(stories: stories, articles: articles, pages: [], digest: digest,
                                       blocked: [], previousBuild: nil, now: now)

        XCTAssertEqual(ranked.map(\.title), ["New", "Favorite", "Plain", "Old"])
        XCTAssertEqual(ranked[1].host, "fav.example")
        XCTAssertEqual(ranked[1].kind, .article)
    }

    func testRankingDropsBlockedLinksCountsALinkOnceAndKeepsTheLimit() {
        let now = Date(timeIntervalSince1970: 1_000_000)
        let digest = HistoryDigest(totalSites: 0, sites: [])
        let links = (0..<40).map { PageLink(label: "L\($0)", url: "https://p.example/\($0)") }
            + [PageLink(label: "Same", url: "https://p.example/0/#top"), PageLink(label: "Bank", url: "https://bank.example/x")]
        let page = LoadedPage(host: "p.example", title: "P", links: links)

        let ranked = BriefRanking.rank(stories: [], articles: [], pages: [page], digest: digest,
                                       blocked: ["bank.example"], previousBuild: now.addingTimeInterval(-3_600), now: now)

        XCTAssertEqual(ranked.count, BriefRanking.candidateLimit)
        XCTAssertFalse(ranked.contains { $0.host == "bank.example" })
        XCTAssertEqual(Set(ranked.map { BriefLinks.normalized($0.url) }).count, ranked.count)
        XCTAssertEqual(ranked[0].score, Decay.score(points: BriefRanking.pageLinkPoints - 1, hours: 1), accuracy: 1e-9)
    }

    func testPageLinksWithoutAnEarlierBuildAreOneDayOld() {
        let now = Date(timeIntervalSince1970: 1_000_000)
        let page = LoadedPage(host: "p.example", title: "P", links: [PageLink(label: "L", url: "https://p.example/1")])
        let digest = HistoryDigest(totalSites: 0, sites: [])

        for previous in [nil, now.addingTimeInterval(-7 * 86_400)] {
            let ranked = BriefRanking.rank(stories: [], articles: [], pages: [page], digest: digest,
                                           blocked: [], previousBuild: previous, now: now)
            XCTAssertEqual(ranked[0].score, Decay.score(points: BriefRanking.pageLinkPoints - 1, hours: BriefRanking.undatedHours),
                           accuracy: 1e-9)
        }
    }

    // MARK: - Prompts

    func testHostsAcceptOnlyHostsInTheDigest() {
        let digest = digest(hosts: ["a.example", "b.example"])
        XCTAssertEqual(BriefPrompts.hosts(in: #"Here: ["b.example", "evil.example/?x=1", "b.example"]"#, digest: digest), ["b.example"])
    }

    func testHostsUseTheTopSitesWhenTheAnswerHasNone() {
        let digest = digest(hosts: (0..<12).map { "s\($0).example" })
        XCTAssertEqual(BriefPrompts.hosts(in: "no json", digest: digest), (0..<8).map { "s\($0).example" })
    }

    // MARK: - Schedule

    func testScheduleRunsOnceInTheMorning() {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC")!
        let date = { (day: Int, hour: Int) in calendar.date(from: DateComponents(year: 2026, month: 10, day: day, hour: hour))! }

        XCTAssertTrue(BriefSchedule.isDue(now: date(30, 5), lastTry: nil, enabled: true, calendar: calendar))
        XCTAssertTrue(BriefSchedule.isDue(now: date(30, 11), lastTry: date(29, 9), enabled: true, calendar: calendar))
        XCTAssertFalse(BriefSchedule.isDue(now: date(30, 9), lastTry: date(30, 6), enabled: true, calendar: calendar))
        XCTAssertFalse(BriefSchedule.isDue(now: date(30, 4), lastTry: nil, enabled: true, calendar: calendar))
        XCTAssertFalse(BriefSchedule.isDue(now: date(30, 12), lastTry: nil, enabled: true, calendar: calendar))
        XCTAssertFalse(BriefSchedule.isDue(now: date(30, 9), lastTry: nil, enabled: false, calendar: calendar))
    }

    // MARK: - Store

    func testStoreKeepsTheNewestBriefAndTheStateOfEachPick() throws {
        let store = BriefStore(folder: folder.appendingPathComponent("Briefs"))
        XCTAssertNil(store.latest())

        try store.save(day("2026-10-29", picks: ["https://a.example/old"]))
        try store.save(day("2026-10-30", picks: ["https://a.example/1", "https://a.example/2"]))
        let changed = try store.set(.kept, of: "https://a.example/1", in: "2026-10-30")

        XCTAssertEqual(store.latest()?.id, "2026-10-30")
        XCTAssertEqual(store.latest(), changed)
        XCTAssertEqual(store.latest()?.openPicks.map(\.url), ["https://a.example/2"])
        XCTAssertEqual(store.day("2026-10-30")?.picks.first?.state, .kept)
        XCTAssertNil(try store.set(.read, of: "https://a.example/none", in: "2026-10-30"))
        let permissions = try FileManager.default.attributesOfItem(atPath: store.folder.path)[.posixPermissions] as? Int
        XCTAssertEqual(permissions, 0o700)
    }

    // MARK: - Helpers

    private func day(_ id: String, picks urls: [String]) -> BriefDay {
        BriefDay(id: id, builtAt: Date(timeIntervalSince1970: 1_700_000_000),
                 picks: urls.map { BriefPick(url: $0, title: "T", host: "a.example", why: "W", score: 1) },
                 sites: [], feeds: [], failed: [])
    }

    private func digest(hosts: [String]) -> HistoryDigest {
        HistoryDigest(totalSites: hosts.count, sites: hosts.map {
            DigestSite(host: $0, visits: 2, pages: 1, lastVisit: Date(), sampleTitles: [], score: 1)
        })
    }

    private func makeDatabase(at url: URL, _ sql: String) throws {
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        var handle: OpaquePointer?
        defer { sqlite3_close(handle) }
        XCTAssertEqual(sqlite3_open(url.path, &handle), SQLITE_OK)
        XCTAssertEqual(sqlite3_exec(handle, sql, nil, nil, nil), SQLITE_OK, String(cString: sqlite3_errmsg(handle)))
    }
}
