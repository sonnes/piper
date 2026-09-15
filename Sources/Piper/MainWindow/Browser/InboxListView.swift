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
            List(selection: Binding<UUID?>(get: { selected }, set: { id in
                if let note = notes.first(where: { $0.id == id }) { selectNote(note) }
            })) {
                ForEach(notes) { note in
                    NoteCell(note: note)
                        .tag(note.id)
                        .listRowSeparator(.hidden)
                        .listRowInsets(EdgeInsets())
                        .accessibilityElement(children: .combine)
                        .accessibilityLabel(note.text)
                }
            }
            .listStyle(.inset)
            .scrollContentBackground(.hidden)
            .overlay {
                if notes.isEmpty {
                    Text(searching ? "No matching captures" : "No captures yet")
                        .font(PiperTheme.ui(AppDefaults.FontSize.small))
                        .foregroundStyle(.secondary)
                }
            }
            .accessibilityLabel("Captures")
        }
        .background(PiperTheme.page)
    }

    // MARK: Parts

    private var header: some View {
        VStack(alignment: .leading, spacing: 1) {
            Text(searching ? "Search Results" : "Inbox")
                .font(PiperTheme.ui(13, weight: .bold))
                .foregroundStyle(PiperTheme.ink)
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

    /// The first line carries the title. The rest carries the summary.
    private var lines: (title: String, rest: String) {
        let lines = note.text.split(maxSplits: 1, whereSeparator: \.isNewline)
        return (SummaryText.plain(String(lines.first ?? "")),
                lines.count > 1 ? SummaryText.plain(String(lines[1])) : "")
    }

    private var date: String {
        if Date().timeIntervalSince(note.modifiedAt) < 24 * 60 * 60 {
            return note.modifiedAt.formatted(.relative(presentation: .named))
        }
        return note.modifiedAt.formatted(date: .abbreviated, time: .omitted)
    }

    var body: some View {
        TimelineRow(title: lines.title, summary: lines.rest, source: note.section,
                    date: date, showsDot: !note.isDone, isDone: note.isDone)
    }
}
