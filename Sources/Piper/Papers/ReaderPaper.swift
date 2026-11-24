import Agents
import AppKit
import Captures
import Feeds
import PiperCore
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
        guard case .note = item, !item.isArticle(in: model) else { return nil }
        return item.note(in: model)
    }

    /// The foot of a note paper: the save state, and Mark as Done.
    private func noteFoot(_ note: Note) -> some View {
        HStack(spacing: 8) {
            Label("Saved as you type", systemImage: "checkmark.icloud")
                .labelStyle(.titleAndIcon)
                .foregroundStyle(PiperTheme.paperFaint)
            Spacer(minLength: 8)
            Button { toggleDone(note) } label: {
                Label(note.isDone ? "Open Again" : "Mark as Done",
                      systemImage: note.isDone ? "arrow.uturn.backward" : "checkmark")
                    .font(PiperTheme.paperUI(.body, weight: .semibold))
                    .foregroundStyle(PiperTheme.onAccent)
                    .padding(.horizontal, 14).frame(height: Metrics.toolbarHeight)
                    .background(PiperTheme.indigo, in: Capsule())
                    .contentShape(Capsule())
            }
            .buttonStyle(PressStyle())
            .help(note.isDone ? "Open the note again" : "Mark the note as done")
        }
        .font(PiperTheme.paperUI(.body))
        .padding(Metrics.noteFootPadding)
        .background(WindowDragArea())
        .overlay(alignment: .top) {
            PiperTheme.paperRule.frame(height: PaperRowMetrics.separatorHeight)
                .padding(.horizontal, Metrics.noteFootPadding.leading)
        }
    }

    // MARK: - Header

    /// The header: what the paper shows at the left, and a floating toolbar
    /// of symbols at the right, as in the Apple apps.
    @ViewBuilder private var header: some View {
        HStack(spacing: 8) {
            switch item {
            case .note(let id): noteHeader(model.store.notes.first { $0.id == id })
            case .article(let id): articleHeader(model.feeds.article(id))
            case .file: fileHeader
            case .session(let id): sessionHeader(model.agents.runner.session(id))
            case .newSession(let folder):
                label("New Session in " + URL(fileURLWithPath: folder).lastPathComponent)
                PaperToolbar { closeButton }
            }
        }
        .font(PiperTheme.paperUI(.body, weight: .medium))
    }

    private func toggleDone(_ note: Note) {
        do { try model.store.toggleDone(note.id) } catch { model.messages.report(error) }
    }

    private var closeButton: some View {
        PaperButton(title: "Put Back", symbol: "xmark", help: "Put the paper back · Escape", action: close)
    }

    @ViewBuilder private func noteHeader(_ note: Note?) -> some View {
        if let note, note.isArticle {
            let host = note.articleURL.flatMap(Site.init)?.key ?? note.section
            label(([host] + (note.reading?.minutes.map { ["\($0) min"] } ?? [])).joined(separator: " · "))
            PaperToolbar {
                PaperButton(title: note.isDone ? "Open Again" : "Mark as Done",
                            symbol: note.isDone ? "checkmark.circle.fill" : "checkmark.circle", active: note.isDone,
                            help: note.isDone ? "Open the link again" : "Mark the link as done") { toggleDone(note) }
                closeButton
            }
        } else if let note {
            label(([note.section] + note.sources.prefix(1) + [RowTime.text(note.modifiedAt)]).joined(separator: " · "))
            PaperToolbar { closeButton }
        } else {
            label("")
            PaperToolbar { closeButton }
        }
    }

    @ViewBuilder private func articleHeader(_ article: Article?) -> some View {
        if let article {
            let feed = model.feeds.feed(article.feedID)
            let kept = model.articleActions.isKept(article)
            if let feed {
                SiteIcon(favicons: model.favicons, host: feed.host, title: feed.title)
            }
            label([feed?.title, RowTime.text(article.date)].compactMap { $0 }.joined(separator: " · "))
            PaperToolbar {
                PaperButton(title: kept ? "Kept" : "Keep", symbol: kept ? "star.fill" : "star", tint: PiperTheme.star,
                            help: kept ? "Kept" : "Keep · K") {
                    model.articleActions.keep([article])
                }
                .disabled(kept)
                PaperToolbarDivider()
                closeButton
            }
        } else {
            label("")
            PaperToolbar { closeButton }
        }
    }

    @ViewBuilder private var fileHeader: some View {
        if let document = model.files.currentDocument {
            SheetMark()
            label(([model.library.vault.root.lastPathComponent] + document.folder.split(separator: "/").map(String.init) + [document.name])
                .joined(separator: " › "))
        } else {
            label("")
        }
        let workspace = model.files.workspace
        PaperToolbar {
            PaperButton(title: "Back", symbol: "chevron.left", help: "Back · Command-[") { model.files.navigate(-1) }
                .disabled(!workspace.history.indices.contains(workspace.position - 1))
            PaperButton(title: "Forward", symbol: "chevron.right", help: "Forward · Command-]") { model.files.navigate(1) }
                .disabled(!workspace.history.indices.contains(workspace.position + 1))
            PaperToolbarDivider()
            closeButton
        }
    }

    @ViewBuilder private func sessionHeader(_ session: AgentSession?) -> some View {
        label(session?.title ?? "Session")
        if let session { SessionStateChip(session: session) }
        PaperToolbar { closeButton }
    }

    private func label(_ text: String) -> some View {
        Text(text)
            .foregroundStyle(PiperTheme.paperMuted)
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
                EmptyPane(title: "Note Deleted", detail: "This note was deleted.")
            }
        case .article(let id):
            if let article = model.feeds.article(id) {
                FeedArticleDetail(model: model, article: article).id(article.id)
            } else {
                EmptyPane(title: "Article Removed", detail: "This article is no longer in its feed.")
            }
        case .file:
            FilePaperContent(files: model.files, cardPresented: model.sessionPresentation == .card)
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

/// The floating toolbar of a reader paper: a capsule of symbols on a
/// material, with a thin edge and two soft shadows.
struct PaperToolbar<Content: View>: View {
    @ViewBuilder let content: () -> Content

    private typealias Metrics = ReaderPaper.Metrics

    var body: some View {
        HStack(spacing: 0) { content() }
            .padding(Metrics.toolbarInset)
            .frame(height: Metrics.toolbarHeight + 2 * Metrics.toolbarInset)
            .background(.regularMaterial, in: Capsule())
            .overlay(Capsule().strokeBorder(PiperTheme.barEdge, lineWidth: 0.5))
            .shadow(color: PiperTheme.barContactShadow, radius: 1, y: 0.5)
            .shadow(color: PiperTheme.barSoftShadow, radius: 8, y: 3)
            .fixedSize()
    }
}

/// The thin line between two groups of a toolbar.
struct PaperToolbarDivider: View {
    var body: some View {
        PiperTheme.paperRule.frame(width: 1, height: 16).padding(.horizontal, 3).accessibilityHidden(true)
    }
}

/// A button of a toolbar: a symbol in a circle that fills under the pointer.
/// A button without a symbol shows its title. The title is the accessibility
/// label, and the help names the key.
struct PaperButton: View {
    let title: String
    var symbol: String?
    var active = false
    /// The color of the symbol while the button is active.
    var tint = PiperTheme.brand
    let help: String
    let action: () -> Void

    @State private var hovered = false
    @Environment(\.isEnabled) private var enabled
    private typealias Metrics = ReaderPaper.Metrics

    var body: some View {
        Button(action: action) {
            Group {
                if let symbol {
                    Image(systemName: symbol)
                        .font(.system(size: Metrics.toolbarGlyph, weight: .medium))
                        .frame(width: Metrics.toolbarButton, height: Metrics.toolbarButton)
                } else {
                    Text(title).lineLimit(1).fixedSize()
                        .padding(.horizontal, 12).frame(height: Metrics.toolbarButton)
                }
            }
            .foregroundStyle(!enabled ? PiperTheme.paperFaint.opacity(0.6)
                             : active ? tint : PiperTheme.paperInk)
            .background(hovered && enabled ? PiperTheme.rowHover : .clear, in: Capsule())
            .contentShape(Capsule())
        }
        .buttonStyle(PressStyle())
        .onHover { hovered = $0 }
        .help(help)
        .accessibilityLabel(title.isEmpty ? help : title)
    }
}

/// A press that dims the control and shrinks it a little, as on macOS.
struct PressStyle: ButtonStyle {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .opacity(configuration.isPressed ? 0.7 : 1)
            .scaleEffect(configuration.isPressed && !reduceMotion ? 0.96 : 1)
            .animation(reduceMotion ? nil : .spring(duration: ReaderPaper.Metrics.spring), value: configuration.isPressed)
    }
}

/// The open file, in the editor, a text view, or Quick Look. It holds the
/// reading preferences, which belong to the view.
struct FilePaperContent: View {
    @Bindable var files: FileEditor
    /// True while the session card shows over the paper.
    let cardPresented: Bool

    private var reading = ReadingSettings()
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        Group {
            if let document = files.currentDocument {
                if FilePresentation(document) == .markdown, let session = files.editor {
                    VStack(spacing: 0) {
                        EditorBanner(files: files, session: session)
                        EditorPane(page: files.editorPage,
                                   request: EditorPane.request(for: session, files: files, source: files.showsFileSource),
                                   session: session, theme: theme,
                                   anchor: files.requestedAnchor, anchorRequest: files.anchorRequest,
                                   notes: files.fileNotes(document))
                    }
                    .background(paper)
                } else if files.showsFileSource, let source = FilePresentation.sourceText(for: document) {
                    PlainTextPreview(text: source)
                } else {
                    FilePreview(library: files.library, document: document)
                }
            } else {
                EmptyPane(title: "No File")
            }
        }
        .overlay(alignment: .bottom) {
            if let document = files.currentDocument, FilePresentation.sourceText(for: document) != nil {
                TabIsland(showsSource: $files.showsFileSource, cardPresented: cardPresented)
            }
        }
    }

    private var theme: EditorTheme {
        EditorTheme(theme: reading.theme, font: reading.font, size: reading.size, appearance: reading.appearance)
    }

    private var paper: Color {
        Color(nsColor: reading.theme.background(dark: (reading.appearance.colorScheme ?? colorScheme) == .dark))
    }
}

// MARK: - Metrics

/// The sizes of a reader paper come from the Write paper of September: a text
/// column of 600 points with 56-point margins at the sides.
extension ReaderPaper {
    enum Metrics {
        /// The opacity of the content of a reader paper without the keyboard focus.
        static let restOpacity = 0.72
        /// The spring of a pressed button and of the tabs.
        static let spring: Double = 0.25
        static let readerHeaderHeight: CGFloat = 48
        /// The grip of a reader paper. Its text starts at the side margin of the article.
        static let readerHeaderPadding = EdgeInsets(top: 14, leading: 56, bottom: 0, trailing: 16)
        /// The grip of a note paper, which has narrower margins.
        static let noteHeaderPadding = EdgeInsets(top: 14, leading: 28, bottom: 0, trailing: 16)
        static let noteFootPadding = EdgeInsets(top: 10, leading: 28, bottom: 14, trailing: 20)
        /// The floating toolbar of a reader paper.
        static let toolbarHeight: CGFloat = 34
        static let toolbarButton: CGFloat = 30
        static let toolbarGlyph: CGFloat = 14
        static let toolbarInset: CGFloat = 2
    }
}
