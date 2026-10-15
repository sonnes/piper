import AppKit
import Captures
import Observation
import SwiftUI

/// The toast of a web page capture: a new highlight, a page saved to Reading,
/// or the note field of a highlight.
///
/// The toast does not take the focus, so the reader keeps reading in the
/// browser. Only the note field takes it, after a second capture of the same
/// highlight. Return or Escape closes the field, and the browser gets the focus
/// back because Piper never became the active application.
@MainActor
final class ReadingToast: NSObject {

    enum Content: Equatable {
        case highlight(article: UUID, highlight: UUID)
        case article(UUID, isNew: Bool)
        case comment(highlight: UUID)
    }

    // MARK: - Properties

    private(set) var content: Content?
    private var panel: ToastPanel?
    private var dismiss: DispatchWorkItem?
    private let draft = CommentDraft()
    private let store: CaptureStore
    /// Opens an article in the main window, at a highlight when one is given.
    var open: (UUID, UUID?) -> Void = { _, _ in }

    /// The highlight on the screen, while its toast shows.
    var shownHighlight: (id: UUID, quote: String)? {
        guard case .highlight(_, let id) = content, panel?.isVisible == true,
              let note = store.notes.first(where: { $0.id == id }) else { return nil }
        return (id, note.anchor?.quote ?? note.text)
    }

    // MARK: - Initialization

    init(store: CaptureStore) {
        self.store = store
    }

    // MARK: - Showing

    func show(_ content: Content) {
        dismiss?.cancel()
        let previous = panel
        self.content = content
        guard let view = view(for: content) else { return close() }
        let panel = previous ?? makePanel()
        let hosting = NSHostingView(rootView: view)
        panel.contentView = hosting
        let size = hosting.fittingSize
        if let screen = NSScreen.main {
            let margin = AppDefaults.ReadingToast.margin
            panel.setFrame(NSRect(x: screen.visibleFrame.maxX - size.width - margin, y: screen.visibleFrame.minY + margin,
                                  width: size.width, height: size.height), display: true)
        }
        self.panel = panel
        if case .comment = content {
            panel.acceptsKey = true
            panel.makeKeyAndOrderFront(nil)
        } else {
            panel.acceptsKey = false
            panel.orderFrontRegardless()
            let work = DispatchWorkItem { [weak self] in self?.close() }
            dismiss = work
            DispatchQueue.main.asyncAfter(deadline: .now() + AppDefaults.Agents.actionToastDuration, execute: work)
        }
    }

    func close() {
        dismiss?.cancel()
        dismiss = nil
        content = nil
        panel?.acceptsKey = false
        panel?.orderOut(nil)
    }
}

// MARK: - NSWindowDelegate

extension ReadingToast: NSWindowDelegate {

    /// A click in another window keeps the typed note.
    func windowDidResignKey(_ notification: Notification) {
        guard case .comment(let id) = content else { return }
        saveComment(on: id)
    }
}

// MARK: - Private

private extension ReadingToast {

    func makePanel() -> ToastPanel {
        let panel = ToastPanel(contentRect: NSRect(x: 0, y: 0, width: AppDefaults.ReadingToast.width, height: 100),
                               styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        panel.isReleasedWhenClosed = false
        panel.level = .floating
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = true
        panel.hidesOnDeactivate = false
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        panel.delegate = self
        return panel
    }

    func view(for content: Content) -> AnyView? {
        switch content {
        case .highlight(let articleID, let highlightID):
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
                    .font(PiperTheme.ui(11.5)).foregroundStyle(PiperTheme.secondary)
                    Spacer(minLength: 8)
                    Button("Continue in Piper") { [weak self] in self?.continueReading(articleID, highlightID) }
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
                    Button("Read Now") { [weak self] in self?.continueReading(articleID, nil) }
                        .buttonStyle(ToastButtonStyle())
                }
            })
        case .comment(let highlightID):
            guard let highlight = store.notes.first(where: { $0.id == highlightID }) else { return nil }
            draft.text = ""
            let host = highlight.parent.flatMap { id in store.notes.first { $0.id == id } }?.articleURL.map(ArticleBadge.host) ?? ""
            return AnyView(ToastCard {
                ToastHeader(title: "Note on this highlight", detail: host)
                CommentField(quote: highlight.anchor?.quote ?? highlight.text, draft: draft,
                             save: { [weak self] in self?.saveComment(on: highlightID) },
                             skip: { [weak self] in self?.close() })
            })
        }
    }

    func continueReading(_ article: UUID, _ highlight: UUID?) {
        close()
        open(article, highlight)
    }

    func saveComment(on id: UUID) {
        let text = draft.text
        draft.text = ""
        close()
        store.comment(text, on: id)
    }
}

/// A panel that takes the keyboard only while the note field shows.
private final class ToastPanel: NSPanel {
    var acceptsKey = false
    override var canBecomeKey: Bool { acceptsKey }
}

/// The text of the note field, read when the field closes.
@MainActor @Observable
private final class CommentDraft {
    var text = ""
}

// MARK: - Views

private struct ToastCard<Content: View>: View {
    @ViewBuilder let content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 9) { content }
            .padding(AppDefaults.ReadingToast.padding)
            .frame(width: AppDefaults.ReadingToast.width, alignment: .leading)
            .foregroundStyle(PiperTheme.ink)
            .background(.regularMaterial, in: RoundedRectangle(cornerRadius: AppDefaults.ReadingToast.cornerRadius))
            .overlay(RoundedRectangle(cornerRadius: AppDefaults.ReadingToast.cornerRadius).strokeBorder(PiperTheme.rule, lineWidth: 0.5))
    }
}

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
            Text(title).font(PiperTheme.ui(13, weight: .semibold))
            Spacer(minLength: 8)
            if let detail { Text(detail).font(PiperTheme.ui(11)).foregroundStyle(PiperTheme.faint).lineLimit(1) }
        }
    }
}

/// A key on the toast, such as the double Shift that opens the note field.
private struct KeyChip: View {
    let text: String

    var body: some View {
        Text(text)
            .font(PiperTheme.ui(11))
            .foregroundStyle(PiperTheme.ink)
            .padding(.horizontal, 5).padding(.vertical, 1)
            .background(PiperTheme.selection, in: RoundedRectangle(cornerRadius: 4))
    }
}

private struct ToastArticle: View {
    let article: Note
    let detail: String?

    var body: some View {
        let host = article.articleURL.map(ArticleBadge.host) ?? ""
        HStack(spacing: 10) {
            ArticleBadge(host: host, size: AppDefaults.ReadingToast.badgeSize)
            VStack(alignment: .leading, spacing: 1) {
                Text(article.reading?.title ?? host).font(PiperTheme.ui(12.5, weight: .semibold)).lineLimit(2)
                Text([host, detail].compactMap { $0 }.joined(separator: " · "))
                    .font(PiperTheme.ui(11.5)).foregroundStyle(PiperTheme.secondary).lineLimit(1)
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
                .font(PiperTheme.ui(13))
                .lineLimit(3...6)
                .focused($focused)
                .onSubmit(save)
                .padding(8)
                .background(PiperTheme.page, in: RoundedRectangle(cornerRadius: 8))
                .overlay(RoundedRectangle(cornerRadius: 8).strokeBorder(PiperTheme.focusRing, lineWidth: 1.5))
            HStack {
                Text("Return saves · Esc skips").font(PiperTheme.ui(11.5)).foregroundStyle(PiperTheme.secondary)
                Spacer()
                Button("Save", action: save).buttonStyle(ToastButtonStyle())
            }
        }
        .onExitCommand(perform: skip)
        .onAppear { focused = true }
    }
}

/// The accent button of the toast. A stock prominent button turns gray in a
/// panel that is not the key window, and the toast is rarely the key window.
private struct ToastButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(PiperTheme.ui(12, weight: .medium))
            .foregroundStyle(PiperTheme.onAccent)
            .padding(.horizontal, AppDefaults.ReadingToast.buttonPadding)
            .frame(height: AppDefaults.ReadingToast.buttonHeight)
            .background(PiperTheme.accent.opacity(configuration.isPressed ? 0.75 : 1), in: RoundedRectangle(cornerRadius: PiperTheme.radius))
            .contentShape(Rectangle())
    }
}

/// A square with the first letter of a site, in a color that the site name picks.
struct ArticleBadge: View {
    let host: String
    let size: CGFloat

    var body: some View {
        let colors = PiperTheme.tagsNS
        let index = host.unicodeScalars.reduce(0) { ($0 + Int($1.value)) % 997 } % colors.count
        Text(host.first.map { String($0).uppercased() } ?? "?")
            .font(PiperTheme.ui(size * AppDefaults.ArticleBadge.fontFraction, weight: .bold))
            .foregroundStyle(PiperTheme.onAccent)
            .frame(width: size, height: size)
            .background(Color(nsColor: colors[index]), in: RoundedRectangle(cornerRadius: size * AppDefaults.ArticleBadge.cornerFraction))
            .accessibilityHidden(true)
    }

    /// The host of a link without `www.`.
    static func host(_ url: URL) -> String {
        let host = url.host() ?? url.absoluteString
        return host.hasPrefix("www.") ? String(host.dropFirst(4)) : host
    }
}
