import Captures
import Observation
import PiperCore
import SwiftUI

/// The cards of a web page capture in the toast: a new highlight, a page
/// saved to Reading, or the note field of a highlight.
///
/// The toast does not take the focus, so the reader keeps reading in the
/// browser. Only the note field takes it, after a second capture of the same
/// highlight. Return or Escape closes the field, and the browser gets the focus
/// back because Piper never became the active application.
@MainActor
final class ReadingToast {

    enum Content: Equatable {
        case highlight(article: UUID, highlight: UUID)
        case article(UUID, isNew: Bool)
        case comment(highlight: UUID)
    }

    // MARK: - Properties

    private(set) var content: Content?
    private let draft = CommentDraft()
    private let store: CaptureStore
    private let toast: Toast
    private let messages: Messages
    /// Opens an article as a reader paper.
    var open: (UUID) -> Void = { _ in }

    /// The highlight on the screen, while its toast shows.
    var shownHighlight: (id: UUID, quote: String)? {
        guard case .highlight(_, let id) = content, toast.isVisible,
              let note = store.notes.first(where: { $0.id == id }) else { return nil }
        return (id, note.anchor?.quote ?? note.text)
    }

    // MARK: - Initialization

    init(store: CaptureStore, toast: Toast, messages: Messages) {
        self.store = store
        self.toast = toast
        self.messages = messages
    }

    // MARK: - Showing

    func show(_ content: Content) {
        guard let view = view(for: content) else { return close() }
        let closed: () -> Void = { [weak self] in self?.content = nil }
        if case .comment(let id) = content {
            toast.show(view, takesKeyboard: true, closed: closed) { [weak self] in self?.saveComment(on: id) }
        } else {
            toast.show(view, closed: closed)
        }
        self.content = content
    }

    func close() {
        guard content != nil else { return }
        toast.close()
    }
}

// MARK: - Private

private extension ReadingToast {

    func view(for content: Content) -> AnyView? {
        switch content {
        case .highlight(let articleID, _):
            guard let article = store.notes.first(where: { $0.id == articleID }) else { return nil }
            let count = ReadingList.highlights(in: store.children(of: articleID)).count
            return AnyView(ToastCard {
                ToastHeader(title: "Highlighted", detail: "\(count) on this page")
                ToastArticle(article: article, detail: "in Reading")
                HStack(spacing: 8) {
                    HStack(spacing: 5) {
                        KeyChip(text: "⇧⇧")
                        Text("again to add a note")
                    }
                    .font(PiperTheme.ui(.secondary)).foregroundStyle(PiperTheme.secondary)
                    Spacer(minLength: 8)
                    Button("Continue in Piper") { [weak self] in self?.continueReading(articleID) }
                        .buttonStyle(ToastButtonStyle())
                }
            })
        case .article(let articleID, let isNew):
            guard let article = store.notes.first(where: { $0.id == articleID }) else { return nil }
            let upNext = ReadingList(notes: store.notes).upNext.count
            let minutes = article.reading?.minutes.map { "\($0) min read" }
            return AnyView(ToastCard {
                ToastHeader(title: isNew ? "Saved to Reading" : "Already in Reading",
                            detail: upNext > 0 ? "\(upNext) in Up Next" : nil)
                ToastArticle(article: article, detail: minutes)
                HStack {
                    Spacer()
                    Button("Read Now") { [weak self] in self?.continueReading(articleID) }
                        .buttonStyle(ToastButtonStyle())
                }
            })
        case .comment(let highlightID):
            guard let highlight = store.notes.first(where: { $0.id == highlightID }) else { return nil }
            draft.text = ""
            let host = highlight.parent.flatMap { id in store.notes.first { $0.id == id } }?.articleURL.flatMap(Site.init)?.key ?? ""
            return AnyView(ToastCard {
                ToastHeader(title: "Note on this highlight", detail: host)
                CommentField(quote: highlight.anchor?.quote ?? highlight.text, draft: draft,
                             save: { [weak self] in self?.saveComment(on: highlightID) },
                             skip: { [weak self] in self?.close() })
            })
        }
    }

    func continueReading(_ article: UUID) {
        close()
        open(article)
    }

    func saveComment(on id: UUID) {
        let text = draft.text
        draft.text = ""
        close()
        do { try store.comment(text, on: id) } catch { messages.report(error) }
    }
}

/// The text of the note field, read when the field closes.
@MainActor @Observable
private final class CommentDraft {
    var text = ""
}

// MARK: - Views

private struct ToastHeader: View {
    let title: String
    let detail: String?

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: "checkmark")
                .font(.system(size: AppDefaults.ReadingToast.checkFontSize, weight: .bold))
                .foregroundStyle(PiperTheme.onAccent)
                .frame(width: AppDefaults.ReadingToast.checkSize, height: AppDefaults.ReadingToast.checkSize)
                .background(PiperTheme.accent, in: Circle())
                .accessibilityHidden(true)
            Text(title).font(PiperTheme.ui(.body, weight: .semibold))
            Spacer(minLength: 8)
            if let detail { Text(detail).font(PiperTheme.ui(.caption)).foregroundStyle(PiperTheme.faint).lineLimit(1) }
        }
    }
}

/// A key on the toast, such as the double Shift that opens the note field.
private struct KeyChip: View {
    let text: String

    var body: some View {
        Text(text)
            .font(PiperTheme.ui(.caption))
            .foregroundStyle(PiperTheme.ink)
            .padding(.horizontal, 5).padding(.vertical, 1)
            .background(PiperTheme.selection, in: RoundedRectangle(cornerRadius: 4))
    }
}

private struct ToastArticle: View {
    let article: Note
    let detail: String?

    var body: some View {
        let host = article.articleURL.flatMap(Site.init)?.key ?? ""
        HStack(spacing: 10) {
            ArticleBadge(host: host, size: AppDefaults.ReadingToast.badgeSize)
            VStack(alignment: .leading, spacing: 1) {
                Text(article.reading?.title ?? host).font(PiperTheme.ui(.body, weight: .semibold)).lineLimit(2)
                Text([host, detail].compactMap { $0 }.joined(separator: " · "))
                    .font(PiperTheme.ui(.secondary)).foregroundStyle(PiperTheme.secondary).lineLimit(1)
            }
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 10).padding(.vertical, 8)
        .background(PiperTheme.hover, in: RoundedRectangle(cornerRadius: 8))
    }
}

private struct CommentField: View {
    let quote: String
    @Bindable var draft: CommentDraft
    let save: () -> Void
    let skip: () -> Void
    @FocusState private var focused: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 9) {
            Text(quote)
                .font(.system(size: 13, design: .serif).italic())
                .foregroundStyle(PiperTheme.secondary)
                .lineLimit(3)
                .padding(.leading, 9)
                .overlay(alignment: .leading) { Rectangle().fill(PiperTheme.markYellow).frame(width: 2) }
            TextField("Add a note", text: $draft.text, axis: .vertical)
                .textFieldStyle(.plain)
                .font(PiperTheme.ui(.body))
                .lineLimit(3...6)
                .focused($focused)
                .onSubmit(save)
                .padding(8)
                .background(PiperTheme.page, in: RoundedRectangle(cornerRadius: 8))
                .overlay(RoundedRectangle(cornerRadius: 8).strokeBorder(PiperTheme.focusRing, lineWidth: 1.5))
            HStack {
                Text("Return saves · Esc skips").font(PiperTheme.ui(.secondary)).foregroundStyle(PiperTheme.secondary)
                Spacer()
                Button("Save", action: save).buttonStyle(ToastButtonStyle())
            }
        }
        .onExitCommand(perform: skip)
        .onAppear { focused = true }
    }
}

/// A square with the first letter of a site, in a color that the site name picks.
struct ArticleBadge: View {
    let host: String
    let size: CGFloat

    var body: some View {
        Text(host.first.map { String($0).uppercased() } ?? "?")
            .font(.system(size: size * AppDefaults.ArticleBadge.fontFraction, weight: .bold))
            .foregroundStyle(PiperTheme.onAccent)
            .frame(width: size, height: size)
            .background(Color(nsColor: SiteIcon.tagColor(for: host)), in: RoundedRectangle(cornerRadius: size * AppDefaults.ArticleBadge.cornerFraction))
            .accessibilityHidden(true)
    }
}
