import AppKit
import Captures
import SwiftUI

/// A capture in a reader paper: a link capture in the Reader, Web, and Notes tabs,
/// or any other note in an editor.
///
/// The session of the note shows in the session card, not in this pane.
struct NoteDetail: View {

    // MARK: Properties

    @Bindable var model: AppModel
    let note: Note
    @State private var session: CaptureEditSession?
    @State private var pendingSave: Task<Void, Never>?
    /// True when the note was a link capture as the pane opened it. The pane
    /// keeps this mode, so a note that the reader edits down to one link
    /// stays in the editor while they type.
    @State private var opensAsArticle: Bool

    /// The page of a link capture. Nil for a note that is not a link capture.
    private var articleURL: URL? { opensAsArticle ? note.articleURL : nil }

    init(model: AppModel, note: Note) {
        self.model = model
        self.note = note
        _opensAsArticle = State(initialValue: note.isArticle)
    }

    var body: some View {
        Group {
            if let articleURL {
                switch model.articleTab(for: note) {
                case .reader:
                    ArticleReader(model: model, note: note, url: articleURL, showWebPage: { model.chooseArticleTab(.web, for: note) })
                case .web:
                    NoteWebReader(url: articleURL) { text, title, url in
                        model.store.add(text, source: title, sourceURL: url.absoluteString,
                                        to: "Inbox", interpretSection: false)
                    }
                case .notes:
                    ArticleNotebook(model: model, note: note, url: articleURL)
                }
            } else {
                page
            }
        }
        .background(PiperTheme.paper)
        .overlay(alignment: .bottom) {
            if let articleURL {
                TabIsland(selection: Binding(get: { model.articleTab(for: note) }, set: { model.chooseArticleTab($0, for: note) }),
                          cardPresented: model.sessionPresentation == .card)
            }
        }
        .onAppear {
            if articleURL == nil {
                session = model.editCapture(note)
            } else {
                model.keepArticleTab(for: note)
            }
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

    /// The text of a note on its paper, in the sans serif of the text that
    /// the reader wrote. The grip over it names the section and the source.
    private var page: some View {
        VStack(alignment: .leading, spacing: 0) {
            if let session {
                NoteTextEditor(text: Binding(get: { session.text }, set: { text in
                    session.text = text
                    scheduleSave()
                }), font: CaptureText.looksLikeCode(note.text)
                    ? PiperTheme.manuscript(size: AppDefaults.Reader.codeFontSize)
                    : PiperTheme.paperUINS(.reading), paper: true)
                .padding(.horizontal, -5)
                .accessibilityLabel("Note text")
            }
            if let error = model.store.errorMessage, session?.hasChanges == true {
                Text(error).font(PiperTheme.paperUI(.body)).foregroundStyle(PiperTheme.danger)
                    .textSelection(.enabled)
                    .padding(.vertical, 8)
            }
        }
        .padding(AppDefaults.Papers.noteBodyPadding)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
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
    /// True on a paper: zinc ink, an indigo caret, and an indigo selection, with the line height of the paper.
    var paper = false

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
        let ink = paper ? PiperTheme.paperInkNS : PiperTheme.inkNS
        editor.textColor = ink
        editor.insertionPointColor = paper ? PiperTheme.brandNS : PiperTheme.accentNS
        editor.selectedTextAttributes = [.backgroundColor: paper ? PiperTheme.paperSelectionNS : PiperTheme.selectionNS,
                                         .foregroundColor: ink]
        editor.defaultParagraphStyle = {
            let style = NSMutableParagraphStyle()
            style.lineSpacing = paper ? AppDefaults.Papers.noteLineSpacing : 3
            return style
        }()
        editor.typingAttributes[.paragraphStyle] = editor.defaultParagraphStyle
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
