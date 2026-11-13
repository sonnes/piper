import Foundation
import Testing
@testable import Feeds

/// Serves fixed answers to the requests of a test session.
final class StubProtocol: URLProtocol {

    struct Answer {
        let status: Int
        let body: String
        var headers: [String: String] = [:]
    }

    private static let lock = NSLock()
    nonisolated(unsafe) private static var answers: [String: Answer] = [:]
    nonisolated(unsafe) private static var requests: [URLRequest] = []

    /// Adds answers. Suites run in parallel, so a test never removes the answers of another.
    static func serve(_ new: [String: Answer]) {
        lock.withLock { answers.merge(new) { $1 } }
    }

    static func lastRequest(to url: String) -> URLRequest? {
        lock.withLock { requests.last { $0.url?.absoluteString == url } }
    }

    static func session() -> URLSession {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [StubProtocol.self]
        return URLSession(configuration: configuration)
    }

    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

    override func startLoading() {
        let url = request.url!
        let answer = Self.lock.withLock {
            Self.requests.append(request)
            return Self.answers[url.absoluteString] ?? Answer(status: 404, body: "")
        }
        let response = HTTPURLResponse(url: url, statusCode: answer.status, httpVersion: nil, headerFields: answer.headers)!
        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: Data(answer.body.utf8))
        client?.urlProtocolDidFinishLoading(self)
    }

    override func stopLoading() {}
}

private let rss = """
<?xml version="1.0"?>
<rss version="2.0"><channel><title>Garden Letters</title><link>https://gardenletters.example/</link>
<item><title>Planting garlic</title><link>https://gardenletters.example/garlic</link><guid>g1</guid>
<description>&lt;p&gt;The ground must be &lt;b&gt;cool&lt;/b&gt;.&lt;/p&gt;</description>
<pubDate>Thu, 12 Nov 2026 09:12:00 GMT</pubDate></item>
<item><title>Seed catalogs</title><link>https://gardenletters.example/seeds</link><guid>g2</guid></item>
<item><title>No link</title><guid>g3</guid></item>
</channel></rss>
"""

private func temporaryDatabase() -> URL {
    FileManager.default.temporaryDirectory.appendingPathComponent("FeedsTests-\(UUID().uuidString)/Feeds.sqlite")
}

@Suite(.serialized) struct FeedDatabaseTests {

    @Test func insertKeepsReadMarksOfKnownArticles() throws {
        let database = try FeedDatabase(url: temporaryDatabase())
        try database.save(Feed(id: "https://a.example/feed", title: "A"))
        let article = Article(id: "1", feedID: "https://a.example/feed", url: "https://a.example/1", title: "One",
                              summary: "", published: nil, arrived: Date())
        #expect(try database.insert([article]) == 1)
        try database.setRead(true, ids: ["1"])
        #expect(try database.insert([article]) == 0)
        #expect(try database.articles(.allUnread).isEmpty)
        #expect(try database.articles(.feed("https://a.example/feed")).first?.read == true)
    }

    @Test func articlesWithTheSameDateKeepTheFeedOrder() throws {
        let database = try FeedDatabase(url: temporaryDatabase())
        try database.save(Feed(id: "f", title: "F"))
        let date = Date(timeIntervalSince1970: 1_000_000)
        try database.insert(["c", "a", "b"].map {
            Article(id: $0, feedID: "f", url: $0, title: $0, summary: "", published: date, arrived: date)
        })
        try database.setRead(true, ids: ["c"])
        #expect(try database.articles(.feed("f")).map(\.id) == ["c", "a", "b"])
        #expect(try database.articles(.allUnread, keeping: ["c"]).map(\.id) == ["c", "a", "b"])
    }

    @Test func deleteFeedRemovesItsArticles() throws {
        let database = try FeedDatabase(url: temporaryDatabase())
        try database.save(Feed(id: "f", title: "F"))
        try database.insert([Article(id: "1", feedID: "f", url: "u", title: "t", summary: "", published: nil, arrived: Date())])
        try database.delete(feed: "f")
        #expect(try database.articles(.feed("f")).isEmpty)
        #expect(try database.unreadCounts().isEmpty)
    }

    @Test func pruneKeepsUnreadAndStarredArticles() throws {
        let database = try FeedDatabase(url: temporaryDatabase())
        try database.save(Feed(id: "f", title: "F"))
        let old = Date(timeIntervalSince1970: 0)
        try database.insert(["read", "unread", "starred"].map {
            Article(id: $0, feedID: "f", url: $0, title: $0, summary: "", published: nil, arrived: old)
        })
        try database.setRead(true, ids: ["read", "starred"])
        try database.setStarred(true, id: "starred")
        try database.prune(before: Date())
        #expect(Set(try database.articles(.feed("f")).map(\.id)) == ["unread", "starred"])
    }

    @Test func replaceSuggestionsKeepsIgnoredHosts() throws {
        let database = try FeedDatabase(url: temporaryDatabase())
        try database.replaceSuggestions([Suggestion(host: "a.example", feedURL: nil, title: nil, visits: 3, score: 1)])
        try database.ignore(host: "a.example")
        try database.replaceSuggestions([Suggestion(host: "a.example", feedURL: "x", title: nil, visits: 9, score: 9),
                                         Suggestion(host: "b.example", feedURL: nil, title: nil, visits: 1, score: 2)])
        let suggestions = try database.suggestions()
        #expect(suggestions.map(\.host) == ["b.example", "a.example"])
        #expect(suggestions.last?.ignored == true)
        #expect(suggestions.last?.visits == 3)
    }
}

@Suite(.serialized) struct FeedFetchTests {

    @Test func articlesSkipItemsWithNoLinkAndStripHTML() async throws {
        let parsed = try #require(try await FeedParser.parse(ParserData(url: "https://gardenletters.example/feed", data: Data(rss.utf8))))
        let articles = FeedFetch.articles(of: parsed, feedID: "f", now: Date())
        #expect(articles.count == 2)
        let garlic = try #require(articles.first { $0.title == "Planting garlic" })
        #expect(garlic.summary == "The ground must be cool .")
        #expect(garlic.published != nil)
    }

    @Test func articleIDsAreStableAcrossFetches() async throws {
        let parsed = try #require(try await FeedParser.parse(ParserData(url: "u", data: Data(rss.utf8))))
        let first = FeedFetch.articles(of: parsed, feedID: "f", now: Date()).map(\.id).sorted()
        let second = FeedFetch.articles(of: parsed, feedID: "f", now: Date()).map(\.id).sorted()
        #expect(first == second)
        #expect(FeedFetch.articles(of: parsed, feedID: "other", now: Date()).map(\.id).sorted() != first)
    }

    @Test func waitGrowsWithFailures() {
        let now = Date(timeIntervalSince1970: 0)
        #expect(FeedFetch.nextFetch(after: 0, now: now).timeIntervalSince1970 == 1800)
        #expect(FeedFetch.nextFetch(after: 2, now: now).timeIntervalSince1970 == 7200)
        #expect(FeedFetch.nextFetch(after: 99, now: now).timeIntervalSince1970 == 86_400)
    }

    @Test func conditionalGetSendsValidatorsAndReads304() async throws {
        StubProtocol.serve(["https://a.example/feed": .init(status: 304, body: "")])
        let feed = Feed(id: "https://a.example/feed", title: "A", etag: "\"v1\"", lastModified: "Thu, 12 Nov 2026 09:00:00 GMT")
        let result = try await FeedFetch.get(feed, session: StubProtocol.session())
        guard case .notModified = result else { Issue.record("Expected notModified"); return }
        #expect(StubProtocol.lastRequest(to: feed.id)?.value(forHTTPHeaderField: "If-None-Match") == "\"v1\"")
        #expect(StubProtocol.lastRequest(to: feed.id)?.value(forHTTPHeaderField: "If-Modified-Since") == "Thu, 12 Nov 2026 09:00:00 GMT")
    }
}

@Suite(.serialized) struct FeedDiscoveryTests {

    @Test func pageLinksToItsFeed() async throws {
        StubProtocol.serve([
            "https://gardenletters.example": .init(status: 200, body: """
            <html><head><title>Garden Letters</title>
            <link rel="alternate" type="application/rss+xml" title="Garden Letters" href="/feed.xml">
            </head><body></body></html>
            """),
            "https://gardenletters.example/feed.xml": .init(status: 200, body: rss)
        ])
        let found = try await FeedDiscovery.find("gardenletters.example", session: StubProtocol.session())
        #expect(found.map(\.url) == ["https://gardenletters.example/feed.xml"])
        #expect(found.first?.title == "Garden Letters")
        #expect(found.first?.format == "RSS")
        #expect(found.first?.articles == 3)
    }

    @Test func feedAddressIsReadAsItIs() async throws {
        StubProtocol.serve(["https://gardenletters.example/feed.xml": .init(status: 200, body: rss)])
        let found = try await FeedDiscovery.find("feed://gardenletters.example/feed.xml", session: StubProtocol.session())
        #expect(found.map(\.url) == ["https://gardenletters.example/feed.xml"])
    }

    @Test func pageWithNoFeedFindsNothing() async throws {
        StubProtocol.serve(["https://plain.example": .init(status: 200, body: "<html><head></head><body>Hi</body></html>")])
        let found = try await FeedDiscovery.find("https://plain.example", session: StubProtocol.session())
        #expect(found.isEmpty)
    }
}

@Suite(.serialized) @MainActor struct FeedStoreTests {

    @Test func subscribeFetchesAndCountsUnread() async throws {
        StubProtocol.serve(["https://store.example/feed.xml": .init(status: 200, body: rss, headers: ["ETag": "\"v1\""])])
        let store = FeedStore(url: temporaryDatabase(), session: StubProtocol.session())
        #expect(store.subscribe(url: "https://store.example/feed.xml", title: nil))
        #expect(!store.subscribe(url: "https://store.example/feed.xml", title: nil))
        while !store.fetching.isEmpty { try await Task.sleep(for: .milliseconds(20)) }
        let feed = try #require(store.feeds.first)
        #expect(feed.title == "Garden Letters")
        #expect(feed.etag == "\"v1\"")
        #expect(feed.home == "https://gardenletters.example/")
        #expect(store.totalUnread == 2)

        store.markAllRead(.allUnread)
        #expect(store.totalUnread == 0)
        #expect(store.articles(.allUnread).isEmpty)
    }

    @Test func failedFetchRecordsTheReason() async throws {
        let store = FeedStore(url: temporaryDatabase(), session: StubProtocol.session())
        store.subscribe(url: "https://gone.example/feed", title: "Gone")
        while !store.fetching.isEmpty { try await Task.sleep(for: .milliseconds(20)) }
        let feed = try #require(store.feeds.first)
        #expect(feed.failures == 1)
        #expect(feed.error == "The server answered 404.")
    }
}

@Suite struct OPMLImportTests {

    @Test func readsFeedsInFolders() throws {
        let file = FileManager.default.temporaryDirectory.appendingPathComponent("Subscriptions-\(UUID().uuidString).opml")
        try """
        <?xml version="1.0"?><opml version="1.1"><head><title>Subs</title></head><body>
        <outline text="Garden Letters" type="rss" xmlUrl="https://gardenletters.example/feed.xml" htmlUrl="https://gardenletters.example/"/>
        <outline text="Tools"><outline text="Small Tools" type="rss" xmlUrl="https://smalltools.example/rss"/></outline>
        </body></opml>
        """.write(to: file, atomically: true, encoding: .utf8)
        let feeds = try OPMLImport.feeds(in: file)
        #expect(feeds.map(\.feedURL) == ["https://gardenletters.example/feed.xml", "https://smalltools.example/rss"])
        #expect(feeds.first?.homePageURL == "https://gardenletters.example/")
    }

    @Test func missingFileExplainsTheFix() {
        #expect(throws: FeedError.self) { try OPMLImport.feeds(in: URL(fileURLWithPath: "/nonexistent/Subscriptions.opml")) }
    }
}
