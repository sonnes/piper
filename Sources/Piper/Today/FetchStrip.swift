import Feeds
import SwiftUI

/// The strip under the lenses of Today while the feeds are fetched: one icon
/// for each source, which lights up when its fetch ends, and a count. The
/// strip folds away a short time after the last fetch.
struct FetchStrip: View {
    let feeds: FeedStore
    let favicons: FaviconStore

    /// Changes when the time to fold the strip comes, so the body reads the clock again.
    @State private var tick = 0
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private var motion: Animation? { reduceMotion ? nil : .easeInOut(duration: Metrics.motionDuration) }

    /// The round to show: a round that runs, or one that ended less than `Metrics.foldDelay` ago.
    private var shown: FetchRound? {
        _ = tick
        guard let round = feeds.round else { return nil }
        guard let finished = round.finished else { return round }
        return Date().timeIntervalSince(finished) < Metrics.foldDelay ? round : nil
    }

    var body: some View {
        let shown = shown
        VStack(spacing: 0) {
            if let shown {
                content(shown)
                    .padding(Metrics.padding)
                    .transition(.opacity.combined(with: .move(edge: .top)))
            }
        }
        .clipped()
        .animation(motion, value: shown?.id)
        .task(id: feeds.round?.finished) {
            guard let finished = feeds.round?.finished else { return }
            let wait = Metrics.foldDelay - Date().timeIntervalSince(finished)
            if wait > 0 { try? await Task.sleep(for: .seconds(wait)) }
            if !Task.isCancelled { tick += 1 }
        }
    }

    private func content(_ round: FetchRound) -> some View {
        HStack(spacing: Metrics.spacing) {
            HStack(spacing: Metrics.iconSpacing) {
                ForEach(round.feeds.prefix(Metrics.iconLimit), id: \.self) { id in
                    icon(id, round: round)
                }
            }
            Text(label(round))
                .font(PiperTheme.paperUI(.body))
                .foregroundStyle(PiperTheme.paperFaint)
                .lineLimit(1)
                .contentTransition(.numericText())
                .animation(motion, value: round.ended.count)
            Spacer(minLength: 0)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(label(round))
    }

    private func icon(_ id: String, round: FetchRound) -> some View {
        let feed = feeds.feed(id)
        let ended = round.ended.contains(id)
        let failed = round.failed.contains(id)
        return FetchIcon(favicons: favicons, host: feed?.host ?? id, title: feed?.title ?? id,
                         busy: !ended && feeds.fetching.contains(id), ended: ended, failed: failed,
                         animates: !reduceMotion)
            .help(failed ? "\(feed?.title ?? id): \(feed?.error ?? "The fetch failed.")" : feed?.title ?? id)
            .animation(motion, value: ended)
    }

    /// "Fetching 6 sources", then "2 of 6", then "4 new · Kiln Works failed".
    private func label(_ round: FetchRound) -> String {
        let total = round.feeds.count
        guard round.isFinished else {
            return round.ended.isEmpty ? "Fetching \(total) \(total == 1 ? "source" : "sources")" : "\(round.ended.count) of \(total)"
        }
        let posts = round.newPosts == 0 ? "Nothing new" : "\(round.newPosts) new"
        switch round.failed.count {
        case 0: return posts
        case 1: return "\(posts) · \(round.failed.first.flatMap { feeds.feed($0)?.title } ?? "1 source") failed"
        case let count: return "\(posts) · \(count) failed"
        }
    }
}

/// The icon of one source in the strip: faint while it waits, bobbing while
/// it is fetched, and in full color when its fetch ends. A failed fetch is
/// gray with a red ring.
private struct FetchIcon: View {
    let favicons: FaviconStore
    let host: String
    let title: String
    let busy: Bool
    let ended: Bool
    let failed: Bool
    let animates: Bool

    @State private var up = false

    var body: some View {
        SiteIcon(favicons: favicons, host: host, title: title, side: FetchStrip.Metrics.iconSize)
            .saturation(ended && !failed ? 1 : 0)
            .opacity(ended ? 1 : busy ? FetchStrip.Metrics.busyOpacity : FetchStrip.Metrics.waitingOpacity)
            .overlay {
                if failed {
                    RoundedRectangle(cornerRadius: FetchStrip.Metrics.iconSize * SiteIcon.Metrics.tileCornerFraction)
                        .strokeBorder(PiperTheme.danger, lineWidth: FetchStrip.Metrics.failRing)
                }
            }
            .offset(y: up ? -FetchStrip.Metrics.bob : 0)
            .onChange(of: busy, initial: true) { _, busy in
                guard animates else { return }
                if busy {
                    withAnimation(.easeInOut(duration: FetchStrip.Metrics.bobDuration).repeatForever()) { up = true }
                } else {
                    withAnimation(.easeOut(duration: FetchStrip.Metrics.bobDuration)) { up = false }
                }
            }
    }
}

extension FetchStrip {
    enum Metrics {
        static let padding = EdgeInsets(top: 0, leading: 20, bottom: 8, trailing: 20)
        static let spacing: CGFloat = 10
        static let iconSize: CGFloat = 18
        static let iconSpacing: CGFloat = 4
        /// The most icons in the strip. The count in the label covers each source.
        static let iconLimit = 12
        static let waitingOpacity: Double = 0.25
        static let busyOpacity: Double = 0.6
        static let failRing: CGFloat = 1.5
        /// How far a busy icon rises, and the time of one rise.
        static let bob: CGFloat = 2
        static let bobDuration: Double = 0.5
        /// The time that the strip stays after the last fetch, in seconds.
        static let foldDelay: Double = 1.2
        static let motionDuration: Double = 0.3
    }
}
