import Agents
import AppKit
import Captures
import Feeds
import SwiftUI
import Vault

/// The content of a reader paper: a header with the actions of the item,
/// and the item under it.
struct ReaderPaper: View {
    @Bindable var model: AppModel
    let item: PaperItem
    /// Called with the session that the first message of a new session started.
    let started: (AgentSession) -> Void
    let close: () -> Void

    @Environment(PaperLayout.self) private var layout
    private typealias Metrics = AppDefaults.Papers

    var body: some View {
        VStack(spacing: 0) {
            header
                .padding(shortNote != nil ? Metrics.noteHeaderPadding : Metrics.readerHeaderPadding)
                .frame(minHeight: Metrics.readerHeaderHeight)
                .background(WindowDragArea())
            content
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .opacity(layout.focused ? 1 : Metrics.restOpacity)
            if let note = shortNote { noteFoot(note) }
        }
        .background(PiperTheme.paper)
        // The title bar is hidden, so the header starts at the top edge.
        .ignoresSafeArea(.container, edges: .top)
    }

    /// The note of a note paper. A link capture is an article and has no foot.
    private var shortNote: Note? {
        guard case .note(let id) = item, let note = model.store.notes.first(where: { $0.id == id }), !note.isArticle else { return nil }
        return note
    }

    /// The foot of a note paper: the save state, and Mark as Done.
    private func noteFoot(_ note: Note) -> some View {
        HStack(spacing: 8) {
            Text("Saved as you type").foregroundStyle(PiperTheme.paperFaint)
            Spacer(minLength: 8)
            Button(note.isDone ? "Open Again" : "Mark as Done") { model.store.toggleDone(note.id) }
                .buttonStyle(.plain)
                .font(PiperTheme.paperUI(.body, weight: .medium))
                .foregroundStyle(PiperTheme.onAccent)
                .padding(.horizontal, 14).padding(.vertical, 8)
                .background(PiperTheme.indigo, in: Capsule())
                .help(note.isDone ? "Open the note again" : "Mark the note as done")
        }
        .font(PiperTheme.paperUI(.body))
        .padding(Metrics.noteFootPadding)
        .overlay(alignment: .top) { Rectangle().fill(PiperTheme.paperRule).frame(height: 1) }
    }

    // MARK: - Header

    @ViewBuilder private var header: some View {
        HStack(spacing: 6) {
            switch item {
            case .note(let id): noteHeader(model.store.notes.first { $0.id == id })
            case .article(let id): articleHeader(model.feeds.article(id))
            case .file: fileHeader
            case .session(let id): sessionHeader(model.agents.runner.session(id))
            case .newSession(let folder): label("New Session in " + URL(fileURLWithPath: folder).lastPathComponent)
            }
            PaperButton(title: "Put back", key: "esc", help: "Close the paper · Escape", action: close)
        }
        .font(PiperTheme.paperUI(.body, weight: .medium))
    }

    @ViewBuilder private func noteHeader(_ note: Note?) -> some View {
        if let note, note.isArticle {
            let host = note.articleURL.map(ArticleBadge.host) ?? note.section
            label(([host] + (note.reading?.minutes.map { ["\($0) min"] } ?? [])).joined(separator: " · "))
            PaperButton(title: note.isDone ? "Open Again" : "Mark as Done",
                        symbol: note.isDone ? "checkmark.circle.fill" : "checkmark.circle",
                        help: note.isDone ? "Open the link again" : "Mark the link as done") { model.store.toggleDone(note.id) }
        } else if let note {
            label(([note.section] + note.sources.prefix(1) + [RowTime.text(note.modifiedAt)]).joined(separator: " · "))
        } else {
            label("")
        }
    }

    @ViewBuilder private func articleHeader(_ article: Article?) -> some View {
        if let article {
            let feed = model.feeds.feed(article.feedID)
            let kept = URL(string: article.url).flatMap(model.store.article(for:)) != nil
            if let feed {
                SiteIcon(favicons: model.favicons, host: feed.host, title: feed.title,
                         index: model.feeds.feeds.firstIndex { $0.id == feed.id } ?? 0)
            }
            label([feed?.title, RowTime.text(article.date)].compactMap { $0 }.joined(separator: " · "))
            PaperButton(title: article.read ? "Unread" : "Read",
                        symbol: article.read ? "checkmark.circle.fill" : "checkmark.circle",
                        help: article.read ? "Mark as Unread (R)" : "Mark as Read (R)") {
                model.feeds.setRead(!article.read, [article])
            }
            PaperButton(title: article.starred ? "Starred" : "Star", symbol: article.starred ? "star.fill" : "star",
                        active: article.starred, help: article.starred ? "Remove Star (S)" : "Star (S)") {
                model.feeds.setStarred(!article.starred, article)
            }
            PaperButton(title: kept ? "Kept" : "Keep", symbol: "tray.and.arrow.down",
                        help: kept ? "Kept in Inbox" : "Keep in Inbox (I)") {
                guard let url = URL(string: article.url) else { return }
                model.store.saveArticle(url, title: article.title, source: feed?.title)
                model.feeds.setRead(true, [article])
            }
            .disabled(kept)
        } else {
            label("")
        }
    }

    @ViewBuilder private var fileHeader: some View {
        if let document = model.currentDocument {
            SheetMark()
            label(([model.vault.root.lastPathComponent] + document.folder.split(separator: "/").map(String.init) + [document.name])
                .joined(separator: " › "))
        } else {
            label("")
        }
        let workspace = model.workspace
        PaperButton(title: "", symbol: "chevron.left", help: "Back · Command-[") { model.navigate(-1) }
            .disabled(!workspace.history.indices.contains(workspace.position - 1))
        PaperButton(title: "", symbol: "chevron.right", help: "Forward · Command-]") { model.navigate(1) }
            .disabled(!workspace.history.indices.contains(workspace.position + 1))
    }

    @ViewBuilder private func sessionHeader(_ session: AgentSession?) -> some View {
        label(session?.title ?? "Session")
        if let session { SessionStateChip(session: session) }
    }

    private func label(_ text: String) -> some View {
        Text(text)
            .foregroundStyle(PiperTheme.paperFaint)
            .lineLimit(1).truncationMode(.middle)
            .frame(maxWidth: .infinity, alignment: .leading)
    }

    // MARK: - Content

    @ViewBuilder private var content: some View {
        switch item {
        case .note(let id):
            if let note = model.store.notes.first(where: { $0.id == id }) {
                NoteDetail(model: model, note: note).id(note.id)
            } else {
                EmptyPane(title: "Note Deleted", detail: "This note is no longer in Inbox.")
            }
        case .article(let id):
            if let article = model.feeds.article(id) {
                FeedArticleDetail(model: model, article: article).id(article.id)
            } else {
                EmptyPane(title: "Article Removed", detail: "This article is no longer in its feed.")
            }
        case .file:
            FilePaperContent(model: model)
        case .session(let id):
            if let session = model.agents.runner.session(id) {
                SessionPane(model: model, session: session, folder: session.folder, started: started)
            } else {
                EmptyPane(title: "Session Deleted")
            }
        case .newSession(let folder):
            SessionPane(model: model, session: nil, folder: folder, started: started)
        }
    }
}

/// A button in the header of a reader paper: a symbol, a title, or both, and
/// an optional key.
struct PaperButton: View {
    let title: String
    var symbol: String?
    var key: String?
    var active = false
    let help: String
    let action: () -> Void

    @State private var hovered = false
    @Environment(\.isEnabled) private var enabled

    var body: some View {
        Button(action: action) {
            HStack(spacing: 6) {
                if let symbol { Image(systemName: symbol).font(.system(size: 14)) }
                if !title.isEmpty { Text(title).lineLimit(1).fixedSize() }
                if let key { KeyCap(text: key) }
            }
            .foregroundStyle(!enabled ? PiperTheme.paperFaint : active ? PiperTheme.brand : PiperTheme.paperMuted)
            .padding(.horizontal, 10).padding(.vertical, 5)
            .background(hovered && enabled ? PiperTheme.paperTint : .clear,
                        in: RoundedRectangle(cornerRadius: AppDefaults.Papers.rowRadius, style: .continuous))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { hovered = $0 }
        .help(help)
        .accessibilityLabel(title.isEmpty ? help : title)
    }
}

/// The open file of the model, in the editor, a text view, or Quick Look. It
/// holds the reading preferences, which belong to the view.
struct FilePaperContent: View {
    @Bindable var model: AppModel

    @AppStorage(AppDefaults.Key.readerSize) private var readerSize = AppDefaults.Reader.defaultSize
    @AppStorage(AppDefaults.Key.readerTheme) private var readerTheme = WikiReadingTheme.paper
    @AppStorage(AppDefaults.Key.readerFont) private var readerFont = AppDefaults.Reader.defaultFont
    @AppStorage(AppDefaults.Key.readerAppearance) private var readerAppearance = WikiReadingAppearance.system
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        Group {
            if let document = model.currentDocument {
                if FilePresentation(document) == .markdown, let session = model.editor {
                    VStack(spacing: 0) {
                        EditorBanner(model: model, session: session)
                        EditorPane(page: model.editorPage,
                                   request: EditorPane.request(for: session, model: model, source: model.showsFileSource),
                                   session: session, theme: theme, anchorRequest: model.anchorRequest,
                                   notes: model.fileNotes(document))
                    }
                    .background(paper)
                } else if model.showsFileSource, let source = FilePresentation.sourceText(for: document) {
                    PlainTextPreview(text: source)
                } else {
                    FilePreview(model: model, document: document)
                }
            } else {
                EmptyPane(title: "No File")
            }
        }
        .overlay(alignment: .bottom) {
            if let document = model.currentDocument, FilePresentation.sourceText(for: document) != nil {
                TabIsland(showsSource: $model.showsFileSource, cardPresented: model.sessionPresentation == .card)
            }
        }
    }

    private var theme: EditorTheme {
        EditorTheme(theme: readerTheme.rawValue, font: readerFont.rawValue, size: readerSize,
                    appearance: readerAppearance.rawValue)
    }

    private var paper: Color {
        Color(nsColor: readerTheme.background(dark: (readerAppearance.colorScheme ?? colorScheme) == .dark))
    }
}
