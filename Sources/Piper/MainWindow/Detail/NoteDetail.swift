import AppKit
import Captures
import SwiftUI

/// The Inbox detail pane: a link capture in the Reader, Web, and Notes tabs,
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

    private var dateLine: String {
        let date = note.modifiedAt.formatted(date: .long, time: .shortened)
        return note.isDone ? date + " · Done" : date
    }

    var body: some View {
        Group {
            if let articleURL {
                switch model.articleTab {
                case .reader:
                    ArticleReader(model: model, note: note, url: articleURL, showWebPage: { model.articleTab = .web })
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
        .background(PiperTheme.page)
        .overlay(alignment: .bottom) {
            if articleURL != nil {
                TabIsland(selection: $model.articleTab, cardPresented: model.sessionPresentation == .card)
            }
        }
        .onAppear {
            if articleURL == nil { session = model.editCapture(note) }
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
