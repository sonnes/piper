import Agents
import Briefs
import Foundation
import Observation

/// Builds the daily brief and holds the picks that Inbox shows.
///
/// The agent has no tools. Piper reads each source, loads each page, and ranks
/// each link, so the agent can only pick hosts and numbers from lists.
@MainActor
@Observable
final class BriefBuilder {

    enum State: Equatable {
        case idle
        case scanning
        case choosing
        case reading([String])
        case picking
        case failed(String)

        var isBuilding: Bool {
            switch self {
            case .idle, .failed: return false
            default: return true
            }
        }
    }

    // MARK: - Properties

    private(set) var state = State.idle
    /// The newest brief. Its open picks show in Inbox until the next build.
    private(set) var day: BriefDay?
    private(set) var sources: [BriefSource] = []
    /// True after the first brief, until the user answers about morning builds.
    private(set) var asksAboutMorning = false

    var openPicks: [BriefPick] { day?.openPicks ?? [] }

    var blockedSites: [String] {
        didSet { preferences.set(blockedSites, forKey: AppDefaults.Key.briefBlockedSites) }
    }
    var disabledSources: Set<String> {
        didSet { preferences.set(disabledSources.sorted(), forKey: AppDefaults.Key.briefDisabledSources) }
    }
    var morningBuilds: Bool {
        didSet { preferences.set(morningBuilds, forKey: AppDefaults.Key.briefMorning) }
    }

    @ObservationIgnored private let agents: FolderAgents
    @ObservationIgnored private let preferences: UserDefaults
    @ObservationIgnored private let store: BriefStore
    @ObservationIgnored private let sessionFolder: URL
    @ObservationIgnored private var schedule: Timer?

    // MARK: - Initialization

    init(agents: FolderAgents, preferences: UserDefaults) {
        self.agents = agents
        self.preferences = preferences
        let support = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("Piper")
        store = BriefStore(folder: support.appendingPathComponent("Briefs"))
        sessionFolder = support.appendingPathComponent("BriefSession")
        blockedSites = preferences.stringArray(forKey: AppDefaults.Key.briefBlockedSites) ?? BlockedSites.defaults
        disabledSources = Set(preferences.stringArray(forKey: AppDefaults.Key.briefDisabledSources) ?? [])
        morningBuilds = preferences.bool(forKey: AppDefaults.Key.briefMorning)
        day = store.latest()
    }

    // MARK: - Reading

    /// Records what the reader did with a pick. The pick leaves Inbox.
    func set(_ state: BriefPick.State, of pick: BriefPick) {
        guard let id = day?.id else { return }
        do {
            if let changed = try store.set(state, of: pick.url, in: id) { day = changed }
        } catch {
            self.state = .failed(error.localizedDescription)
        }
    }

    func refreshSources() {
        Task {
            sources = await Task.detached { BrowserCatalog.sources() }.value
        }
    }

    /// The digest that the next build sends.
    func preview() async -> HistoryDigest {
        await Self.scan(enabledSources(), blocked: blockedSites).digest
    }

    func block(_ host: String) {
        blockedSites = BlockedSites.normalized(blockedSites + [host])
    }

    func answerMorning(_ accepted: Bool) {
        morningBuilds = accepted
        asksAboutMorning = false
        preferences.set(true, forKey: AppDefaults.Key.briefMorningAsked)
    }

    // MARK: - Schedule

    func startSchedule() {
        checkSchedule()
        schedule = Timer.scheduledTimer(withTimeInterval: AppDefaults.Brief.scheduleInterval, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.checkSchedule() }
        }
    }

    private func checkSchedule() {
        let lastTry = preferences.object(forKey: AppDefaults.Key.briefLastTry) as? Date
        guard !state.isBuilding, BriefSchedule.isDue(now: Date(), lastTry: lastTry, enabled: morningBuilds) else { return }
        build()
    }

    // MARK: - Building

    func build() {
        guard !state.isBuilding else { return }
        preferences.set(Date(), forKey: AppDefaults.Key.briefLastTry)
        Task {
            do {
                try await runBuild()
                state = .idle
                if !preferences.bool(forKey: AppDefaults.Key.briefMorningAsked) { asksAboutMorning = true }
            } catch {
                state = .failed(error.localizedDescription)
            }
        }
    }

    private func runBuild() async throws {
        state = .scanning
        let now = Date()
        let blocked = blockedSites
        let lastBuilt = preferences.object(forKey: AppDefaults.Key.briefLastBuilt) as? Date
        let feedsSince = lastBuilt ?? now.addingTimeInterval(-Double(AppDefaults.Brief.firstFeedDays) * 86_400)
        let scan = await Self.scan(enabledSources(), blocked: blocked, feedsSince: feedsSince)
        let seen = store.linksBefore(now)
        let articles = scan.articles.filter { !BriefLinks.isSeen($0.url, in: seen) }
        var stories: [HackerNewsStory] = []
        var failed: [String] = []
        if !disabledSources.contains(HackerNews.sourceID) {
            do { stories = try await HackerNews.fetch(now: now, blocked: blocked, seen: seen) }
            catch { failed.append(HackerNews.name) }
        }
        guard !scan.digest.sites.isEmpty || !articles.isEmpty || !stories.isEmpty else {
            throw BriefFailure("Piper found no history, feed articles, or Hacker News stories to use.")
        }

        try FileManager.default.createDirectory(at: sessionFolder, withIntermediateDirectories: true)
        let session = agents.runner.newSession(in: sessionFolder.path, purpose: .brief)
        agents.runner.setModel(AppDefaults.Brief.model, for: session)
        defer { agents.runner.delete(session) }

        var hosts: [String] = []
        var pages: [LoadedPage] = []
        if !scan.digest.sites.isEmpty {
            state = .choosing
            let answer = try await turn(BriefPrompts.chooseSites(scan.digest), in: session)
            hosts = BriefPrompts.hosts(in: answer, digest: scan.digest)
            state = .reading(hosts)
            pages = await BriefPageLoader().load(hosts, blocked: blocked).map { $0.removingLinks(in: seen) }
        }
        failed += hosts.filter { host in !pages.contains { $0.host == host } }

        state = .picking
        let candidates = BriefRanking.rank(stories: stories, articles: articles, pages: pages, digest: scan.digest,
                                           blocked: blocked, previousBuild: lastBuilt, now: now)
        guard !candidates.isEmpty else { throw BriefFailure("Piper found no new links to pick from.") }
        let date = now.formatted(date: .complete, time: .omitted)
        let answer = try await turn(BriefPrompts.choosePicks(date: date, candidates: candidates, digest: scan.digest,
                                                             articles: articles, stories: stories), in: session)
        let picks = BriefPrompts.picks(in: answer, candidates: candidates)
        guard !picks.isEmpty else { throw BriefFailure("The agent picked no links.") }

        var feeds: [String] = []
        for article in articles where !feeds.contains(article.feed) { feeds.append(article.feed) }
        if !stories.isEmpty { feeds.append(HackerNews.name) }
        let built = BriefDay(id: BriefStore.id(for: now), builtAt: now, picks: picks,
                             sites: pages.map(\.host), feeds: feeds, failed: failed)
        try store.save(built)
        preferences.set(now, forKey: AppDefaults.Key.briefLastBuilt)
        day = built
    }

    /// Sends one message and waits for the result of its turn. The runner stops a turn after its time limit.
    private func turn(_ text: String, in session: AgentSession) async throws -> String {
        agents.runner.send(text, to: session)
        guard let start = session.blocks.lastIndex(where: { if case .user = $0 { return true } else { return false } }) else {
            throw BriefFailure("The agent did not start.")
        }
        while true {
            let blocks = session.blocks[(start + 1)...]
            if case .result(_, let result)? = blocks.last(where: { if case .result = $0 { return true } else { return false } }) {
                if let failure = result.failure { throw BriefFailure(failure) }
                let messages = blocks.compactMap { block -> String? in
                    if case .assistant(_, let text) = block { return text } else { return nil }
                }
                return result.text.isEmpty ? messages.joined(separator: "\n\n") : result.text
            }
            try await Task.sleep(for: .milliseconds(200))
        }
    }

    private func enabledSources() -> [BriefSource] {
        BrowserCatalog.sources().filter { !$0.needsAccess && !disabledSources.contains($0.id) }
    }

    // MARK: - Scanning

    private struct Scan: Sendable {
        let digest: HistoryDigest
        let articles: [FeedArticle]
    }

    /// Reads each source away from the main thread. A source that fails does not stop the others.
    private nonisolated static func scan(_ sources: [BriefSource], blocked: [String], feedsSince: Date? = nil) async -> Scan {
        await Task.detached {
            let now = Date()
            let since = now.addingTimeInterval(-Double(HistoryDigest.days) * 86_400)
            let visits = sources.flatMap { (try? HistoryReader.read($0, since: since)) ?? [] }
            let articles = feedsSince.map { date in
                sources.filter { $0.format == .netNewsWire }
                    .flatMap { (try? NetNewsWireReader.read($0, since: date, blocked: blocked)) ?? [] }
            } ?? []
            return Scan(digest: HistoryDigest(visits: visits, blocked: blocked, now: now),
                        articles: Array(articles.prefix(NetNewsWireReader.articleLimit)))
        }.value
    }
}

private struct BriefFailure: LocalizedError {
    let message: String
    init(_ message: String) { self.message = message }
    var errorDescription: String? { message }
}
