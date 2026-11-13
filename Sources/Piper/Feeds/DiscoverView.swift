import AppKit
import Feeds
import History
import SwiftUI

/// The sites of recent browser history, with Subscribe for each site that has a
/// feed. The sites with no feed sit in a folded section at the end.
struct DiscoverView: View {
    @Bindable var model: AppModel

    @State private var showsNoFeed = false

    private var feeds: FeedStore { model.feeds }
    private var scan: DiscoverScan { model.discover }
    private var open: [Suggestion] { feeds.suggestions.filter { !$0.ignored } }
    private var withFeed: [Suggestion] { open.filter { $0.feedURL.map { feeds.feed($0) == nil } ?? false } }
    private var noFeed: [Suggestion] { open.filter { $0.feedURL == nil } }

    var body: some View {
        VStack(spacing: 0) {
            header
            Rule()
            if case .failed(let reason) = scan.state, open.isEmpty {
                VStack(spacing: 12) {
                    EmptyPane(title: "Nothing to Discover", detail: reason)
                    Button("Open Settings") { model.openSettings?() }
                }
            } else if open.isEmpty {
                EmptyPane(title: scan.state == .scanning ? "Reading History…" : "Nothing to Discover",
                          detail: scan.state == .scanning ? nil : "Every site of your recent history has an answer.")
            } else {
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: AppDefaults.Feeds.discoverRowSpacing) {
                        ForEach(Array(withFeed.enumerated()), id: \.element.id) { index, suggestion in
                            SuggestionRow(suggestion: suggestion, index: index,
                                          subscribe: { subscribe(suggestion) },
                                          ignore: { feeds.ignore(suggestion) })
                        }
                        if withFeed.isEmpty {
                            Text("No new feeds. Each site with a feed has a subscription or an answer.")
                                .font(PiperTheme.ui(.secondary)).foregroundStyle(PiperTheme.secondary)
                                .padding(12)
                        }
                        if !noFeed.isEmpty {
                            Button { showsNoFeed.toggle() } label: {
                                HStack(spacing: 6) {
                                    Image(systemName: showsNoFeed ? "chevron.down" : "chevron.right")
                                    Text("\(noFeed.count) \(noFeed.count == 1 ? "Site" : "Sites") with No Feed")
                                }
                                .font(PiperTheme.ui(.caption, weight: .semibold))
                                .foregroundStyle(PiperTheme.secondary)
                                .contentShape(Rectangle())
                            }
                            .buttonStyle(.plain)
                            .padding(.horizontal, 12)
                            .padding(.top, 16)
                            .padding(.bottom, 4)
                            if showsNoFeed {
                                ForEach(Array(noFeed.enumerated()), id: \.element.id) { index, suggestion in
                                    SuggestionRow(suggestion: suggestion, index: withFeed.count + index,
                                                  subscribe: nil, ignore: { feeds.ignore(suggestion) })
                                }
                            }
                        }
                    }
                    .padding(8)
                }
            }
        }
        .background(PiperTheme.page)
        .onAppear { scan.scanIfStale() }
    }

    private var header: some View {
        HStack(spacing: 8) {
            Text("Discover").font(PiperTheme.ui(.body, weight: .semibold))
            Text(subtitle).font(PiperTheme.ui(.secondary)).foregroundStyle(PiperTheme.secondary).lineLimit(1)
            Spacer(minLength: 8)
            if scan.state == .scanning {
                ProgressView().controlSize(.small)
            } else {
                Button("Scan Again") { scan.scan() }.buttonStyle(.text)
            }
        }
        .padding(.horizontal, 16)
        .frame(height: AppDefaults.Feeds.headerHeight)
    }

    private var subtitle: String {
        if scan.state == .scanning { return "Looking for feeds on the sites of your history…" }
        let count = withFeed.count
        return "From \(HistoryDigest.days) days of history · \(count) \(count == 1 ? "site" : "sites") with a feed"
    }

    private func subscribe(_ suggestion: Suggestion) {
        guard let url = suggestion.feedURL else { return }
        feeds.subscribe(url: url, title: suggestion.title, home: "https://" + suggestion.host)
    }
}

/// One site of Discover: its feed or its host, its visits, and its actions.
private struct SuggestionRow: View {
    let suggestion: Suggestion
    let index: Int
    /// Nil for a site with no feed. The row then offers Open.
    let subscribe: (() -> Void)?
    let ignore: () -> Void

    @State private var hovered = false

    private var title: String { suggestion.title ?? suggestion.host }

    var body: some View {
        HStack(spacing: 10) {
            Text(SidebarOutline.monogram(title))
                .font(PiperTheme.ui(.caption, weight: .bold))
                .foregroundStyle(PiperTheme.onAccent)
                .frame(width: AppDefaults.Sidebar.imageSize, height: AppDefaults.Sidebar.imageSize)
                .background(Color(nsColor: SidebarOutline.tagColor(at: index)),
                            in: RoundedRectangle(cornerRadius: AppDefaults.Sidebar.imageSize * AppDefaults.Sidebar.tileCornerFraction))
                .opacity(subscribe == nil ? 0.5 : 1)
            VStack(alignment: .leading, spacing: 1) {
                Text(title).font(PiperTheme.ui(.body, weight: subscribe == nil ? .regular : .semibold)).lineLimit(1)
                Text("\(suggestion.host) · \(suggestion.visits) \(suggestion.visits == 1 ? "visit" : "visits")")
                    .font(PiperTheme.ui(.caption)).foregroundStyle(PiperTheme.secondary).lineLimit(1)
            }
            Spacer(minLength: 8)
            if let subscribe {
                Button("Subscribe", action: subscribe)
                    .buttonStyle(.borderedProminent).controlSize(.small)
            } else {
                Button("Open") {
                    if let url = URL(string: "https://" + suggestion.host) { NSWorkspace.shared.open(url) }
                }
                .buttonStyle(.text)
            }
            Button("Ignore", action: ignore).buttonStyle(.text)
                .foregroundStyle(PiperTheme.secondary)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
        .background(hovered ? PiperTheme.hover : .clear, in: RoundedRectangle(cornerRadius: AppDefaults.InboxRow.cornerRadius))
        .onHover { hovered = $0 }
    }
}
