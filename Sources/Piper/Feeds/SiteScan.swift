import Feeds
import Foundation
import History
import Observation

/// Finds the sites of recent browser history and the feed of each one, for
/// Sites You Read Often on Sources.
///
/// History stays on the Mac. The scan sends one request to the home page of
/// each site, and a few more to confirm the feeds that the page names.
@MainActor
@Observable
final class SiteScan {

    enum State: Equatable {
        case idle
        case scanning
        case failed(String)
    }

    // MARK: - Properties

    /// Sources scans the history again when it opens, if the last scan is older than this.
    static let scanInterval: TimeInterval = 86_400
    /// The number of sites that the scan reads at the same time.
    nonisolated static let parallelScans = 4

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
    @ObservationIgnored private let messages: Messages
    @ObservationIgnored private let preferences: UserDefaults

    // MARK: - Initialization

    init(feeds: FeedStore, messages: Messages, preferences: UserDefaults) {
        self.feeds = feeds
        self.messages = messages
        self.preferences = preferences
        blockedSites = preferences.stringArray(forKey: AppDefaults.Key.blockedSites) ?? BlockedSites.defaults
        disabledSources = Set(preferences.stringArray(forKey: AppDefaults.Key.disabledHistorySources) ?? [])
        lastScan = preferences.object(forKey: AppDefaults.Key.siteScanDate) as? Date
    }

    // MARK: - Scanning

    func refreshSources() {
        Task {
            sources = await Task.detached { BrowserCatalog.sources() }.value
        }
    }

    /// Scans if the last scan is older than one day. Sources calls it when it opens.
    func scanIfStale(now: Date = Date()) {
        guard let lastScan else { return scan() }
        if now.timeIntervalSince(lastScan) > Self.scanInterval { scan() }
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
            let (digest, errors) = await Self.digest(enabled, blocked: blocked)
            errors.forEach(messages.report)
            guard !digest.sites.isEmpty else {
                state = .failed(enabled.isEmpty ? "Piper can read no browser history. Open Settings > Feeds to choose the sources."
                                : "Piper found no sites in the last \(HistoryDigest.days) days of history.")
                return
            }
            feeds.replaceSuggestions(await Self.suggestions(for: digest.sites))
            let now = Date()
            lastScan = now
            preferences.set(now, forKey: AppDefaults.Key.siteScanDate)
            state = .idle
        }
    }

    // MARK: - Parts

    /// The digest of the sources that Piper can read, and the error of each source that it cannot.
    private nonisolated static func digest(_ sources: [HistorySource], blocked: [String]) async -> (HistoryDigest, [Error]) {
        await Task.detached {
            let now = Date()
            let since = now.addingTimeInterval(-Double(HistoryDigest.days) * 86_400)
            var visits: [Visit] = []
            var errors: [Error] = []
            for source in sources {
                do { visits += try HistoryReader.read(source, since: since) } catch { errors.append(error) }
            }
            return (HistoryDigest(visits: visits, blocked: blocked, now: now), errors)
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
            for _ in 0..<Self.parallelScans { next() }
            for await suggestion in group {
                results.append(suggestion)
                next()
            }
            return results
        }
    }
}
