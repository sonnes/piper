import AppKit
import Captures
import SwiftUI

/// One row of a list on the feed paper: a mark, the text, and a time.
///
/// The selected row has a fill and a bar at its left edge, in indigo while
/// the feed paper has the focus. A row whose item is open as a reader paper
/// shows a dashed slot and "on the desk" in place of its time. The row
/// flashes when its paper goes back, and when a note lands under it.
struct PaperRow<Mark: View, Content: View>: View {
    /// The item that the row opens, for its slot and its flash.
    let item: PaperItem?
    var openOnDesk = false
    /// The count of the notes under the row. The row flashes when it grows.
    var notes = 0
    let selected: Bool
    let time: String
    let action: () -> Void
    @ViewBuilder let mark: () -> Mark
    @ViewBuilder let content: () -> Content

    @Environment(DeskMarks.self) private var marks: DeskMarks?
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var flashing = false
    private typealias Metrics = AppDefaults.Papers

    private var lifted: Bool { openOnDesk || (item.map { marks?.isOpen($0) == true } ?? false) }

    var body: some View {
        decorated
            .clipShape(RoundedRectangle(cornerRadius: Metrics.rowRadius, style: .continuous))
            .contentShape(Rectangle())
            .onTapGesture(perform: action)
            .onChange(of: flashID) { _, id in
                if id != nil { flash() }
            }
            .onChange(of: notes) { old, new in
                if new > old { flash() }
            }
            .accessibilityElement(children: .combine)
            .accessibilityAddTraits(selected ? [.isButton, .isSelected] : .isButton)
            .accessibilityValue(lifted ? "On the desk" : "")
            .accessibilityAction(.default, action)
    }

    private var flashID: UUID? {
        guard let item, let marks else { return nil }
        return marks.flashes(item)
    }

    private var line: some View {
        HStack(alignment: .top, spacing: Metrics.rowSpacing) {
            mark().frame(width: Metrics.markColumn, height: Metrics.rowLineHeight)
            content()
                .frame(maxWidth: .infinity, alignment: .leading)
                .environment(\.rowLifted, lifted)
            timeLabel
        }
        .padding(Metrics.listRowPadding)
    }

    private var decorated: some View {
        line
            .background(background)
            .overlay(alignment: .leading) { selectionBar }
            .overlay { slot }
    }

    @ViewBuilder private var selectionBar: some View {
        if selected {
            let color: Color = marks?.feedFocused == true ? PiperTheme.brand : PiperTheme.paperBar
            RoundedRectangle(cornerRadius: Metrics.selectionBarWidth)
                .fill(color)
                .frame(width: Metrics.selectionBarWidth)
                .padding(.vertical, Metrics.selectionBarInset)
        }
    }

    @ViewBuilder private var slot: some View {
        if lifted {
            let style = StrokeStyle(lineWidth: Metrics.markLine, dash: Metrics.slotDash)
            RoundedRectangle(cornerRadius: Metrics.rowRadius, style: .continuous)
                .strokeBorder(PiperTheme.paperSlot, style: style)
                .padding(Metrics.markLine)
        }
    }

    private var timeLabel: some View {
        let text: String = lifted ? "on the desk" : time
        let weight: NSFont.Weight = lifted ? .medium : .regular
        let color: Color = lifted ? PiperTheme.brand : PiperTheme.paperFaint
        return Text(text)
            .font(PiperTheme.paperUI(.body, weight: weight))
            .foregroundStyle(color)
            .monospacedDigit().lineLimit(1).fixedSize()
            .frame(minHeight: Metrics.rowLineHeight)
    }

    private var background: some View {
        ZStack {
            if selected { PiperTheme.paperTint }
            PiperTheme.currentRow.opacity(flashing ? 1 : 0)
        }
    }

    /// The mock holds the indigo for 30 percent of the flash, then fades it to the fill.
    private func flash() {
        guard !reduceMotion else { return }
        flashing = true
        let hold = Metrics.flash * 0.3
        DispatchQueue.main.asyncAfter(deadline: .now() + hold) {
            withAnimation(.easeOut(duration: Metrics.flash - hold)) { flashing = false }
        }
    }
}

/// The title of a row. Text that the reader wrote is sans serif. Text that
/// the reader reads, such as an article or a file, is serif.
struct PaperRowTitle: View {
    let text: Text
    var read = false
    var bold = false
    var done = false
    var lines = 2

    @Environment(\.rowLifted) private var lifted
    private typealias Metrics = AppDefaults.Papers

    var body: some View {
        let heavy = bold && !lifted
        text
            .font(read ? PiperTheme.paperSerif(Metrics.serifRowSize, weight: heavy ? .semibold : .regular)
                       : PiperTheme.paperUI(.row, weight: heavy ? .semibold : .regular))
            .foregroundStyle(done || lifted ? PiperTheme.paperFaint : PiperTheme.paperInk)
            .strikethrough(done, color: PiperTheme.paperFaint)
            .lineSpacing(Metrics.rowLineSpacing)
            .lineLimit(lines)
            .frame(minHeight: Metrics.rowLineHeight, alignment: .leading)
    }
}

/// The meta line under the title of a row.
struct PaperRowMeta<Content: View>: View {
    @ViewBuilder let content: () -> Content

    var body: some View {
        HStack(spacing: 5) { content() }
            .font(PiperTheme.paperUI(.body))
            .foregroundStyle(PiperTheme.paperFaint)
            .lineLimit(1)
            .padding(.top, 1)
    }
}

// MARK: - Marks

/// The circle of a capture: a ring, or a filled indigo circle with a check when done.
struct TickMark: View {
    let done: Bool

    var body: some View {
        let metrics = AppDefaults.Papers.self
        ZStack {
            if done {
                Circle().fill(PiperTheme.indigo)
                Image(systemName: "checkmark").font(.system(size: 9, weight: .bold)).foregroundStyle(PiperTheme.onAccent)
            } else {
                Circle().strokeBorder(PiperTheme.paperFaint, lineWidth: metrics.markLine)
            }
        }
        .frame(width: metrics.tickSize, height: metrics.tickSize)
    }
}

/// The dot of an article: filled indigo while unread, a ring once read.
struct UnreadDot: View {
    let unread: Bool

    var body: some View {
        let metrics = AppDefaults.Papers.self
        Group {
            if unread {
                Circle().fill(PiperTheme.brand)
            } else {
                Circle().strokeBorder(PiperTheme.paperBar, lineWidth: metrics.markLine)
            }
        }
        .frame(width: metrics.dotSize, height: metrics.dotSize)
        .accessibilityLabel(unread ? "Unread" : "")
    }
}

/// The sheet of a file: a page with a folded corner.
struct SheetMark: View {
    var body: some View {
        let metrics = AppDefaults.Papers.self
        UnevenRoundedRectangle(topLeadingRadius: 2, bottomLeadingRadius: 2, bottomTrailingRadius: 2, topTrailingRadius: 5)
            .strokeBorder(PiperTheme.paperFaint, lineWidth: metrics.markLine)
            .frame(width: metrics.sheetMark.width, height: metrics.sheetMark.height)
            .accessibilityHidden(true)
    }
}

// MARK: - Notes

/// The last notes of an article under its row: the quote in serif, and the
/// note of the reader under it.
struct RowNotes: View {
    let notes: [Note]
    let open: (Note) -> Void

    private typealias Metrics = AppDefaults.Papers

    var body: some View {
        let shown = notes.suffix(Metrics.rowNoteLimit)
        VStack(alignment: .leading, spacing: 6) {
            ForEach(Array(shown)) { note in
                Button { open(note) } label: {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(Self.quote(of: note))
                            .font(PiperTheme.paperSerif(Metrics.quoteSize))
                            .foregroundStyle(PiperTheme.paperMuted)
                            .lineSpacing(4).lineLimit(2)
                        let comment = Self.comment(of: note)
                        if !comment.isEmpty {
                            Text(comment).font(PiperTheme.paperUI(.body)).foregroundStyle(PiperTheme.paperInk).lineLimit(2)
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityHint("Shows the note in the article")
            }
            if notes.count > shown.count {
                Text("and \(notes.count - shown.count) more").font(PiperTheme.paperUI(.body)).foregroundStyle(PiperTheme.paperFaint)
            }
        }
        .padding(Metrics.rowNotesPadding)
        .overlay(alignment: .leading) { Rectangle().fill(PiperTheme.quoteBar).frame(width: Metrics.quoteBarWidth) }
        .padding(.top, 0)
    }

    /// The quote of a highlight, or the first paragraph of another note.
    static func quote(of note: Note) -> String {
        note.anchor?.quote ?? (note.text.components(separatedBy: "\n\n").first ?? note.text)
    }

    /// The words of the reader after the quote of a highlight.
    static func comment(of note: Note) -> String {
        guard note.anchor?.quote != nil else { return "" }
        return HighlightText.comment(of: note.text, quote: note.anchor?.quote)
    }
}

/// A group header in a list of the feed paper, such as Today.
struct PaperGroupHeader: View {
    let title: String
    var action: (title: String, run: () -> Void)?

    var body: some View {
        HStack {
            Text(title)
            Spacer(minLength: 8)
            if let action {
                Button(action.title, action: action.run).buttonStyle(.plain).foregroundStyle(PiperTheme.brand)
            }
        }
        .font(PiperTheme.paperUI(.body, weight: .medium))
        .foregroundStyle(PiperTheme.paperFaint)
        .padding(AppDefaults.Papers.groupHeaderPadding)
        .accessibilityAddTraits(.isHeader)
    }
}

extension EnvironmentValues {
    /// True inside a row whose item is open as a reader paper. Its title turns faint.
    @Entry var rowLifted = false
}

/// The fold over the captures done today, at the end of a list of the feed paper.
struct PaperDoneToday: View {
    let count: Int
    let shown: Bool
    let toggle: () -> Void

    var body: some View {
        Button(action: toggle) {
            HStack(spacing: 6) {
                Text(shown ? "Hide \(count) done today" : "\(count) done today")
                Spacer(minLength: 0)
            }
            .font(PiperTheme.paperUI(.body, weight: .medium))
            .foregroundStyle(PiperTheme.paperFaint)
            .padding(AppDefaults.Papers.groupHeaderPadding)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(shown ? "Hide \(count) done today" : "Show \(count) done today")
    }
}

/// A title and a line under it, in a list of the feed paper that has nothing to show.
struct PaperEmpty: View {
    let title: String
    var detail: String?

    var body: some View {
        VStack(spacing: 4) {
            Text(title).font(PiperTheme.paperUI(.row, weight: .semibold)).foregroundStyle(PiperTheme.paperMuted)
            if let detail {
                Text(detail).font(PiperTheme.paperUI(.body)).foregroundStyle(PiperTheme.paperFaint)
            }
        }
        .multilineTextAlignment(.center)
        .padding(24)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .allowsHitTesting(false)
    }
}

/// One copy in the clipboard list of the feed paper. Keep saves it to Inbox.
struct PaperClipboardRow: View {
    let entry: ClipboardEntry
    let keep: () -> Void
    let copy: () -> Void
    let agents: FolderAgents
    let send: (FolderAgents.Action?) -> Void

    @State private var hovered = false

    var body: some View {
        PaperRow(item: nil, selected: false, time: RowTime.text(entry.copiedAt), action: copy) {
            SheetMark()
        } content: {
            VStack(alignment: .leading, spacing: 2) {
                PaperRowTitle(text: Text(entry.text.replacingOccurrences(of: "\n", with: " ")), lines: 2)
                PaperRowMeta {
                    if let source = entry.source { Text(source) }
                    if hovered {
                        Button("Keep", action: keep).buttonStyle(.plain)
                            .font(PiperTheme.paperUI(.body, weight: .medium)).foregroundStyle(PiperTheme.brand)
                    }
                }
            }
        }
        .onHover { hovered = $0 }
        .contextMenu {
            Button("Copy", action: copy)
            Button("Keep in Inbox", action: keep)
            if !agents.folders.isEmpty {
                Divider()
                Menu("Send To") { SendMenuItems(agents: agents, send: send) }
            }
        }
        .help("Click to copy it again")
    }
}
