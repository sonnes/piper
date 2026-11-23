import AppKit
import Agents
import Captures
import SwiftUI

/// One capture in the Inbox stream of the feed paper.
///
/// A note shows a circle that marks it as done, in sans serif because the
/// reader wrote it. A link shows a dot that is filled while the article is
/// unread, in serif because the reader reads it. The last notes of a link
/// show under its row. The content opens the capture. Command-click and
/// Shift-click select several captures.
struct InboxRow: View {

    /// How much of a link capture the row shows.
    enum Style {
        case note
        /// A link that the reader did not open: the title and the reading time.
        case link
        /// A started or finished article: the title and the progress.
        case compact
    }

    // MARK: - Properties

    let note: Note
    let style: Style
    let selected: Bool
    /// The section of the capture, when the list shows more than one section.
    let section: String?
    let children: [Note]
    let session: AgentSession?
    let select: () -> Void
    let complete: () -> Void
    let openRun: () -> Void
    /// Shows a note of the capture in its article.
    let openChild: (Note) -> Void
    let menu: NoteContextMenu

    private var reading: Reading { note.reading ?? Reading() }
    private var url: URL? { note.articleURL }
    private var host: String { url.map(ArticleBadge.host) ?? "" }
    private var isFinished: Bool { reading.finishedAt != nil }
    private var isUnread: Bool { style != .note && reading.openedAt == nil && !isFinished && !note.isDone }
    /// A done note or a read article. Its text is faint.
    private var isComplete: Bool { note.isDone || (style != .note && isFinished) }
    private var completionTitle: String {
        note.isDone ? "Reopen" : style == .note ? "Mark as Done" : isFinished ? "Read Again" : "Mark as Read"
    }

    var body: some View {
        PaperRow(item: .note(note.id), notes: children.count, selected: selected, time: RowTime.text(note.createdAt), action: select) {
            control
        } content: {
            VStack(alignment: .leading, spacing: 0) {
                title
                meta
                if !children.isEmpty { RowNotes(notes: children, open: openChild) }
            }
        }
        .accessibilityHint("Click to open. Command-click or Shift-click to select several captures.")
        .contextMenu { menu }
    }

    // MARK: - Parts

    private var control: some View {
        Button(action: complete) {
            Group {
                if style == .note || note.isDone {
                    TickMark(done: isComplete)
                } else {
                    UnreadDot(unread: isUnread)
                }
            }
            .frame(width: AppDefaults.Papers.markColumn, height: AppDefaults.Papers.rowLineHeight)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .help(completionTitle)
        .accessibilityLabel(completionTitle)
    }

    @ViewBuilder private var title: some View {
        if style != .note {
            PaperRowTitle(text: Text(reading.title.map(CaptureText.firstLine) ?? (host + (url?.path() ?? ""))),
                          read: true, bold: isUnread, done: note.isDone)
        } else if CaptureText.looksLikeCode(note.text) {
            Text(CaptureText.firstLine(note.text))
                .font(Font(PiperTheme.manuscript(size: AppDefaults.InboxRow.codeFontSize + 2)))
                .foregroundStyle(isComplete ? PiperTheme.paperFaint : PiperTheme.paperInk)
                .lineLimit(1)
                .frame(minHeight: AppDefaults.Papers.rowLineHeight, alignment: .leading)
        } else {
            PaperRowTitle(text: Text((try? AttributedString(markdown: note.text, options: .init(interpretedSyntax: .inlineOnlyPreservingWhitespace)))
                                     ?? AttributedString(note.text)),
                          done: isComplete)
        }
    }

    /// The section and the source of a note, or the site, the minutes, and
    /// the progress of a link. A run of an agent comes first.
    @ViewBuilder private var meta: some View {
        let parts = metaParts
        if session != nil || !parts.isEmpty {
            PaperRowMeta {
                if let session { RunBadge(session: session, open: openRun) }
                Text(parts.joined(separator: " · ")).monospacedDigit()
            }
        }
    }

    private var metaParts: [String] {
        if style == .note {
            let source = note.sources.first.map { $0 == "Clipboard" ? "Clipboard" : $0 }
            return [section, source].compactMap { $0 }
        }
        var parts = [note.sources.first ?? host]
        if let minutes = reading.minutes { parts.append("\(minutes) min") }
        if !isComplete, reading.progress > 0 { parts.append("\(Int((reading.progress * 100).rounded()))% read") }
        if let section { parts.append(section) }
        return parts
    }
}

/// The done control of a link: a ring that fills with the reading progress.
/// A finished article, or any done capture, shows a gray check.
struct ProgressRing: View {
    let progress: Double
    let finished: Bool

    var body: some View {
        ZStack {
            let metrics = AppDefaults.ProgressRing.self
            Circle().strokeBorder(PiperTheme.faint, lineWidth: metrics.lineWidth)
            if finished {
                Image(systemName: "checkmark").font(.system(size: metrics.checkFontSize, weight: .bold)).foregroundStyle(PiperTheme.faint)
            } else if progress > 0 {
                Circle()
                    .trim(from: 0, to: min(max(progress, metrics.minimumProgress), 1))
                    .stroke(PiperTheme.accent, style: StrokeStyle(lineWidth: metrics.progressLineWidth, lineCap: .round))
                    .rotationEffect(.degrees(-90))
                    .padding(metrics.progressInset)
            }
        }
    }
}
