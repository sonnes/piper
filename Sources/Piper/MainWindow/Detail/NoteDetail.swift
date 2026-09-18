import AppKit
import Captures
import SwiftUI

/// The Inbox detail pane: one note that the reader edits in place, or the web
/// page that the note links to.
struct NoteDetail: View {

    // MARK: Properties

    @Bindable var model: AppModel
    let note: Note
    @State private var session: CaptureEditSession?
    @State private var selectedURL: URL?
    @State private var pendingSave: Task<Void, Never>?

    private var links: CaptureLinks { CaptureLinks(note.text) }

    private var dateLine: String {
        let date = note.modifiedAt.formatted(date: .long, time: .shortened)
        return note.isDone ? date + " · Done" : date
    }

    var body: some View {
        Group {
            if let selectedURL {
                NoteWebReader(url: selectedURL, showNote: { self.selectedURL = nil }) { text, title, url in
                    model.store.add(text, source: title, sourceURL: url.absoluteString,
                                    to: "Inbox", interpretSection: false)
                }
            } else {
                page
            }
        }
        .background(PiperTheme.page)
        .onAppear {
            session = model.editCapture(note)
            // A note with a session opens on its page, so the reader sees the session.
            if model.agents.latestSession(for: note) == nil { selectedURL = links.standaloneURL }
        }
        .onDisappear(perform: finish)
        .onChange(of: note.text) { _, text in
            // A change from the panel or a merge replaces the text under the editor.
            guard let session, !session.hasChanges, session.note.text != text else { return }
            session.note = note
            session.text = text
        }
    }

    // MARK: Parts

    private var page: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text(dateLine)
                .font(PiperTheme.ui(11))
                .foregroundStyle(PiperTheme.secondary)
                .frame(maxWidth: .infinity)
                .padding(.top, AppDefaults.Reader.topInset)
            ForEach(links.urls.prefix(3), id: \.self) { url in
                LinkCard(url: url, open: { selectedURL = url })
                    .padding(.top, 12)
            }
            if let session {
                NoteTextEditor(text: Binding(get: { session.text }, set: { text in
                    session.text = text
                    scheduleSave()
                }), font: CaptureText.looksLikeCode(note.text)
                    ? PiperTheme.manuscript(size: AppDefaults.Reader.codeFontSize)
                    : PiperTheme.uiNS(AppDefaults.Reader.noteFontSize))
                .padding(.top, 12)
                .padding(.horizontal, -5)
                .accessibilityLabel("Note text")
            }
            if let error = model.store.errorMessage, session?.hasChanges == true {
                Text(error).font(PiperTheme.ui(11)).foregroundStyle(PiperTheme.danger)
                    .textSelection(.enabled)
                    .padding(.vertical, 8)
            }
            if !note.sources.isEmpty {
                Text("From " + note.sources.joined(separator: ", "))
                    .font(PiperTheme.ui(11)).foregroundStyle(PiperTheme.secondary)
                    .lineLimit(1).truncationMode(.middle)
                    .padding(.vertical, 10)
            }
            if let session = model.agents.latestSession(for: note) {
                SessionPane(model: model, session: session, folder: session.folder)
                    .frame(maxHeight: .infinity)
                    .overlay(alignment: .top) { Rule() }
            }
        }
        .frame(maxWidth: AppDefaults.Reader.columnWidth, alignment: .leading)
        .padding(.horizontal, AppDefaults.Reader.horizontalInset)
        .frame(maxWidth: .infinity)
    }

    // MARK: Saving

    /// Saves shortly after the reader stops typing.
    private func scheduleSave() {
        pendingSave?.cancel()
        pendingSave = Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(600))
            guard !Task.isCancelled, let session else { return }
            model.saveCaptureEdit(session)
        }
    }

    private func finish() {
        pendingSave?.cancel()
        guard let session else { return }
        if session.hasChanges, !session.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            model.saveCaptureEdit(session)
        }
        model.captureEdits.removeValue(forKey: session.id)
    }
}

/// The editable text of a note.
///
/// SwiftUI's `TextEditor` follows the system setting for smart quotes and
/// dashes, and that setting changes code. This view turns the substitutions off.
struct NoteTextEditor: NSViewRepresentable {
    @Binding var text: String
    let font: NSFont

    func makeCoordinator() -> Coordinator { Coordinator(self) }

    func makeNSView(context: Context) -> NSScrollView {
        let scroll = NSTextView.scrollableTextView()
        scroll.drawsBackground = false
        scroll.hasHorizontalScroller = false
        scroll.autohidesScrollers = true
        scroll.scrollerStyle = .overlay
        guard let editor = scroll.documentView as? NSTextView else { return scroll }
        editor.isRichText = false
        editor.importsGraphics = false
        editor.drawsBackground = false
        editor.allowsUndo = true
        editor.usesFindBar = true
        editor.isAutomaticQuoteSubstitutionEnabled = false
        editor.isAutomaticDashSubstitutionEnabled = false
        editor.isAutomaticTextReplacementEnabled = false
        editor.isAutomaticSpellingCorrectionEnabled = false
        editor.textColor = PiperTheme.inkNS
        editor.insertionPointColor = PiperTheme.accentNS
        editor.selectedTextAttributes = [.backgroundColor: PiperTheme.selectionNS, .foregroundColor: PiperTheme.inkNS]
        editor.defaultParagraphStyle = {
            let style = NSMutableParagraphStyle()
            style.lineSpacing = 3
            return style
        }()
        editor.font = font
        editor.string = text
        editor.delegate = context.coordinator
        editor.setAccessibilityLabel("Note text")
        return scroll
    }

    func updateNSView(_ scroll: NSScrollView, context: Context) {
        context.coordinator.parent = self
        guard let editor = scroll.documentView as? NSTextView else { return }
        if editor.string != text {
            editor.string = text
            editor.undoManager?.removeAllActions()
        }
        if editor.font != font {
            editor.font = font
            editor.typingAttributes[.font] = font
        }
    }

    final class Coordinator: NSObject, NSTextViewDelegate {
        var parent: NoteTextEditor
        init(_ parent: NoteTextEditor) { self.parent = parent }

        func textDidChange(_ notification: Notification) {
            guard let editor = notification.object as? NSTextView else { return }
            parent.text = editor.string
        }
    }
}

/// A web link in a note, with a button that opens it in the reader.
private struct LinkCard: View {
    let url: URL
    let open: () -> Void

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: "globe")
                .font(.system(size: 16))
                .foregroundStyle(PiperTheme.secondary)
                .frame(width: 32, height: 32)
                .background(PiperTheme.card, in: RoundedRectangle(cornerRadius: 8))
                .overlay(RoundedRectangle(cornerRadius: 8).strokeBorder(PiperTheme.rule, lineWidth: 0.5))
            VStack(alignment: .leading, spacing: 1) {
                Text(url.host() ?? url.absoluteString)
                    .font(PiperTheme.ui(13, weight: .semibold))
                Text(url.path().isEmpty ? url.absoluteString : url.path())
                    .font(PiperTheme.ui(12)).foregroundStyle(PiperTheme.secondary)
                    .lineLimit(1).truncationMode(.middle)
            }
            Spacer(minLength: 8)
            Button("Open Reader", action: open)
            Button { NSWorkspace.shared.open(url) } label: { Image(systemName: "safari") }
                .buttonStyle(.borderless)
                .help("Open in Browser").accessibilityLabel("Open in Browser")
        }
        .padding(.horizontal, 14).padding(.vertical, 10)
        .background(PiperTheme.panel, in: RoundedRectangle(cornerRadius: PiperTheme.cardRadius))
        .accessibilityElement(children: .contain)
    }
}
