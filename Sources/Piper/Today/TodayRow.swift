import AppKit
import Agents
import Captures
import Feeds
import PiperCore
import Stream
import SwiftUI

/// What a row of Today can do. The list gives each row the same actions,
/// bound to the row.
struct RowVerbs {
    let open: () -> Void
    let keep: () -> Void
    let done: () -> Void
    let file: () -> Void
    let send: (SkillFolders.Action?) -> Void
    let ask: () -> Void
    let copy: () -> Void
    let delete: () -> Void
    /// Edits a capture in a sheet. Nil for other kinds.
    var edit: (() -> Void)?
    var editInWindow: (() -> Void)?
    /// Joins the selected captures. Nil unless several captures are selected.
    var merge: (() -> Void)?
    /// Opens the list of the feed of an article or a digest.
    var openFeed: (() -> Void)?
    var stopSession: (() -> Void)?
}

/// One row of Today: a note, a link, an article, a digest, or a clipboard text.
///
/// The selected row and the row under the pointer show the four verbs as
/// round buttons in place of the time: Keep, Done, File, and Send, then a
/// More menu. The context menu has the same items. No action needs a swipe.
struct TodayRow: View {
    let item: StreamItem
    let selected: Bool
    let model: AppModel
    let verbs: RowVerbs
    /// The section of a capture, when the list shows more than one section.
    var section: String?
    let click: () -> Void


    var body: some View {
        PaperRow(item: paperItem, notes: item.children.count, selected: selected, actionsOnSelection: true,
                 time: RowTime.text(item.date), action: click) {
            mark
        } content: {
            VStack(alignment: .leading, spacing: 0) {
                title
                meta
                if item.kind == .digest { digestTitles }
                if !shownNotes.isEmpty {
                    RowNotes(notes: shownNotes) { child in
                        guard let note = item.note else { return }
                        model.showHighlight(child.id, in: note.id)
                        verbs.open()
                    }
                }
            }
        } actions: {
            VerbButtons(item: item, model: model, verbs: verbs)
        }
        .accessibilityHint("Click to select. Return opens it. K keeps, E marks as done, F files, and S sends it.")
        .contextMenu { TodayMenu(item: item, model: model, verbs: verbs) }
    }

    // MARK: - Parts

    private var paperItem: PaperItem? {
        switch item.id {
        case .note(let id): return .note(id)
        case .article(let id): return .article(id)
        case .digest, .clip: return nil
        }
    }

    /// The circle of a note marks it as done. A link, an article, and a
    /// digest show the icon of the site. A clipboard text shows a clipboard.
    @ViewBuilder private var mark: some View {
        switch item.kind {
        case .note:
            Button(action: verbs.done) { TickMark(done: item.state == .done) }
                .buttonStyle(.plain)
                .help(item.state == .done ? "Reopen" : "Mark as Done")
                .accessibilityLabel(item.state == .done ? "Reopen" : "Mark as Done")
        case .link, .article, .digest:
            ZStack(alignment: .topTrailing) {
                SiteIcon(favicons: model.favicons, host: host, title: item.source ?? host)
                if item.state == .new {
                    UnreadDot().offset(x: 3, y: -3)
                }
            }
        case .clip:
            Image(systemName: "doc.on.clipboard")
                .font(.system(size: 14))
                .foregroundStyle(PiperTheme.paperFaint)
                .accessibilityHidden(true)
        }
    }

    private var host: String {
        item.url.flatMap(Site.init)?.key ?? item.source ?? ""
    }

    @ViewBuilder private var title: some View {
        let done = item.state == .done
        let bold = item.state == .new && item.kind != .note && item.kind != .clip
        switch item.kind {
        case .note where CaptureText.looksLikeCode(item.title), .clip where CaptureText.looksLikeCode(item.title):
            Text(CaptureText.firstLine(item.title))
                .font(Font(PiperTheme.manuscript(size: Metrics.codeFontSize)))
                .foregroundStyle(done ? PiperTheme.paperFaint : PiperTheme.paperInk)
                .lineLimit(1)
                .frame(minHeight: PaperRowMetrics.rowLineHeight, alignment: .leading)
        case .note:
            PaperRowTitle(text: Text((try? AttributedString(markdown: item.title, options: .init(interpretedSyntax: .inlineOnlyPreservingWhitespace)))
                                     ?? AttributedString(item.title)), done: done)
        case .clip:
            PaperRowTitle(text: Text(item.title.replacingOccurrences(of: "\n", with: " ")))
        case .digest:
            HStack(spacing: 6) {
                PaperRowTitle(text: Text(item.title), bold: bold, lines: 1)
                Text("\(item.articles.filter { !$0.read }.count) new")
                    .font(PiperTheme.paperUI(.body, weight: .medium))
                    .foregroundStyle(PiperTheme.brand)
                    .fixedSize()
            }
        case .link, .article:
            PaperRowTitle(text: Text(CaptureText.firstLine(item.title)), bold: bold, done: done)
        }
    }

    /// The source, the reason, and the progress of the row.
    @ViewBuilder private var meta: some View {
        let session = item.note.flatMap { model.agents.runner.latestSession(for: $0.id) }
        let parts = metaParts
        if session != nil || !parts.isEmpty || item.state == .kept {
            PaperRowMeta {
                if let session { RunBadge(session: session) { verbs.open() } }
                if item.state == .kept {
                    Image(systemName: "star.fill").foregroundStyle(PiperTheme.brand).accessibilityLabel("Kept")
                }
                Text(parts.joined(separator: " · ")).monospacedDigit()
            }
        }
    }

    private var metaParts: [String] {
        switch item.kind {
        case .note:
            return [item.note?.sources.first ?? "Note", section].compactMap { $0 }
        case .clip:
            return ["Clipboard", item.source].compactMap { $0 }
        case .digest:
            return []
        case .article:
            var parts = [item.source ?? host]
            if item.score >= Relevance.bar { parts.append("matches your reading") }
            return parts
        case .link:
            guard let note = item.note else { return [] }
            let reading = note.reading ?? Reading()
            var parts = [note.sources.first ?? host]
            if reading.openedAt == nil, reading.finishedAt == nil, !note.isDone { parts.append("Read later") }
            if let left = reading.minutesLeft, reading.progress > 0, reading.finishedAt == nil { parts.append("\(left) min left") }
            else if let minutes = reading.minutes { parts.append("\(minutes) min") }
            let counts = ReadingList.counts(of: item.children)
            if !counts.isEmpty { parts.append(counts) }
            if let section { parts.append(section) }
            return parts
        }
    }

    /// The first titles of a digest, then a count of the others.
    private var digestTitles: some View {
        let limit = Metrics.digestTitles
        let titles = item.articles.prefix(limit).map { CaptureText.firstLine($0.title) }.joined(separator: " · ")
        let rest = item.articles.count - min(limit, item.articles.count)
        return Text(titles + (rest > 0 ? " and \(rest) more" : ""))
            .font(PiperTheme.paperUI(.body))
            .foregroundStyle(PiperTheme.paperMuted)
            .lineLimit(2)
            .padding(.top, 2)
    }

    /// The highlights and notes under a link, or the notes under a note.
    private var shownNotes: [Note] {
        item.kind == .link || item.kind == .note ? item.children.filter { !$0.has(.question) } : []
    }
}

// MARK: - Verbs

extension TodayRow {
    enum Metrics {
        /// The round button of a verb on the selected row and on the row under the pointer.
        static let verbButton: CGFloat = 30
        static let verbGlyph: CGFloat = 14
        static let verbSpacing: CGFloat = 2
        static let codeFontSize: CGFloat = 14
        /// The titles of a digest row: the first titles, then a count of the others.
        static let digestTitles = 2
    }
}

/// The four verbs of a row as round buttons, then the More menu.
struct VerbButtons: View {
    let item: StreamItem
    let model: AppModel
    let verbs: RowVerbs

    var body: some View {
        HStack(spacing: TodayRow.Metrics.verbSpacing) {
            let kept = item.note?.isKept == true
            VerbButton(symbol: kept ? "star.fill" : "star", title: kept ? "Kept · K removes the mark" : "Keep · K",
                       tint: kept ? PiperTheme.brand : PiperTheme.paperMuted, action: verbs.keep)
            VerbButton(symbol: item.state == .done ? "arrow.uturn.backward" : "checkmark",
                       title: item.state == .done ? "Reopen · E" : "Done · E", action: verbs.done)
            VerbButton(symbol: "arrow.turn.down.right", title: "File · F", action: verbs.file)
            Menu {
                SendItems(model: model, verbs: verbs)
            } label: {
                VerbGlyph(symbol: "paperplane", tint: PiperTheme.paperMuted)
            }
            .menuStyle(.borderlessButton).menuIndicator(.hidden).fixedSize()
            .help("Send · S").accessibilityLabel("Send")
            Menu {
                TodayMenu(item: item, model: model, verbs: verbs)
            } label: {
                VerbGlyph(symbol: "ellipsis", tint: PiperTheme.paperMuted)
            }
            .menuStyle(.borderlessButton).menuIndicator(.hidden).fixedSize()
            .help("More").accessibilityLabel("More")
        }
    }
}

/// A 30-point round button with a symbol.
struct VerbButton: View {
    let symbol: String
    let title: String
    var tint: Color = PiperTheme.paperMuted
    let action: () -> Void

    var body: some View {
        Button(action: action) { VerbGlyph(symbol: symbol, tint: tint) }
            .buttonStyle(.plain)
            .help(title)
            .accessibilityLabel(title)
    }
}

/// The symbol of a verb in its 30-point circle. The circle fills under the pointer.
struct VerbGlyph: View {
    let symbol: String
    let tint: Color

    @State private var hovered = false

    var body: some View {
        let metrics = TodayRow.Metrics.self
        Image(systemName: symbol)
            .font(.system(size: metrics.verbGlyph, weight: .medium))
            .foregroundStyle(tint)
            .frame(width: metrics.verbButton, height: metrics.verbButton)
            .background(hovered ? PiperTheme.rowHover : .clear, in: Circle())
            .contentShape(Circle())
            .onHover { hovered = $0 }
    }
}

/// The skills of each folder, then Ask.
struct SendItems: View {
    let model: AppModel
    let verbs: RowVerbs

    var body: some View {
        if !model.skills.folders.isEmpty {
            Button("Send with the Default Skill") { verbs.send(nil) }.keyboardShortcut("s", modifiers: [])
            Divider()
            SendMenuItems(skills: model.skills) { verbs.send($0) }
            Divider()
        }
        Button("Ask…", action: verbs.ask)
    }
}

/// The More menu and the context menu of a row.
struct TodayMenu: View {
    let item: StreamItem
    let model: AppModel
    let verbs: RowVerbs

    var body: some View {
        Button("Open", action: verbs.open)
        Divider()
        Button(item.note?.isKept == true ? "Remove Keep" : "Keep", action: verbs.keep)
        Button(item.state == .done ? "Reopen" : "Done", action: verbs.done)
        Button("File…", action: verbs.file)
        Menu("Send") { SendItems(model: model, verbs: verbs) }
        Divider()
        if let edit = verbs.edit { Button("Edit", action: edit) }
        if let editInWindow = verbs.editInWindow { Button("Edit in New Window", action: editInWindow) }
        if let merge = verbs.merge { Button("Merge Notes", action: merge) }
        Button("Copy", action: verbs.copy)
        if item.kind == .article, let article = item.articles.first {
            Button("Copy Link") { model.articleActions.copyLink(article) }
            Button("Open in Browser") { model.articleActions.openInBrowser(article) }
        } else if let url = item.url, url.isWeb {
            Button("Copy Link") { Clipboard.copy(url.absoluteString) }
            Button("Open in Browser") { NSWorkspace.shared.open(url) }
        }
        if let openFeed = verbs.openFeed {
            Divider()
            Button("Show the Feed", action: openFeed)
            if let feed = item.articles.first.flatMap({ model.feeds.feed($0.feedID) }) {
                FeedModeMenu(feeds: model.feeds, feed: feed)
            }
        }
        if let stop = verbs.stopSession { Button("Stop Session", action: stop) }
        if TodayModel.canDelete(item.id) {
            Divider()
            Button("Delete", role: .destructive, action: verbs.delete)
        }
    }
}

/// How Today shows the posts of one feed: each post, the best posts and a
/// digest of the rest, one digest a day, or nothing. Piper saves the choice
/// for the feed.
struct FeedModeMenu: View {
    let feeds: FeedStore
    let feed: Feed

    var body: some View {
        Picker("Show Posts", selection: Binding(get: { feed.mode }, set: { feeds.setMode($0, of: feed.id) })) {
            ForEach(FeedMode.allCases, id: \.self) { mode in
                Text(mode.title).tag(mode)
            }
        }
        .pickerStyle(.menu)
    }
}
