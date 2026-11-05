import AppKit
import Agents
import Captures
import SwiftUI

/// One capture in the Inbox stream of the main window.
///
/// A circle completes a note. A ring marks an article as read.
/// The content opens the capture. Command-click and Shift-click select several captures.
struct InboxRow: View {

    /// How much of a link capture the row shows.
    enum Style {
        case note
        /// A link that the reader did not open: the title and the reading time.
        case link
        /// A started or finished article: the title and the minutes left.
        case compact
    }

    // MARK: - Properties

    let note: Note
    let style: Style
    let selected: Bool
    /// The section and its color, when the list shows more than one section.
    let section: (name: String, color: Color)?
    let children: [Note]
    let showsChildren: Bool
    let toggleChildren: () -> Void
    let session: AgentSession?
    let select: () -> Void
    let complete: () -> Void
    let openRun: () -> Void
    let menu: NoteContextMenu
    @State private var hovered = false

    private var reading: Reading { note.reading ?? Reading() }
    private var url: URL? { note.articleURL }
    private var host: String { url.map(ArticleBadge.host) ?? "" }
    private var isFinished: Bool { reading.finishedAt != nil }
    /// A done note or a read article. Its control is a gray check and its text is gray.
    private var isComplete: Bool { note.isDone || (style != .note && isFinished) }
    /// The time of the capture, or the app that it came from. The row shows it on hover.
    private var hoverText: String {
        if style == .note, let source = note.sources.first, source != "Clipboard" { return "From " + source }
        return RowTime.text(note.createdAt)
    }
    private var completionTitle: String {
        note.isDone ? "Reopen" : style == .note ? "Mark as Done" : isFinished ? "Read Again" : "Mark as Read"
    }

    var body: some View {
        VStack(spacing: 0) {
            HStack(alignment: .top, spacing: AppDefaults.InboxRow.columnSpacing) {
                control
                Button(action: select) { content.contentShape(Rectangle()) }
                    .buttonStyle(.plain)
                    .accessibilityAddTraits(selected ? .isSelected : [])
                    .accessibilityHint("Click to open. Command-click or Shift-click to select several captures.")
                if hovered {
                    Text(hoverText)
                        .font(PiperTheme.ui(AppDefaults.InboxRow.metaFontSize)).foregroundStyle(PiperTheme.faint)
                        .monospacedDigit().lineLimit(1).fixedSize()
                }
            }
            .padding(AppDefaults.InboxRow.padding)
            .background(selected ? PiperTheme.selection : hovered ? PiperTheme.hover : .clear,
                        in: RoundedRectangle(cornerRadius: AppDefaults.InboxRow.cornerRadius))
        }
        .onHover { hovered = $0 }
        .contextMenu { menu }
    }

    // MARK: - Parts

    @ViewBuilder private var control: some View {
        Button(action: complete) {
            Group {
                if isComplete {
                    ProgressRing(progress: 1, finished: true)
                } else if style == .note {
                    Circle().strokeBorder(PiperTheme.faint, lineWidth: AppDefaults.ProgressRing.lineWidth)
                } else {
                    ProgressRing(progress: reading.progress, finished: false)
                }
            }
            .frame(width: AppDefaults.InboxRow.controlSize, height: AppDefaults.InboxRow.controlSize)
            .frame(width: AppDefaults.InboxRow.controlColumn, height: AppDefaults.InboxRow.controlSize + 2)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .help(completionTitle)
        .accessibilityLabel(completionTitle)
    }

    @ViewBuilder private var content: some View {
        VStack(alignment: .leading, spacing: 3) {
            if style == .note {
                noteText
            } else {
                Text(reading.title.map(CaptureText.firstLine) ?? (host + (url?.path() ?? "")))
                    .font(PiperTheme.ui(AppDefaults.InboxRow.titleFontSize))
                    .foregroundStyle(isComplete ? PiperTheme.secondary : PiperTheme.ink)
                    .lineLimit(1)
            }
            meta
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    @ViewBuilder private var noteText: some View {
        if CaptureText.looksLikeCode(note.text) {
            Text(CaptureText.firstLine(note.text))
                .font(Font(PiperTheme.manuscript(size: AppDefaults.InboxRow.codeFontSize)))
                .lineLimit(1)
        } else {
            Text((try? AttributedString(markdown: note.text, options: .init(interpretedSyntax: .inlineOnlyPreservingWhitespace)))
                 ?? AttributedString(note.text))
                .font(PiperTheme.ui(AppDefaults.InboxRow.titleFontSize))
                .foregroundStyle(isComplete ? PiperTheme.secondary : PiperTheme.ink)
                .lineSpacing(AppDefaults.ChildNote.lineSpacing)
                .lineLimit(2)
        }
    }

    /// The run, the site of a link, the count of child notes, and the section.
    /// A note with none of these shows only its text.
    @ViewBuilder private var meta: some View {
        if session != nil || style != .note || section != nil || !children.isEmpty {
            HStack(spacing: 5) {
                if let session { RunBadge(session: session, open: openRun) }
                if style != .note {
                    Text(host + (linkDetail.map { " · " + $0 } ?? "")).monospacedDigit().layoutPriority(1)
                }
                if !children.isEmpty {
                    Button(action: toggleChildren) { CountChip(text: childCount, open: showsChildren) }
                        .buttonStyle(.plain)
                        .accessibilityLabel(showsChildren ? "Hide notes" : "Show notes")
                        .accessibilityValue(childCount)
                }
                if let section {
                    if session != nil || style != .note || !children.isEmpty { Text("·") }
                    Circle().fill(section.color).frame(width: AppDefaults.InboxRow.sectionDot, height: AppDefaults.InboxRow.sectionDot)
                    Text(section.name)
                }
            }
            .font(PiperTheme.ui(AppDefaults.InboxRow.metaFontSize))
            .foregroundStyle(PiperTheme.secondary)
            .lineLimit(1)
        }
    }

    /// The reading time of a new link, or the minutes left of a started one.
    /// A read article shows only its site.
    private var linkDetail: String? {
        switch style {
        case .note: return nil
        case .link: return reading.minutes.map { "\($0) min" }
        case .compact: return isComplete ? nil : reading.minutesLeft.map { "\($0) min left" }
        }
    }

    /// "2 highlights · 1 note", or the number of child notes when none is a highlight or a question.
    private var childCount: String {
        let counts = ReadingList.counts(of: children)
        guard counts.isEmpty else { return counts }
        return "\(children.count) " + (children.count == 1 ? "note" : "notes")
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
