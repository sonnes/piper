import AppKit
import Captures
import SwiftUI

/// One row of a list on the feed paper: a mark, the text, and a time.
///
/// The rows follow Mail and Reminders. A hairline that starts at the text
/// column parts two rows. The selected row has a round fill, in indigo while
/// the feed paper has the focus and in gray when it does not. A row under the
/// pointer has a faint fill, and its actions take the place of its time. A
/// row of Today also shows its actions while it is selected. A
/// row whose item is open as a reader paper shows a dashed slot and "on the
/// desk" in place of its time. The row flashes when its paper goes back, and
/// when a note lands under it.
struct PaperRow<Mark: View, Content: View, Actions: View>: View {
    /// The item that the row opens, for its slot and its flash.
    let item: PaperItem?
    /// The count of the notes under the row. The row flashes when it grows.
    var notes = 0
    let selected: Bool
    /// True when the selected row shows its actions too, so that no action
    /// needs the pointer.
    var actionsOnSelection = false
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
    private typealias Metrics = PaperRowMetrics

    private var lifted: Bool { item.map { marks?.isOpen($0) == true } ?? false }
    private var showsActions: Bool { (hovered || (actionsOnSelection && selected)) && Actions.self != EmptyView.self }

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
            .accessibilityElement(children: .contain)
    }

    private var flashID: UUID? {
        guard let item, let marks else { return nil }
        return marks.flashes(item)
    }

    /// The mark, the text, and the time are one element for VoiceOver. The
    /// actions stay separate buttons, so that VoiceOver and Full Keyboard
    /// Access reach each one.
    private var line: some View {
        HStack(alignment: .top, spacing: Metrics.rowSpacing) {
            HStack(alignment: .top, spacing: Metrics.rowSpacing) {
                mark().frame(width: Metrics.markColumn, height: Metrics.rowLineHeight)
                content()
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .environment(\.rowLifted, lifted)
                if !actionsShown { timeLabel }
            }
            .accessibilityElement(children: .combine)
            .accessibilityAddTraits(selected ? [.isButton, .isSelected] : .isButton)
            .accessibilityValue(lifted ? "On the desk" : "")
            .accessibilityAction(.default, action)
            if actionsShown {
                HStack(spacing: Metrics.rowActionSpacing) { actions() }
                    .frame(minHeight: Metrics.rowLineHeight)
                    .transition(.opacity)
            }
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
            PiperTheme.paperRule
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

    /// True when the actions take the place of the time.
    private var actionsShown: Bool { showsActions && (!lifted || actionsOnSelection) }

    private var timeLabel: some View {
        let text: String = lifted ? "on the desk" : time
        let weight: NSFont.Weight = lifted ? .medium : .regular
        let color: Color = lifted ? PiperTheme.brand : PiperTheme.paperMuted
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
        let hold = Metrics.flash * Metrics.flashHold
        DispatchQueue.main.asyncAfter(deadline: .now() + hold) {
            withAnimation(.easeOut(duration: Metrics.flash - hold)) { flashing = false }
        }
    }
}

extension PaperRow where Actions == EmptyView {
    /// A row without actions under the pointer.
    init(item: PaperItem?, notes: Int = 0, selected: Bool, time: String,
         action: @escaping () -> Void, @ViewBuilder mark: @escaping () -> Mark, @ViewBuilder content: @escaping () -> Content) {
        self.init(item: item, notes: notes, selected: selected, time: time, action: action,
                  mark: mark, content: content, actions: { EmptyView() })
    }
}

/// A round button at the end of a row under the pointer, with a symbol only.
struct RowAction: View {
    let symbol: String
    let title: String
    var tint: Color = PiperTheme.paperMuted
    let action: () -> Void

    @State private var hovered = false
    private typealias Metrics = PaperRowMetrics

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

/// The title of a row, in the one list title style of `PiperTheme.listTitle`.
struct PaperRowTitle: View {
    let text: Text
    var bold = false
    var done = false
    var lines = 2

    @Environment(\.rowLifted) private var lifted
    private typealias Metrics = PaperRowMetrics

    var body: some View {
        let heavy = bold && !lifted
        text
            .font(PiperTheme.listTitle(bold: heavy))
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
        HStack(spacing: PaperRowMetrics.metaSpacing) { content() }
            .font(PiperTheme.paperUI(.body))
            .foregroundStyle(PiperTheme.paperMuted)
            .lineLimit(1)
            .padding(.top, PaperRowMetrics.metaTopPadding)
    }
}

// MARK: - Marks

/// The circle of a capture, as in Reminders: a ring that turns indigo under
/// the pointer, or a filled indigo circle with a check when done.
struct TickMark: View {
    let done: Bool

    @State private var hovered = false

    var body: some View {
        let metrics = PaperRowMetrics.self
        ZStack {
            if done {
                Circle().fill(PiperTheme.indigo)
                Image(systemName: "checkmark").font(.system(size: metrics.tickGlyph, weight: .bold)).foregroundStyle(PiperTheme.onAccent)
            } else {
                Circle().strokeBorder(hovered ? PiperTheme.brand : PiperTheme.paperFaint, lineWidth: metrics.markLine)
            }
        }
        .frame(width: metrics.tickSize, height: metrics.tickSize)
        .onHover { hovered = $0 }
    }
}

/// The dot of an unread article, as in Mail.
struct UnreadDot: View {
    var body: some View {
        let metrics = PaperRowMetrics.self
        Circle()
            .fill(PiperTheme.brand)
            .frame(width: metrics.dotSize, height: metrics.dotSize)
            .accessibilityLabel("Unread")
    }
}

/// The sheet of a file: a page with a folded corner.
struct SheetMark: View {
    var body: some View {
        let metrics = PaperRowMetrics.self
        UnevenRoundedRectangle(topLeadingRadius: metrics.sheetMarkRadius, bottomLeadingRadius: metrics.sheetMarkRadius,
                               bottomTrailingRadius: metrics.sheetMarkRadius, topTrailingRadius: metrics.sheetMarkFoldRadius)
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

    private typealias Metrics = PaperRowMetrics

    var body: some View {
        let shown = notes.suffix(Metrics.rowNoteLimit)
        VStack(alignment: .leading, spacing: Metrics.rowNotesSpacing) {
            ForEach(Array(shown)) { note in
                Button { open(note) } label: {
                    VStack(alignment: .leading, spacing: Metrics.rowNoteSpacing) {
                        Text(Self.quote(of: note))
                            .font(PiperTheme.paperSerif(Metrics.quoteSize))
                            .foregroundStyle(PiperTheme.paperMuted)
                            .lineSpacing(Metrics.quoteLineSpacing).lineLimit(2)
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
            Text(title).foregroundStyle(PiperTheme.paperMuted)
            Spacer(minLength: PaperRowMetrics.trailingGap)
            if let action {
                Button(action.title, action: action.run).buttonStyle(.plain).foregroundStyle(PiperTheme.brand)
            }
        }
        .font(PiperTheme.paperUI(.body, weight: .semibold))
        .padding(PaperRowMetrics.groupHeaderPadding)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(PaperRowMetrics.groupHeaderFill)
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
            HStack(spacing: PaperRowMetrics.doneTodaySpacing) {
                Text(shown ? "Hide \(count) done today" : "\(count) done today")
                Spacer(minLength: 0)
            }
            .font(PiperTheme.paperUI(.body, weight: .medium))
            .foregroundStyle(PiperTheme.paperFaint)
            .padding(PaperRowMetrics.groupHeaderPadding)
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
        VStack(spacing: PaperRowMetrics.emptySpacing) {
            Image(systemName: symbol)
                .font(.system(size: PaperRowMetrics.emptySymbol, weight: .light))
                .foregroundStyle(PiperTheme.paperFaint)
                .padding(.bottom, PaperRowMetrics.emptySymbolGap)
                .accessibilityHidden(true)
            Text(title).font(PiperTheme.paperUI(.row, weight: .semibold)).foregroundStyle(PiperTheme.paperMuted)
            if let detail {
                Text(detail).font(PiperTheme.paperUI(.body)).foregroundStyle(PiperTheme.paperFaint)
            }
        }
        .multilineTextAlignment(.center)
        .padding(PaperRowMetrics.emptyPadding)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .allowsHitTesting(false)
    }
}

// MARK: - Metrics

/// A row of a list on the feed paper: a column for the mark, then the text
/// and the time. Today, the index, the folder tree, and the article list use
/// these values too.
enum PaperRowMetrics {
    static let rowRadius: CGFloat = 12
    static let rowPadding: CGFloat = 12
    static let listRowPadding = EdgeInsets(top: 10, leading: 14, bottom: 10, trailing: 20)
    static let listPadding = EdgeInsets(top: 4, leading: 12, bottom: 8, trailing: 12)
    static let markColumn: CGFloat = 24
    static let rowLineHeight: CGFloat = 26
    /// The space between the lines of a title, for a line height of 26.
    static let rowLineSpacing: CGFloat = 4
    static let rowSpacing: CGFloat = 10
    /// The least space between the text of a row and its count, time, or action.
    static let trailingGap: CGFloat = 8
    /// The meta line under the title of a row.
    static let metaSpacing: CGFloat = 5
    static let metaTopPadding: CGFloat = 1
    /// The quote of a note under a row.
    static let quoteSize: CGFloat = 15.5
    static let tickSize: CGFloat = 18
    static let tickGlyph: CGFloat = 9
    static let dotSize: CGFloat = 9
    static let markLine: CGFloat = 1.5
    static let sheetMark = NSSize(width: 12, height: 15)
    /// The corners of the sheet, and its folded corner at the top right.
    static let sheetMarkRadius: CGFloat = 2
    static let sheetMarkFoldRadius: CGFloat = 5
    static let slotDash: [CGFloat] = [4, 3]
    /// A group header, such as Today. It sticks to the top of the list while the list scrolls.
    static let groupHeaderPadding = EdgeInsets(top: 16, leading: 14, bottom: 6, trailing: 20)
    static let groupHeaderFill = PiperTheme.paper.opacity(0.94)
    /// The fold over the captures done today.
    static let doneTodaySpacing: CGFloat = 6
    /// The hairline between two rows starts at the text column, as in Mail.
    static let separatorInset = listRowPadding.leading + markColumn + rowSpacing
    static let separatorHeight: CGFloat = 0.5
    /// The fade of a row fill under the pointer.
    static let hoverFade: Double = 0.12
    /// The time of the flash of a row when its paper goes back.
    static let flash: Double = 1.4
    /// The part of the flash that holds the indigo before it fades.
    static let flashHold: Double = 0.3
    /// The trailing actions of a row under the pointer, in place of its time.
    static let rowActionSize: CGFloat = 28
    static let rowActionGlyph: CGFloat = 14
    static let rowActionSpacing: CGFloat = 2
    /// An empty list: a symbol over one line.
    static let emptySymbol: CGFloat = 34
    static let emptySpacing: CGFloat = 6
    /// The extra space under the symbol.
    static let emptySymbolGap: CGFloat = 6
    static let emptyPadding: CGFloat = 24
    /// The notes under a row: the last two, then a count of the others.
    static let rowNoteLimit = 2
    static let rowNotesPadding = EdgeInsets(top: 8, leading: 12, bottom: 2, trailing: 0)
    static let quoteBarWidth: CGFloat = 2
    /// The space between two notes, and between the quote and the words of the reader.
    static let rowNotesSpacing: CGFloat = 6
    static let rowNoteSpacing: CGFloat = 2
    /// The space between the lines of a quote.
    static let quoteLineSpacing: CGFloat = 4
}
