import Foundation
import Observation
import PiperCore

/// The subscriptions, for Today, the Sources paper, and the list of a feed.
/// It owns the database and the refresh of each feed.
///
/// The database calls run on the main thread. A fetch and its parse run in a
/// detached task, and the result comes back to the main thread. Each database
/// error goes to `report`. A read that fails then gives an empty value.
@MainActor @Observable
public final class FeedStore {

    // MARK: - Properties

    /// Piper removes a read article after this many days. A kept article
    /// lives on as a link capture.
    nonisolated public static let keepDays = 30
    static let parallelFetches = 4

    public private(set) var feeds: [Feed] = []
    public private(set) var suggestions: [Suggestion] = []
    /// The IDs of the feeds that a fetch holds now.
    public private(set) var fetching: Set<String> = []
    /// Changes on each write, so a list of articles can read the database again.
    public private(set) var revision = 0

    @ObservationIgnored private let database: FeedDatabase?
    @ObservationIgnored private let report: @MainActor (Error) -> Void
    @ObservationIgnored private let session: URLSession
    @ObservationIgnored private var timer: Timer?

    // MARK: - Initialization

    /// - Parameter report: Takes each database error.
    public init(url: URL? = nil, session: URLSession = .shared, report: @escaping @MainActor (Error) -> Void) {
        let location = url ?? DataFolder.url.appendingPathComponent("Feeds.sqlite")
        self.session = session
        self.report = report
        do {
            database = try FeedDatabase(url: location)
        } catch {
            database = nil
            report(error)
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

    /// Sets how the posts of the feed reach Today.
    public func setMode(_ mode: FeedMode, of id: String) {
        guard var feed = feed(id), feed.mode != mode else { return }
        feed.mode = mode
        write { try $0.save(feed) }
    }

    // MARK: - Articles

    /// The articles of a filter. See `FeedDatabase.articles`.
    public func articles(_ filter: FeedFilter, keeping: Set<String> = []) -> [Article] {
        read([]) { try $0.articles(filter, keeping: keeping) }
    }

    /// The article with the ID, with its current marks.
    public func article(_ id: String) -> Article? {
        read(nil) { try $0.article(id) }
    }

    public func setRead(_ read: Bool, ids: [String]) {
        guard !ids.isEmpty else { return }
        write { try $0.setRead(read, ids: ids) }
    }

    /// The count of articles of each feed in the days before now, by feed ID.
    public func articleCounts(days: Int, now: Date = Date()) -> [String: Int] {
        read([:]) { try $0.articleCounts(since: now.addingTimeInterval(-Double(days) * 86_400)) }
    }

    /// The count of unread articles of each feed, by feed ID. A view that
    /// reads it shows the new count after each write.
    public func unreadCounts() -> [String: Int] {
        _ = revision
        return read([:]) { try $0.unreadCounts() }
    }

    /// Marks as read each article that the filter shows.
    public func markAllRead(_ filter: FeedFilter) {
        setRead(true, ids: articles(filter).filter { !$0.read }.map(\.id))
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

    /// Runs a read. A store whose database did not open reads nothing, and
    /// it reported that error when it opened.
    private func read<Value>(_ empty: Value, _ query: (FeedDatabase) throws -> Value) -> Value {
        guard let database else { return empty }
        do {
            return try query(database)
        } catch {
            report(error)
            return empty
        }
    }

    private func write(_ change: (FeedDatabase) throws -> Void) {
        guard let database else { return }
        do { try change(database) } catch { report(error) }
        reload()
    }

    private func reload() {
        feeds = read([]) { try $0.feeds() }
        suggestions = read([]) { try $0.suggestions() }
        revision += 1
    }
}
