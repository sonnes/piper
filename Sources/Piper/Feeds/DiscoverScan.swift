import Feeds
import Foundation
import History
import Observation

/// Finds the sites of recent browser history and the feed of each one, for Discover.
///
/// History stays on the Mac. The scan sends one request to the home page of
/// each site, and a few more to confirm the feeds that the page names.
@MainActor
@Observable
final class DiscoverScan {

    enum State: Equatable {
        case idle
        case scanning
        case failed(String)
    }

    // MARK: - Properties

    private(set) var state = State.idle
    private(set) var sources: [HistorySource] = []
    private(set) var lastScan: Date?

    var blockedSites: [String] {
        didSet { preferences.set(blockedSites, forKey: AppDefaults.Key.blockedSites) }
    }
    var disabledSources: Set<String> {
        didSet { preferences.set(disabledSources.sorted(), forKey: AppDefaults.Key.disabledHistorySources) }
    }

    @ObservationIgnored private let feeds: FeedStore
    @ObservationIgnored private let preferences: UserDefaults

    // MARK: - Initialization

    init(feeds: FeedStore, preferences: UserDefaults) {
        self.feeds = feeds
        self.preferences = preferences
        blockedSites = preferences.stringArray(forKey: AppDefaults.Key.blockedSites) ?? BlockedSites.defaults
        disabledSources = Set(preferences.stringArray(forKey: AppDefaults.Key.disabledHistorySources) ?? [])
        lastScan = preferences.object(forKey: AppDefaults.Key.discoverLastScan) as? Date
    }

    // MARK: - Scanning

    func refreshSources() {
        Task {
            sources = await Task.detached { BrowserCatalog.sources() }.value
        }
    }

    /// Scans if the last scan is older than one day. Discover calls it when it opens.
    func scanIfStale(now: Date = Date()) {
        guard let lastScan else { return scan() }
        if now.timeIntervalSince(lastScan) > AppDefaults.Feeds.discoverInterval { scan() }
    }

    func scan() {
        guard state != .scanning else { return }
        state = .scanning
        let blocked = blockedSites
        let disabled = disabledSources
        Task {
            let found = await Task.detached { BrowserCatalog.sources() }.value
            sources = found
            let enabled = found.filter { !disabled.contains($0.id) && !$0.needsAccess }
            let digest = await Self.digest(enabled, blocked: blocked)
            guard !digest.sites.isEmpty else {
                state = .failed(enabled.isEmpty ? "Piper can read no browser history. Open Settings > Feeds to choose the sources."
                                : "Piper found no sites in the last \(HistoryDigest.days) days of history.")
                return
            }
            feeds.replaceSuggestions(await Self.suggestions(for: digest.sites))
            let now = Date()
            lastScan = now
            preferences.set(now, forKey: AppDefaults.Key.discoverLastScan)
            state = .idle
        }
    }

    func block(_ host: String) {
        blockedSites = BlockedSites.normalized(blockedSites + [host])
    }

    // MARK: - Parts

    private nonisolated static func digest(_ sources: [HistorySource], blocked: [String]) async -> HistoryDigest {
        await Task.detached {
            let now = Date()
            let since = now.addingTimeInterval(-Double(HistoryDigest.days) * 86_400)
            let visits = sources.flatMap { (try? HistoryReader.read($0, since: since)) ?? [] }
            return HistoryDigest(visits: visits, blocked: blocked, now: now)
        }.value
    }

    /// Looks for a feed on the home page of each site, a few sites at a time.
    private nonisolated static func suggestions(for sites: [DigestSite]) async -> [Suggestion] {
        await withTaskGroup(of: Suggestion.self) { group in
            var queue = sites[...]
            var results: [Suggestion] = []
            func next() {
                guard let site = queue.popFirst() else { return }
                group.addTask {
                    let feed = (try? await FeedDiscovery.find("https://" + site.host))?.first
                    return Suggestion(host: site.host, feedURL: feed?.url, title: feed?.title,
                                      visits: site.visits, score: site.score)
                }
            }
            for _ in 0..<AppDefaults.Feeds.discoverParallelSites { next() }
            for await suggestion in group {
                results.append(suggestion)
                next()
            }
            return results
        }
    }
}
