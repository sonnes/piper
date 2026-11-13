import Foundation
import Observation

/// The subscriptions and their counts, for the sidebar and the article list.
/// It owns the database and the refresh of each feed.
///
/// The database calls run on the main thread. A fetch and its parse run in a
/// detached task, and the result comes back to the main thread.
@MainActor @Observable
public final class FeedStore {

    // MARK: - Properties

    public static let refreshInterval: TimeInterval = 30 * 60
    /// Piper removes a read article that is not starred after this many days.
    public static let keepDays = 30
    static let parallelFetches = 4

    public private(set) var feeds: [Feed] = []
    public private(set) var unreadCounts: [String: Int] = [:]
    public private(set) var starredCount = 0
    public private(set) var suggestions: [Suggestion] = []
    /// The IDs of the feeds that a fetch holds now.
    public private(set) var fetching: Set<String> = []
    /// Changes on each write, so a list of articles can read the database again.
    public private(set) var revision = 0
    public private(set) var loadError: String?

    public var totalUnread: Int { unreadCounts.values.reduce(0, +) }

    @ObservationIgnored private let database: FeedDatabase?
    @ObservationIgnored private let session: URLSession
    @ObservationIgnored private var timer: Timer?

    // MARK: - Initialization

    public init(url: URL? = nil, session: URLSession = .shared) {
        let location = url ?? FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("Piper/Feeds.sqlite")
        self.session = session
        do {
            database = try FeedDatabase(url: location)
        } catch {
            database = nil
            loadError = error.localizedDescription
        }
        reload()
    }

    /// Starts the timer of the refresh, and refreshes each feed that is due.
    public func start() {
        guard timer == nil else { return }
        timer = Timer.scheduledTimer(withTimeInterval: 60, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.refreshDue() }
        }
        refreshDue()
    }

    // MARK: - Subscriptions

    public func feed(_ id: String) -> Feed? { feeds.first { $0.id == id } }

    /// Adds the feed and fetches it now. Returns false if the feed exists.
    @discardableResult
    public func subscribe(url: String, title: String?, home: String? = nil) -> Bool {
        guard feed(url) == nil else { return false }
        let feed = Feed(id: url, title: title?.nilIfEmptyOrWhitespace ?? URL(string: url)?.host ?? url, home: home)
        write { try $0.save(feed) }
        refresh([feed])
        return true
    }

    /// Adds each feed that Piper does not have. Returns the count of new feeds.
    @discardableResult
    public func subscribe(_ specifiers: [OPMLFeedSpecifier]) -> Int {
        let new = specifiers.filter { feed($0.feedURL) == nil }
            .map { Feed(id: $0.feedURL, title: $0.title?.nilIfEmptyOrWhitespace ?? $0.feedURL, home: $0.homePageURL) }
        guard !new.isEmpty else { return 0 }
        write { database in try new.forEach(database.save) }
        refresh(new)
        return new.count
    }

    public func unsubscribe(_ id: String) {
        write { try $0.delete(feed: id) }
    }

    public func rename(_ id: String, to title: String) {
        guard var feed = feed(id), let title = title.nilIfEmptyOrWhitespace else { return }
        feed.title = title
        write { try $0.save(feed) }
    }

    // MARK: - Articles

    /// The articles of a row of the sidebar. See `FeedDatabase.articles`.
    public func articles(_ filter: FeedFilter, keeping: Set<String> = []) -> [Article] {
        (try? database?.articles(filter, keeping: keeping)) ?? []
    }

    /// The article with the ID, with its current marks.
    public func article(_ id: String) -> Article? {
        try? database?.article(id)
    }

    public func setRead(_ read: Bool, _ articles: [Article]) {
        let ids = articles.filter { $0.read != read }.map(\.id)
        guard !ids.isEmpty else { return }
        write { try $0.setRead(read, ids: ids) }
    }

    public func setStarred(_ starred: Bool, _ article: Article) {
        write { try $0.setStarred(starred, id: article.id) }
    }

    /// Marks as read each article that the filter shows.
    public func markAllRead(_ filter: FeedFilter) {
        setRead(true, articles(filter))
    }

    // MARK: - Suggestions

    public func replaceSuggestions(_ suggestions: [Suggestion]) {
        write { try $0.replaceSuggestions(suggestions) }
    }

    public func ignore(_ suggestion: Suggestion) {
        write { try $0.ignore(host: suggestion.host) }
    }

    // MARK: - Refresh

    /// Fetches each feed whose next fetch time has come.
    public func refreshDue(now: Date = Date()) {
        refresh(feeds.filter { $0.nextFetch <= now })
    }

    /// Fetches each feed now, whatever its next fetch time.
    public func refreshAll() {
        refresh(feeds)
    }

    private func refresh(_ due: [Feed]) {
        let waiting = due.filter { !fetching.contains($0.id) }
        guard !waiting.isEmpty else { return }
        fetching.formUnion(waiting.map(\.id))
        let session = session
        Task {
            await withTaskGroup(of: (Feed, Swift.Result<FeedFetch.Result, Error>).self) { group in
                var queue = waiting[...]
                func next() {
                    guard let feed = queue.popFirst() else { return }
                    group.addTask {
                        do { return (feed, .success(try await FeedFetch.get(feed, session: session))) }
                        catch { return (feed, .failure(error)) }
                    }
                }
                for _ in 0..<Self.parallelFetches { next() }
                for await (feed, result) in group {
                    finish(feed, result)
                    next()
                }
            }
            write { try $0.prune(before: Date().addingTimeInterval(-Double(Self.keepDays) * 86_400)) }
        }
    }

    private func finish(_ old: Feed, _ result: Swift.Result<FeedFetch.Result, Error>) {
        fetching.remove(old.id)
        // The user can remove the feed during the fetch.
        guard var feed = feed(old.id) else { return }
        let now = Date()
        switch result {
        case .success(.notModified):
            feed.failures = 0
            feed.error = nil
            feed.nextFetch = FeedFetch.nextFetch(after: 0, now: now)
            write { try $0.save(feed) }
        case .success(.fetched(let parsed, let etag, let lastModified)):
            feed.failures = 0
            feed.error = nil
            feed.etag = etag
            feed.lastModified = lastModified
            feed.nextFetch = FeedFetch.nextFetch(after: 0, now: now)
            if feed.home == nil { feed.home = parsed.homePageURL }
            if feed.title == URL(string: feed.id)?.host || feed.title == feed.id,
               let title = parsed.title?.nilIfEmptyOrWhitespace {
                feed.title = title
            }
            let articles = FeedFetch.articles(of: parsed, feedID: feed.id, now: now)
            write { database in
                try database.save(feed)
                try database.insert(articles)
            }
        case .failure(let error):
            feed.failures += 1
            feed.error = error.localizedDescription
            feed.nextFetch = FeedFetch.nextFetch(after: feed.failures, now: now)
            write { try $0.save(feed) }
        }
    }

    // MARK: - Database

    private func write(_ change: (FeedDatabase) throws -> Void) {
        guard let database else { return }
        do {
            try change(database)
            loadError = nil
        } catch {
            loadError = error.localizedDescription
        }
        reload()
    }

    private func reload() {
        guard let database else { return }
        feeds = (try? database.feeds()) ?? []
        unreadCounts = (try? database.unreadCounts()) ?? [:]
        starredCount = (try? database.starredCount()) ?? 0
        suggestions = (try? database.suggestions()) ?? []
        revision += 1
    }
}
