import AppKit
import Captures
import SwiftUI

/// The middle pane when the sidebar has the inbox selected: every capture.
///
/// A capture lives in the database, not in the vault, so it carries no path.
/// The row therefore shows the section in place of a folder. The rows follow
/// the metrics of the file list, so one list does not read as another design.
struct InboxListView: View {

    // MARK: Properties

    @Bindable var model: AppModel
    /// The capture the detail pane shows.
    let selected: UUID?
    let selectNote: (Note) -> Void

    private var searching: Bool {
        !model.wikiQuery.trimmingCharacters(in: .whitespaces).isEmpty
    }

    /// Every capture, newest first. A search reads the text and the section.
    private var notes: [Note] {
        let query = model.wikiQuery.trimmingCharacters(in: .whitespaces)
        return model.store.notes
            .filter { query.isEmpty || ($0.text + " " + $0.section).localizedCaseInsensitiveContains(query) }
            .sorted { $0.modifiedAt > $1.modifiedAt }
    }

    var body: some View {
        VStack(spacing: 0) {
            header
            ScrollView {
                if notes.isEmpty {
                    Text(searching ? "No matching captures." : "No captures yet.")
                        .font(PiperTheme.ui(AppDefaults.FontSize.small))
                        .foregroundStyle(PiperTheme.secondary)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(16)
                } else {
                    LazyVStack(spacing: 0) {
                        ForEach(notes) { note in
                            Button { selectNote(note) } label: {
                                NoteCell(note: note, isSelected: note.id == selected)
                            }
                            .buttonStyle(.plain)
                            .focusEffectDisabled()
                            .accessibilityLabel(note.text)
                        }
                    }
                    .padding(.horizontal, 8)
                }
            }
            .scrollIndicators(.automatic)
        }
        .background(PiperTheme.page)
    }

    // MARK: Parts

    private var header: some View {
        VStack(alignment: .leading, spacing: 1) {
            Text(searching ? "Search Results" : "Inbox")
                .font(PiperTheme.ui(13, weight: .bold))
                .foregroundStyle(PiperTheme.ink)
            Text("\(notes.count) \(notes.count == 1 ? "capture" : "captures")")
                .font(PiperTheme.ui(11))
                .foregroundStyle(PiperTheme.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.leading, 16)
        .padding(.trailing, 10)
        .padding(.vertical, 8)
    }
}

/// One capture, drawn with the metrics of the timeline cell.
struct NoteCell: View {

    // MARK: Properties

    let note: Note
    var isSelected = false

    /// The first line carries the title. The rest carries the summary.
    private var lines: (title: String, rest: String) {
        let text = SummaryText.plain(note.text)
        guard let break_ = text.firstIndex(where: \.isNewline) else { return (text, "") }
        return (String(text[..<break_]), String(text[text.index(after: break_)...]))
    }

    private var date: String {
        if Date().timeIntervalSince(note.modifiedAt) < 24 * 60 * 60 {
            return note.modifiedAt.formatted(.relative(presentation: .named))
        }
        return note.modifiedAt.formatted(date: .abbreviated, time: .omitted)
    }

    var body: some View {
        let metrics = AppDefaults.Timeline.self
        let text = lines
        HStack(alignment: .top, spacing: 0) {
            Circle()
                .fill(note.isDone ? Color.clear : PiperTheme.accent)
                .frame(width: metrics.unreadCircleDimension, height: metrics.unreadCircleDimension)
                .padding(.top, 5)
                .padding(.trailing, metrics.unreadCircleMarginRight)
            VStack(alignment: .leading, spacing: 0) {
                Text(text.title)
                    .font(PiperTheme.ui(AppDefaults.FontSize.large, weight: .semibold))
                    .foregroundStyle(note.isDone ? PiperTheme.secondary : PiperTheme.ink)
                    .strikethrough(note.isDone)
                    .lineLimit(metrics.titleNumberOfLines)
                    .padding(.bottom, metrics.titleBottomMargin)
                if !text.rest.isEmpty {
                    Text(text.rest)
                        .font(PiperTheme.ui(AppDefaults.FontSize.large))
                        .foregroundStyle(PiperTheme.secondary)
                        .lineLimit(2)
                }
                HStack(alignment: .firstTextBaseline, spacing: metrics.dateMarginLeft) {
                    Text(note.section)
                        .font(PiperTheme.ui(AppDefaults.FontSize.small, weight: .bold))
                        .foregroundStyle(PiperTheme.secondary)
                        .lineLimit(1)
                    Spacer(minLength: metrics.dateMarginLeft)
                    Text(date)
                        .font(PiperTheme.ui(AppDefaults.FontSize.small, weight: .bold))
                        .foregroundStyle(PiperTheme.secondary)
                        .lineLimit(1)
                }
                .padding(.top, 3)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .multilineTextAlignment(.leading)
        .padding(.top, metrics.cellPadding.top)
        .padding(.leading, metrics.cellPadding.left)
        .padding(.bottom, metrics.cellPadding.bottom)
        .padding(.trailing, metrics.cellPadding.right)
        .frame(maxWidth: .infinity, alignment: .leading)
        .contentShape(Rectangle())
        .background(isSelected ? PiperTheme.rowSelection : .clear, in: RoundedRectangle(cornerRadius: 6))
    }
}
