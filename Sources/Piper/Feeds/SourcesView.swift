import AppKit
import Captures
import Feeds
import History
import PiperCore
import Stream
import SwiftUI
import UniformTypeIdentifiers

/// Sources: the place to add and manage feeds, on the Feeds tab.
///
/// It has a field that adds a feed from the address of a site or a feed, the
/// feeds with how often each one posts and how much of it the reader keeps,
/// one mode for each feed, OPML import, and the sites of browser history
/// that have a feed.
struct SourcesView: View {
    @Bindable var paper: FeedPaperModel
    @Bindable var model: AppModel

    @State private var address = ""
    @State private var found: [FeedDiscovery.Found] = []
    @State private var searching = false
    @State private var message: String?
    @State private var search: Task<Void, Never>?
    @FocusState private var addressFocused: Bool

    private var feeds: FeedStore { model.feeds }
    private var scan: SiteScan { model.siteScan }

    var body: some View {
        let stats = FeedStats.compute(feeds, notes: model.store.notes)
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                header
                addField
                if !found.isEmpty { foundRows }
                if let message {
                    Text(message).font(PiperTheme.paperUI(.body)).foregroundStyle(PiperTheme.paperMuted)
                        .fixedSize(horizontal: false, vertical: true)
                        .padding(.vertical, 6)
                }
                Text("Each source has one setting: how its posts reach Today.")
                    .font(PiperTheme.paperUI(.body)).foregroundStyle(PiperTheme.paperFaint)
                    .padding(.top, 12).padding(.bottom, 4)
                if feeds.feeds.isEmpty {
                    Text("No sources yet. Paste a site or feed address above, or import an OPML file.")
                        .font(PiperTheme.paperUI(.body)).foregroundStyle(PiperTheme.paperMuted)
                        .padding(.vertical, Metrics.sourceRowPadding)
                }
                ForEach(feeds.feeds) { feed in
                    SourceRow(feed: feed, stats: stats[feed.id], model: model) {
                        paper.pick(.feed(feed.id))
                    }
                }
                sites
            }
            .padding(.horizontal, PaperRowMetrics.rowPadding)
            .padding(.bottom, 16)
        }
        .onAppear {
            paper.listKeys = []
            scan.scanIfStale()
            take(paper.sourcesAddress)
        }
        .onChange(of: paper.sourcesAddress) { _, address in take(address) }
        .onChange(of: paper.addressRequest, initial: true) { _, request in
            guard request != nil else { return }
            paper.addressRequest = nil
            DispatchQueue.main.async { addressFocused = true }
        }
        .onDisappear { search?.cancel() }
    }

    // MARK: - Parts

    private var header: some View {
        HStack {
            Spacer()
            Menu("Import") {
                Button("Import from NetNewsWire") { importFile(OPMLImport.netNewsWireFile) }
                Button("Import OPML File…", action: chooseFile)
            }
            .menuStyle(.borderlessButton).fixedSize()
            .help("Import the feeds of an OPML file")
        }
        .padding(.vertical, 8)
    }

    private var addField: some View {
        HStack(spacing: 8) {
            Image(systemName: "plus").foregroundStyle(PiperTheme.paperFaint).accessibilityHidden(true)
            TextField("Paste a site or feed address", text: $address)
                .textFieldStyle(.plain)
                .font(PiperTheme.paperUI(.body))
                .focused($addressFocused)
                .onSubmit(find)
                .onChange(of: address) { _, _ in
                    found = []
                    message = nil
                }
                .accessibilityLabel("Site or feed address")
            if searching {
                ProgressView().controlSize(.small)
            } else if !address.trimmingCharacters(in: .whitespaces).isEmpty {
                Button("Find Feeds", action: find).buttonStyle(.borderless)
            }
        }
        .padding(.horizontal, 10)
        .frame(height: Metrics.fieldHeight)
        .background(PiperTheme.paperTint, in: Capsule())
    }

    private var foundRows: some View {
        VStack(alignment: .leading, spacing: 0) {
            ForEach(found) { result in
                let subscribed = feeds.feed(result.url) != nil
                HStack(spacing: 10) {
                    VStack(alignment: .leading, spacing: 1) {
                        Text(result.title ?? result.url).font(PiperTheme.paperUI(.body, weight: .semibold)).lineLimit(1)
                        Text(Self.detail(result)).font(PiperTheme.paperUI(.body)).foregroundStyle(PiperTheme.paperMuted)
                            .lineLimit(1).truncationMode(.middle)
                    }
                    Spacer(minLength: 8)
                    if subscribed {
                        Text("Added").font(PiperTheme.paperUI(.body)).foregroundStyle(PiperTheme.paperFaint)
                    } else {
                        Button("Add") { add(result) }.buttonStyle(.borderedProminent).controlSize(.small)
                    }
                }
                .padding(.vertical, 8)
            }
        }
        .padding(.top, 4)
    }

    /// The sites of recent history that have a feed and no subscription.
    @ViewBuilder private var sites: some View {
        let shown = Self.sites(feeds.suggestions, feeds: feeds.feeds)
        HStack {
            Text("Sites You Read Often").font(PiperTheme.paperUI(.body, weight: .semibold)).foregroundStyle(PiperTheme.paperMuted)
                .accessibilityAddTraits(.isHeader)
            Spacer()
            if scan.state == .scanning {
                ProgressView().controlSize(.small)
            } else {
                Button("Scan Again") { scan.scan() }.buttonStyle(.borderless).font(PiperTheme.paperUI(.body))
            }
        }
        .padding(.top, 20).padding(.bottom, 4)
        if case .failed(let reason) = scan.state, shown.isEmpty {
            Text(reason).font(PiperTheme.paperUI(.body)).foregroundStyle(PiperTheme.paperMuted)
                .fixedSize(horizontal: false, vertical: true)
            Button("Open Settings") { model.openSettings?() }.buttonStyle(.borderless).padding(.top, 4)
        } else if shown.isEmpty {
            Text(scan.state == .scanning ? "Reading the history of this Mac…" : "No other sites of your history have a feed.")
                .font(PiperTheme.paperUI(.body)).foregroundStyle(PiperTheme.paperMuted)
        }
        ForEach(shown) { site in
            HStack(spacing: 10) {
                SiteIcon(favicons: model.favicons, host: site.host, title: site.title ?? site.host,
                         side: Metrics.sourceIcon)
                VStack(alignment: .leading, spacing: 1) {
                    Text(site.title ?? site.host).font(PiperTheme.paperUI(.body, weight: .semibold)).lineLimit(1)
                    Text("\(site.host) · \(site.visits) \(site.visits == 1 ? "visit" : "visits") · has a feed")
                        .font(PiperTheme.paperUI(.body)).foregroundStyle(PiperTheme.paperMuted).lineLimit(1)
                }
                Spacer(minLength: 8)
                Button("Add") { subscribe(site) }.buttonStyle(.borderedProminent).controlSize(.small)
                    .accessibilityLabel("Add \(site.title ?? site.host)")
                Button("Ignore") { feeds.ignore(site) }.buttonStyle(.borderless)
                    .foregroundStyle(PiperTheme.paperMuted)
                    .accessibilityLabel("Ignore \(site.host)")
            }
            .padding(.vertical, Metrics.sourceRowPadding)
        }
    }

    // MARK: - Text

    /// "2 posts a week · you keep 70%", or a month rate for a quiet feed.
    static func rate(_ stats: FeedStats?) -> String {
        guard let stats, stats.postsPerWeek > 0 else { return "No posts in \(FeedStats.days / 7) weeks" }
        let posts: String
        if stats.postsPerWeek >= 1 {
            let count = Int(stats.postsPerWeek.rounded())
            posts = "\(count) \(count == 1 ? "post" : "posts") a week"
        } else {
            let count = max(1, Int((stats.postsPerWeek * 30 / 7).rounded()))
            posts = "\(count) \(count == 1 ? "post" : "posts") a month"
        }
        return posts + " · you keep \(Int((stats.keepRate * 100).rounded()))%"
    }

    /// The sites of history with a feed that the reader did not add or
    /// ignore, most visited first.
    static func sites(_ suggestions: [Suggestion], feeds: [Feed], limit: Int = Metrics.siteLimit) -> [Suggestion] {
        let subscribed = Set(feeds.map(\.id))
        let hosts = Set(feeds.map(\.host))
        return suggestions
            .filter { !$0.ignored && $0.feedURL.map { !subscribed.contains($0) } == true && !hosts.contains(Site(host: $0.host).key) }
            .sorted { $0.score > $1.score }
            .prefix(limit)
            .map { $0 }
    }

    private static func detail(_ result: FeedDiscovery.Found) -> String {
        [result.url, result.format, result.articles.map { "\($0) posts" }].compactMap { $0 }.joined(separator: " · ")
    }

    // MARK: - Actions

    /// Puts an address from a paste in the field and looks it up.
    private func take(_ pasted: String?) {
        guard let pasted else { return }
        paper.sourcesAddress = nil
        address = pasted
        DispatchQueue.main.async(execute: find)
    }

    private func find() {
        let text = address.trimmingCharacters(in: .whitespaces)
        guard !text.isEmpty, !searching else { return }
        searching = true
        message = nil
        search = Task {
            do {
                let results = try await FeedDiscovery.find(text)
                guard !Task.isCancelled else { return }
                found = results
                if results.isEmpty { message = "Piper found no feed at this address." }
            } catch {
                message = error.localizedDescription
            }
            searching = false
        }
    }

    private func add(_ result: FeedDiscovery.Found) {
        feeds.subscribe(url: result.url, title: result.title)
        address = ""
    }

    private func subscribe(_ site: Suggestion) {
        guard let url = site.feedURL else { return }
        feeds.subscribe(url: url, title: site.title, home: "https://" + site.host)
    }

    private func chooseFile() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [UTType(filenameExtension: "opml") ?? .xml, .xml]
        panel.allowsMultipleSelection = false
        guard panel.runModal() == .OK, let url = panel.url else { return }
        importFile(url)
    }

    private func importFile(_ url: URL) {
        do {
            let added = feeds.subscribe(try OPMLImport.feeds(in: url))
            message = added == 0 ? "Piper already has every feed of \(url.lastPathComponent)."
                : "Added \(added) \(added == 1 ? "feed" : "feeds") from \(url.lastPathComponent)."
        } catch {
            message = error.localizedDescription
        }
    }
}

extension SourcesView {
    enum Metrics {
        /// The height of the address field.
        static let fieldHeight: CGFloat = 30
        /// The number of sites that Sites You Read Often shows.
        static let siteLimit = 8
        static let sourceIcon: CGFloat = 22
        static let sourceRowPadding: CGFloat = 10
    }
}

/// One feed on Sources: its icon, its title, its rate, and its mode.
private struct SourceRow: View {
    let feed: Feed
    let stats: FeedStats?
    let model: AppModel
    let open: () -> Void

    var body: some View {
        // The mode goes under the title when the paper is too narrow for both.
        ViewThatFits(in: .horizontal) {
            HStack(spacing: 10) {
                icon
                title
                mode
            }
            HStack(alignment: .top, spacing: 10) {
                icon
                VStack(alignment: .leading, spacing: 6) {
                    title
                    mode
                }
            }
        }
        .padding(.vertical, SourcesView.Metrics.sourceRowPadding)
        .overlay(alignment: .bottom) { Rule() }
        .contextMenu {
            Button("Show Posts", action: open)
            if let home = feed.home.flatMap(URL.init(string:)) {
                Button("Open Site in Browser") { NSWorkspace.shared.open(home) }
            }
            Button("Copy Feed Address") { Clipboard.copy(feed.id) }
            Divider()
            Button("Remove Source", role: .destructive) { model.feeds.unsubscribe(feed.id) }
        }
    }

    private var icon: some View {
        SiteIcon(favicons: model.favicons, host: feed.host, title: feed.title, side: SourcesView.Metrics.sourceIcon)
    }

    private var title: some View {
        Button(action: open) {
            VStack(alignment: .leading, spacing: 1) {
                Text(feed.title).font(PiperTheme.paperUI(.row, weight: .semibold)).foregroundStyle(PiperTheme.paperInk)
                    .lineLimit(1)
                Text(SourcesView.rate(stats)).font(PiperTheme.paperUI(.body)).foregroundStyle(PiperTheme.paperMuted)
                    .monospacedDigit().lineLimit(1)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .help("Show the posts of \(feed.title)")
    }

    private var mode: some View {
        SegmentedCapsule(values: FeedMode.allCases, selection: feed.mode, title: \.title,
                         help: { "Show \($0.title.lowercased()) of \(feed.title) in Today" }, fills: false) {
            model.feeds.setMode($0, of: feed.id)
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel("How \(feed.title) reaches Today")
    }
}
