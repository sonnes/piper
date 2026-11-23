import AppKit
import Captures
import SwiftUI

/// One row of a list on the feed paper: a mark, the text, and a time.
///
/// The rows follow Mail and Reminders. A hairline that starts at the text
/// column parts two rows. The selected row has a round fill, in indigo while
/// the feed paper has the focus and in gray when it does not. A row under the
/// pointer has a faint fill, and its actions take the place of its time. A
/// row whose item is open as a reader paper shows a dashed slot and "on the
/// desk" in place of its time. The row flashes when its paper goes back, and
/// when a note lands under it.
struct PaperRow<Mark: View, Content: View, Actions: View>: View {
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
    /// The buttons that show at the end of the row while the pointer is over it.
    @ViewBuilder let actions: () -> Actions

    @Environment(DeskMarks.self) private var marks: DeskMarks?
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var flashing = false
    @State private var hovered = false
    private typealias Metrics = AppDefaults.Papers

    private var lifted: Bool { openOnDesk || (item.map { marks?.isOpen($0) == true } ?? false) }
    private var showsActions: Bool { hovered && Actions.self != EmptyView.self }

    var body: some View {
        decorated
            .clipShape(RoundedRectangle(cornerRadius: Metrics.rowRadius, style: .continuous))
            .background(alignment: .bottom) { separator }
            .contentShape(Rectangle())
            .onTapGesture(perform: action)
            .onHover { hovered = $0 }
            .animation(reduceMotion ? nil : .easeOut(duration: Metrics.hoverFade), value: hovered)
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
            trailing
        }
        .padding(Metrics.listRowPadding)
    }

    private var decorated: some View {
        line
            .background(background)
            .overlay { slot }
    }

    /// The hairline under the row. It hides beside a fill, as in Mail.
    @ViewBuilder private var separator: some View {
        if !selected && !hovered && !lifted {
            PiperTheme.separator
                .frame(height: Metrics.separatorHeight)
                .padding(.leading, Metrics.separatorInset)
                .padding(.trailing, Metrics.listRowPadding.trailing)
                .accessibilityHidden(true)
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

    /// The time, or the actions while the pointer is over the row.
    @ViewBuilder private var trailing: some View {
        if showsActions && !lifted {
            HStack(spacing: 2) { actions() }
                .frame(minHeight: Metrics.rowLineHeight)
                .transition(.opacity)
        } else {
            timeLabel
        }
    }

    private var timeLabel: some View {
        let text: String = lifted ? "on the desk" : time
        let weight: NSFont.Weight = lifted ? .medium : .regular
        let color: Color = lifted ? PiperTheme.brand : PiperTheme.secondaryLabel
        return Text(text)
            .font(PiperTheme.paperUI(.body, weight: weight))
            .foregroundStyle(color)
            .monospacedDigit().lineLimit(1).fixedSize()
            .frame(minHeight: Metrics.rowLineHeight)
    }

    private var background: some View {
        ZStack {
            PiperTheme.rowFill(selected: selected, focused: marks?.feedFocused == true, hovered: hovered)
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

extension PaperRow where Actions == EmptyView {
    /// A row without actions under the pointer.
    init(item: PaperItem?, openOnDesk: Bool = false, notes: Int = 0, selected: Bool, time: String,
         action: @escaping () -> Void, @ViewBuilder mark: @escaping () -> Mark, @ViewBuilder content: @escaping () -> Content) {
        self.init(item: item, openOnDesk: openOnDesk, notes: notes, selected: selected, time: time, action: action,
                  mark: mark, content: content, actions: { EmptyView() })
    }
}

/// A round button at the end of a row under the pointer, with a symbol only.
struct RowAction: View {
    let symbol: String
    let title: String
    var tint: Color = PiperTheme.secondaryLabel
    let action: () -> Void

    @State private var hovered = false
    private typealias Metrics = AppDefaults.Papers

    var body: some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.system(size: Metrics.rowActionGlyph, weight: .medium))
                .foregroundStyle(tint)
                .frame(width: Metrics.rowActionSize, height: Metrics.rowActionSize)
                .background(hovered ? PiperTheme.rowHover : .clear, in: Circle())
                .contentShape(Circle())
        }
        .buttonStyle(.plain)
        .onHover { hovered = $0 }
        .help(title)
        .accessibilityLabel(title)
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
            .foregroundStyle(PiperTheme.secondaryLabel)
            .lineLimit(1)
            .padding(.top, 1)
    }
}

// MARK: - Marks

/// The circle of a capture, as in Reminders: a ring that turns indigo under
/// the pointer, or a filled indigo circle with a check when done.
struct TickMark: View {
    let done: Bool

    @State private var hovered = false

    var body: some View {
        let metrics = AppDefaults.Papers.self
        ZStack {
            if done {
                Circle().fill(PiperTheme.indigo)
                Image(systemName: "checkmark").font(.system(size: 9, weight: .bold)).foregroundStyle(PiperTheme.onAccent)
            } else {
                Circle().strokeBorder(hovered ? PiperTheme.brand : PiperTheme.tertiaryLabel, lineWidth: metrics.markLine)
            }
        }
        .frame(width: metrics.tickSize, height: metrics.tickSize)
        .onHover { hovered = $0 }
    }
}

/// The dot of an article, as in Mail: an indigo dot while unread, and no dot once read.
struct UnreadDot: View {
    let unread: Bool

    var body: some View {
        let metrics = AppDefaults.Papers.self
        Circle()
            .fill(unread ? PiperTheme.brand : .clear)
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

/// A group header in a list of the feed paper, such as Today. In a list
/// with pinned section headers, it sticks to the top while the list scrolls,
/// on the color of the paper.
struct PaperGroupHeader: View {
    let title: String
    var action: (title: String, run: () -> Void)?

    var body: some View {
        HStack {
            Text(title).foregroundStyle(PiperTheme.secondaryLabel)
            Spacer(minLength: 8)
            if let action {
                Button(action.title, action: action.run).buttonStyle(.plain).foregroundStyle(PiperTheme.brand)
            }
        }
        .font(PiperTheme.paperUI(.body, weight: .semibold))
        .padding(AppDefaults.Papers.groupHeaderPadding)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(PiperTheme.paper.opacity(0.94))
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

/// The empty state of a list, as in the Apple apps: a symbol, a title, and one line.
struct PaperEmpty: View {
    var symbol = "tray"
    let title: String
    var detail: String?

    var body: some View {
        VStack(spacing: 6) {
            Image(systemName: symbol)
                .font(.system(size: AppDefaults.Papers.emptySymbol, weight: .light))
                .foregroundStyle(PiperTheme.tertiaryLabel)
                .padding(.bottom, 6)
                .accessibilityHidden(true)
            Text(title).font(PiperTheme.paperUI(.row, weight: .semibold)).foregroundStyle(PiperTheme.secondaryLabel)
            if let detail {
                Text(detail).font(PiperTheme.paperUI(.body)).foregroundStyle(PiperTheme.tertiaryLabel)
            }
        }
        .multilineTextAlignment(.center)
        .padding(24)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .allowsHitTesting(false)
    }
}

/// One copy in the clipboard list of the feed paper. Under the pointer, the
/// row shows Keep and Copy in place of its time.
struct PaperClipboardRow: View {
    let entry: ClipboardEntry
    let keep: () -> Void
    let copy: () -> Void
    let agents: FolderAgents
    let send: (FolderAgents.Action?) -> Void

    var body: some View {
        PaperRow(item: nil, selected: false, time: RowTime.text(entry.copiedAt), action: copy) {
            Image(systemName: "doc.on.clipboard")
                .font(.system(size: 14))
                .foregroundStyle(PiperTheme.tertiaryLabel)
        } content: {
            VStack(alignment: .leading, spacing: 2) {
                PaperRowTitle(text: Text(entry.text.replacingOccurrences(of: "\n", with: " ")), lines: 2)
                if let source = entry.source {
                    PaperRowMeta { Text(source) }
                }
            }
        } actions: {
            RowAction(symbol: "tray.and.arrow.down", title: "Keep in Inbox", tint: PiperTheme.brand, action: keep)
            RowAction(symbol: "doc.on.doc", title: "Copy", action: copy)
        }
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
