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
        /// A started article with the progress, the newest highlight, and the counts.
        case full
    }

    // MARK: - Properties

    let note: Note
    let style: Style
    let selected: Bool
    let separated: Bool
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

    private var reading: Reading { note.reading ?? Reading() }
    private var url: URL? { note.articleURL }
    private var host: String { url.map(ArticleBadge.host) ?? "" }
    private var isFinished: Bool { reading.finishedAt != nil }
    private var completionTitle: String {
        note.isDone ? "Reopen" : style == .note ? "Mark as Done" : isFinished ? "Read Again" : "Mark as Read"
    }

    var body: some View {
        VStack(spacing: 0) {
            if separated && !selected { Rule().padding(.leading, AppDefaults.InboxRow.textInset) }
            HStack(alignment: .top, spacing: AppDefaults.InboxRow.columnSpacing) {
                control
                Button(action: select) { content.contentShape(Rectangle()) }
                    .buttonStyle(.plain)
                    .accessibilityAddTraits(selected ? .isSelected : [])
                    .accessibilityHint("Click to open. Command-click or Shift-click to select several captures.")
            }
            .padding(AppDefaults.InboxRow.padding)
            .background(selected ? PiperTheme.selection : .clear, in: RoundedRectangle(cornerRadius: AppDefaults.InboxRow.cornerRadius))
        }
        .contextMenu { menu }
    }

    // MARK: - Parts

    @ViewBuilder private var control: some View {
        Button(action: complete) {
            Group {
                if note.isDone {
                    ZStack {
                        Circle().fill(PiperTheme.accent)
                        Image(systemName: "checkmark").font(.system(size: AppDefaults.ProgressRing.checkFontSize, weight: .bold))
                            .foregroundStyle(PiperTheme.onAccent)
                    }
                } else if style == .note {
                    Circle().strokeBorder(PiperTheme.faint, lineWidth: AppDefaults.ProgressRing.lineWidth)
                } else {
                    ProgressRing(progress: isFinished ? 1 : reading.progress, finished: isFinished)
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
                HStack(alignment: .firstTextBaseline, spacing: 6) {
                    if style == .link {
                        Circle().fill(PiperTheme.accent)
                            .frame(width: AppDefaults.InboxRow.unreadDot, height: AppDefaults.InboxRow.unreadDot)
                            .accessibilityLabel("Not opened")
                    }
                    Text(reading.title ?? (host + (url?.path() ?? "")))
                        .font(PiperTheme.ui(AppDefaults.InboxRow.titleFontSize, weight: .semibold))
                        .lineLimit(2)
                }
            }
            meta
            if style == .full { article }
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
                .lineSpacing(AppDefaults.ChildNote.lineSpacing)
                .lineLimit(2)
        }
    }

    private var meta: some View {
        HStack(spacing: 5) {
            if let session { RunBadge(session: session, open: openRun) }
            if style == .note {
                Text(RowTime.text(note.createdAt)).monospacedDigit()
                if let source = note.sources.first, source != "Clipboard" { Text("· From " + source) }
            } else {
                ArticleBadge(host: host, size: AppDefaults.InboxRow.badgeSize)
                Text(host)
                if let detail = linkDetail { Text("· " + detail).monospacedDigit() }
            }
            if let section {
                Text("·")
                Circle().fill(section.color).frame(width: AppDefaults.InboxRow.sectionDot, height: AppDefaults.InboxRow.sectionDot)
                Text(section.name)
            }
        }
        .font(PiperTheme.ui(AppDefaults.InboxRow.metaFontSize))
        .foregroundStyle(PiperTheme.secondary)
        .lineLimit(1)
    }

    /// The reading time of a new link, or the minutes left of a started one.
    private var linkDetail: String? {
        switch style {
        case .note, .full: return nil
        case .link: return reading.minutes.map { "\($0) min" }
        case .compact: return isFinished ? "Read" : reading.minutesLeft.map { "\($0) min left" }
        }
    }

    @ViewBuilder private var article: some View {
        HStack(spacing: 8) {
            GeometryReader { proxy in
                ZStack(alignment: .leading) {
                    Capsule().fill(PiperTheme.rule)
                    Capsule().fill(PiperTheme.accent).frame(width: proxy.size.width * min(max(reading.progress, 0), 1))
                }
            }
            .frame(height: AppDefaults.Reading.progressHeight)
            if let left = reading.minutesLeft {
                Text("\(left) min left").font(PiperTheme.ui(AppDefaults.InboxRow.detailFontSize)).foregroundStyle(PiperTheme.faint).monospacedDigit().fixedSize()
            }
        }
        .padding(.top, 4)
        .accessibilityElement()
        .accessibilityLabel("\(Int((reading.progress * 100).rounded())) percent read")
        if let last = ReadingList.highlights(in: children).max(by: { $0.createdAt < $1.createdAt }) {
            Text(last.anchor?.quote ?? last.text.components(separatedBy: "\n\n")[0])
                .font(.system(size: AppDefaults.InboxRow.quoteFontSize, design: .serif).italic())
                .foregroundStyle(PiperTheme.secondary)
                .lineLimit(1)
                .padding(.leading, 7)
                .overlay(alignment: .leading) {
                    Rectangle().fill(PiperTheme.markYellow).frame(width: AppDefaults.Reading.quoteRuleWidth)
                }
                .padding(.top, 3)
        }
        if !children.isEmpty {
            Button(action: toggleChildren) {
                HStack(spacing: 4) {
                    Image(systemName: showsChildren ? "chevron.down" : "chevron.right")
                        .font(.system(size: AppDefaults.InboxRow.chevronSize, weight: .semibold))
                    Text(childCount)
                }
                .font(PiperTheme.ui(AppDefaults.InboxRow.detailFontSize)).foregroundStyle(PiperTheme.faint)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .padding(.top, 2)
            .accessibilityLabel(showsChildren ? "Hide notes" : "Show notes")
            .accessibilityValue(childCount)
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
/// A finished article shows a check.
struct ProgressRing: View {
    let progress: Double
    let finished: Bool

    var body: some View {
        ZStack {
            let metrics = AppDefaults.ProgressRing.self
            Circle().strokeBorder(PiperTheme.faint, lineWidth: metrics.lineWidth)
            if finished {
                Circle().fill(PiperTheme.accent)
                Image(systemName: "checkmark").font(.system(size: metrics.checkFontSize, weight: .bold)).foregroundStyle(PiperTheme.onAccent)
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
