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
    private let shortcut: () -> CaptureShortcut
    /// Opens an article as a reader paper.
    var open: (UUID) -> Void = { _ in }

    /// The highlight on the screen, while its toast shows.
    var shownHighlight: (id: UUID, quote: String)? {
        guard case .highlight(_, let id) = content, toast.isVisible,
              let note = store.notes.first(where: { $0.id == id }) else { return nil }
        return (id, note.anchor?.quote ?? note.text)
    }

    // MARK: - Initialization

    /// - Parameter shortcut: The capture shortcut that Settings shows. A second
    ///   capture of a highlight asks for a note on it.
    init(store: CaptureStore, toast: Toast, messages: Messages, shortcut: @escaping () -> CaptureShortcut) {
        self.store = store
        self.toast = toast
        self.messages = messages
        self.shortcut = shortcut
    }

    /// The key text of the highlight card: the capture shortcut, again.
    var noteKeys: String { shortcut().glyph }

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
                HStack(spacing: Metrics.lineSpacing) {
                    HStack(spacing: Metrics.keyHintSpacing) {
                        KeyChip(text: noteKeys)
                        Text("again to add a note")
                    }
                    .font(PiperTheme.paperUI(.body)).foregroundStyle(PiperTheme.paperMuted)
                    Spacer(minLength: Metrics.lineSpacing)
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
        HStack(spacing: ReadingToast.Metrics.lineSpacing) {
            Image(systemName: "checkmark")
                .font(.system(size: ReadingToast.Metrics.checkFontSize, weight: .bold))
                .foregroundStyle(PiperTheme.onAccent)
                .frame(width: ReadingToast.Metrics.checkSize, height: ReadingToast.Metrics.checkSize)
                .background(PiperTheme.brand, in: Circle())
                .accessibilityHidden(true)
            Text(title).font(PiperTheme.paperUI(.body, weight: .semibold))
            Spacer(minLength: ReadingToast.Metrics.lineSpacing)
            if let detail { Text(detail).font(PiperTheme.paperUI(.body)).foregroundStyle(PiperTheme.paperFaint).lineLimit(1) }
        }
    }
}

/// A key on the toast, such as the double Shift that opens the note field.
private struct KeyChip: View {
    let text: String

    var body: some View {
        Text(text)
            .font(PiperTheme.paperUI(.body))
            .foregroundStyle(PiperTheme.paperInk)
            .padding(.horizontal, ReadingToast.Metrics.keyPadding.width).padding(.vertical, ReadingToast.Metrics.keyPadding.height)
            .background(PiperTheme.paperTint, in: RoundedRectangle(cornerRadius: ReadingToast.Metrics.keyRadius))
    }
}

private struct ToastArticle: View {
    let article: Note
    let detail: String?

    var body: some View {
        let host = article.articleURL.flatMap(Site.init)?.key ?? ""
        HStack(spacing: ReadingToast.Metrics.articleSpacing) {
            ArticleBadge(host: host, size: ReadingToast.Metrics.badgeSize)
            VStack(alignment: .leading, spacing: ReadingToast.Metrics.articleLineSpacing) {
                Text(article.reading?.title ?? host).font(PiperTheme.paperUI(.body, weight: .semibold)).lineLimit(2)
                Text([host, detail].compactMap { $0 }.joined(separator: " · "))
                    .font(PiperTheme.paperUI(.body)).foregroundStyle(PiperTheme.paperMuted).lineLimit(1)
            }
            Spacer(minLength: 0)
        }
        .padding(ReadingToast.Metrics.articlePadding)
        .background(PiperTheme.rowHover, in: RoundedRectangle(cornerRadius: ReadingToast.Metrics.articleRadius))
    }
}

private struct CommentField: View {
    let quote: String
    @Bindable var draft: CommentDraft
    let save: () -> Void
    let skip: () -> Void
    @FocusState private var focused: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: ReadingToast.Metrics.commentSpacing) {
            Text(quote)
                .font(.system(size: ReadingToast.Metrics.quoteFontSize, design: .serif).italic())
                .foregroundStyle(PiperTheme.paperMuted)
                .lineLimit(3)
                .padding(.leading, ReadingToast.Metrics.quoteIndent)
                .overlay(alignment: .leading) { Rectangle().fill(PiperTheme.markYellow).frame(width: ReadingToast.Metrics.quoteBarWidth) }
            TextField("Add a note", text: $draft.text, axis: .vertical)
                .textFieldStyle(.plain)
                .font(PiperTheme.paperUI(.body))
                .lineLimit(3...6)
                .focused($focused)
                .onSubmit(save)
                .padding(ReadingToast.Metrics.fieldPadding)
                .background(PiperTheme.paper, in: RoundedRectangle(cornerRadius: ReadingToast.Metrics.fieldRadius))
                .overlay(RoundedRectangle(cornerRadius: ReadingToast.Metrics.fieldRadius).strokeBorder(PiperTheme.focusRing, lineWidth: ReadingToast.Metrics.fieldRingWidth))
            HStack {
                Text("Return saves · Esc skips").font(PiperTheme.paperUI(.body)).foregroundStyle(PiperTheme.paperMuted)
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
            .font(.system(size: size * Metrics.fontFraction, weight: .bold))
            .foregroundStyle(PiperTheme.onAccent)
            .frame(width: size, height: size)
            .background(Color(nsColor: SiteIcon.tagColor(for: host)), in: RoundedRectangle(cornerRadius: size * Metrics.cornerFraction))
            .accessibilityHidden(true)
    }
}

extension ReadingToast {
    /// The cards of a web page capture in the toast.
    enum Metrics {
        static let checkSize: CGFloat = 16
        static let checkFontSize: CGFloat = 9
        static let badgeSize: CGFloat = 22
        /// The space between the parts of a line of a card.
        static let lineSpacing: CGFloat = 8
        /// The space between the key and the text of the key hint.
        static let keyHintSpacing: CGFloat = 5
        static let keyPadding = CGSize(width: 5, height: 1)
        static let keyRadius: CGFloat = 4
        /// The article row: the badge, the title, and the site.
        static let articleSpacing: CGFloat = 10
        static let articleLineSpacing: CGFloat = 1
        static let articlePadding = EdgeInsets(top: 8, leading: 10, bottom: 8, trailing: 10)
        static let articleRadius: CGFloat = 8
        /// The note field under a highlight.
        static let commentSpacing: CGFloat = 9
        static let quoteFontSize: CGFloat = 13
        static let quoteIndent: CGFloat = 9
        static let quoteBarWidth: CGFloat = 2
        static let fieldPadding: CGFloat = 8
        static let fieldRadius: CGFloat = 8
        static let fieldRingWidth: CGFloat = 1.5
    }
}

extension ArticleBadge {
    enum Metrics {
        static let fontFraction: CGFloat = 0.5
        static let cornerFraction: CGFloat = 0.24
    }
}
