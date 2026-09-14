import AppKit
import Captures
import SwiftUI

/// The detail pane when the sidebar has the inbox selected.
///
/// A capture is short and it carries no file, so the pane shows the text and
/// the places it came from. Editing opens the note editor, which is the one
/// place that writes a capture.
struct NoteDetail: View {

    // MARK: Properties

    @Bindable var model: AppModel
    let note: Note

    private var date: String {
        note.modifiedAt.formatted(date: .long, time: .shortened)
    }

    var body: some View {
        VStack(spacing: 0) {
            header
            ScrollView {
                Text(note.text)
                    .font(PiperTheme.ui(15))
                    .lineSpacing(5)
                    .textSelection(.enabled)
                    .frame(maxWidth: 640, alignment: .leading)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, 32)
                    .padding(.vertical, 24)
            }
            if !note.sources.isEmpty { sources }
        }
        .background(PiperTheme.page)
    }

    // MARK: Parts

    private var header: some View {
        VStack(spacing: 0) {
            HStack(spacing: 10) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(note.section)
                        .font(PiperTheme.ui(13, weight: .bold))
                        .foregroundStyle(PiperTheme.feedLink)
                    Text(date)
                        .font(PiperTheme.ui(12))
                        .foregroundStyle(PiperTheme.secondary)
                }
                Spacer(minLength: 12)
                Button(note.isDone ? "Reopen" : "Mark as Done") { model.store.toggleDone(note.id) }
                    .buttonStyle(PiperButtonStyle())
                Button("Edit") { model.openNoteEditor?(note) }
                    .buttonStyle(PiperButtonStyle(prominent: true))
            }
            .padding(.horizontal, 32)
            .frame(height: 68)
            Rule()
        }
    }

    private var sources: some View {
        VStack(spacing: 0) {
            Rule()
            HStack(spacing: 8) {
                Text(note.sources.joined(separator: " · "))
                    .lineLimit(1)
                    .truncationMode(.middle)
                Spacer(minLength: 8)
                if let first = note.sourceURLs.first, let url = URL(string: first),
                   ["http", "https"].contains(url.scheme?.lowercased() ?? "") {
                    Button("Open Source") { NSWorkspace.shared.open(url) }
                        .buttonStyle(.plain)
                        .foregroundStyle(PiperTheme.accent)
                }
            }
            .font(PiperTheme.ui(11))
            .foregroundStyle(PiperTheme.secondary)
            .padding(.horizontal, 10)
            .frame(height: 24)
            .background(PiperTheme.statusBar)
        }
    }
}
