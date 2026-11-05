import Briefs
import SwiftUI

/// The picks of the newest brief, at the top of Inbox in the main window and
/// in the capture panel. The group also shows the state of a build.
///
/// A click on a pick saves its link to Inbox and opens it in the Web tab. Keep
/// saves the link only. Skip and the circle remove the pick from the group.
struct BriefGroup: View {
    let model: AppModel

    @State private var folded = false

    private var brief: BriefBuilder { model.brief }
    private var picks: [BriefPick] { brief.openPicks }
    private var builtToday: Bool { Self.builtToday(brief) }

    /// True when the group has a state, a question, a pick, or a Build Brief button to show.
    static func shows(_ brief: BriefBuilder) -> Bool {
        brief.state != .idle || brief.asksAboutMorning || !brief.openPicks.isEmpty || !builtToday(brief)
    }

    private static func builtToday(_ brief: BriefBuilder) -> Bool {
        brief.day?.id == BriefStore.id(for: Date())
    }

    var body: some View {
        if Self.shows(brief) {
            VStack(alignment: .leading, spacing: 0) {
                header
                if !folded {
                    ForEach(picks) { pick in
                        BriefPickRow(pick: pick,
                                     open: { open(pick) },
                                     keep: { keep(pick) },
                                     skip: { brief.set(.skipped, of: pick) },
                                     markRead: { brief.set(.read, of: pick) })
                    }
                }
                if brief.asksAboutMorning { morningQuestion }
            }
            .padding(.vertical, 4)
            .background(PiperTheme.accent.opacity(0.05), in: RoundedRectangle(cornerRadius: 10))
            .overlay(RoundedRectangle(cornerRadius: 10).strokeBorder(PiperTheme.accent.opacity(0.14), lineWidth: 1))
            .padding(.vertical, 6)
        }
    }

    // MARK: - Parts

    private var header: some View {
        HStack(spacing: 6) {
            Image(systemName: "sun.max").foregroundStyle(PiperTheme.accent)
            switch brief.state {
            case .idle:
                Text(picks.isEmpty ? "Brief" : "Brief · \(picks.count) \(picks.count == 1 ? "pick" : "picks")")
                    .font(PiperTheme.ui(12, weight: .semibold)).foregroundStyle(PiperTheme.accent)
                Spacer(minLength: 8)
                if !builtToday {
                    Button("Build Brief") { brief.build() }.buttonStyle(.text)
                }
                if !picks.isEmpty {
                    Button { folded.toggle() } label: {
                        Image(systemName: folded ? "chevron.right" : "chevron.down")
                    }
                    .buttonStyle(.plain).foregroundStyle(PiperTheme.secondary)
                    .accessibilityLabel(folded ? "Show Picks" : "Hide Picks")
                }
            case .failed(let message):
                Text("The brief was not built. \(message)")
                    .font(PiperTheme.ui(12)).foregroundStyle(PiperTheme.danger).lineLimit(2)
                Spacer(minLength: 8)
                Button("Try Again") { brief.build() }.buttonStyle(.text)
            default:
                ProgressView().controlSize(.small)
                Text(progress).font(PiperTheme.ui(12)).foregroundStyle(PiperTheme.secondary).lineLimit(1)
                Spacer(minLength: 0)
            }
        }
        .padding(.horizontal, AppDefaults.CaptureItem.horizontalPadding)
        .frame(minHeight: 28)
    }

    private var progress: String {
        switch brief.state {
        case .scanning: return "Reading history and feeds…"
        case .choosing: return "Choosing sites…"
        case .reading(let hosts): return "Reading \(hosts.joined(separator: ", "))…"
        case .picking: return "Picking links…"
        case .idle, .failed: return ""
        }
    }

    private var morningQuestion: some View {
        HStack(spacing: 8) {
            Text("Build a brief each morning while Piper is open?")
                .font(PiperTheme.ui(12)).foregroundStyle(PiperTheme.secondary)
            Spacer(minLength: 8)
            Button("Not Now") { brief.answerMorning(false) }.buttonStyle(.text)
            Button("Build Each Morning") { brief.answerMorning(true) }.buttonStyle(.text)
        }
        .padding(.horizontal, AppDefaults.CaptureItem.horizontalPadding)
        .padding(.vertical, 6)
    }

    // MARK: - Actions

    private static let source = "Brief"

    private func save(_ pick: BriefPick) -> UUID? {
        guard let url = URL(string: pick.url) else { return nil }
        return model.store.saveArticle(url, title: pick.title, source: Self.source, to: "Inbox")?.id
    }

    private func open(_ pick: BriefPick) {
        guard let id = save(pick) else { return }
        brief.set(.kept, of: pick)
        model.showArticle?(id)
    }

    private func keep(_ pick: BriefPick) {
        guard save(pick) != nil else { return }
        brief.set(.kept, of: pick)
    }
}

/// One pick: a circle, the title, the site and the reason, and Keep and Skip.
private struct BriefPickRow: View {
    let pick: BriefPick
    let open: () -> Void
    let keep: () -> Void
    let skip: () -> Void
    let markRead: () -> Void

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            Button(action: markRead) {
                Image(systemName: "circle").font(.system(size: 16)).foregroundStyle(PiperTheme.faint)
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Mark as Read")
            Button(action: open) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(pick.title).font(PiperTheme.ui(13)).foregroundStyle(PiperTheme.ink).lineLimit(2)
                    Text("\(pick.host) · \(pick.why)")
                        .font(PiperTheme.ui(11.5)).foregroundStyle(PiperTheme.secondary).lineLimit(2)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel("\(pick.title), \(pick.host)")
            .accessibilityHint(pick.why)
            Button("Keep", action: keep).buttonStyle(.text)
            Button("Skip", action: skip).buttonStyle(.text).foregroundStyle(PiperTheme.secondary)
        }
        .padding(.horizontal, AppDefaults.CaptureItem.horizontalPadding)
        .padding(.vertical, 6)
    }
}
