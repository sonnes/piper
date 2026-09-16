import AppKit
import MarkdownEngine
import Observation
import SwiftUI
import PiperCore
import Vault

@MainActor @Observable
final class WikiEditSession {
    var document: VaultFile
    var text: String
    var markdown: String { WikiEditorLinks.decode(text) }
    var hasChanges: Bool { markdown != document.editableBody }

    init(document: VaultFile) {
        self.document = document
        text = WikiEditorLinks.encode(document.editableBody)
    }
}

enum WikiEditorLinks {
    static let prefix = "piper-link:"

    static func encode(_ markdown: String) -> String {
        replace(markdown) { target, alias in
            guard let alias else { return nil }
            return "[[\(alias)|\(prefix)\(Data(target.utf8).base64EncodedString())]]"
        }
    }

    static func decode(_ text: String) -> String {
        replace(text) { label, identifier in
            guard let identifier, let target = target(for: identifier) else { return nil }
            return "[[\(target)|\(label)]]"
        }
    }

    static func target(for identifier: String) -> String? {
        guard identifier.hasPrefix(prefix),
              let bytes = Data(base64Encoded: String(identifier.dropFirst(prefix.count))) else { return nil }
        return String(data: bytes, encoding: .utf8)
    }

    static func markdownURL(in text: String, after label: NSRange) -> URL? {
        let source = text as NSString
        guard NSMaxRange(label) < source.length else { return nil }
        let suffix = source.substring(from: NSMaxRange(label))
        guard suffix.hasPrefix("](") else { return nil }
        var destination = ""
        var depth = 0
        var escaped = false
        for character in suffix.dropFirst(2) {
            if escaped { destination.append(character); escaped = false; continue }
            if character == "\\" { escaped = true; continue }
            if character == ")", depth == 0 {
                return URL(string: destination.trimmingCharacters(in: .whitespaces).trimmingCharacters(in: CharacterSet(charactersIn: "<>")))
            }
            if character == "(" { depth += 1 }
            if character == ")" { depth -= 1 }
            if character.isNewline { return nil }
            destination.append(character)
        }
        return nil
    }

    private static func replace(_ text: String, transform: (String, String?) -> String?) -> String {
        let regex = try! NSRegularExpression(pattern: #"(?<!!)\[\[([^|\]\r\n]*)(?:\|([^\]\r\n]+))?\]\]"#)
        let output = NSMutableString(string: text)
        for match in regex.matches(in: text, range: NSRange(text.startIndex..., in: text)).reversed() {
            let first = (text as NSString).substring(with: match.range(at: 1))
            let second = match.range(at: 2).location == NSNotFound ? nil : (text as NSString).substring(with: match.range(at: 2))
            if let replacement = transform(first, second) { output.replaceCharacters(in: match.range, with: replacement) }
        }
        return output as String
    }
}

struct WikiEditor: View {
    let model: AppModel
    let document: VaultFile
    let fontSize: Double
    let fontName: String
    let paper: Color

    private var text: Binding<String> {
        Binding(get: { model.wikiEdit?.text ?? WikiEditorLinks.encode(document.editableBody) },
                set: { model.wikiEdit?.text = $0 })
    }

    var body: some View {
        GeometryReader { geometry in
            NativeTextViewWrapper(
                text: text,
                configuration: configuration,
                fontName: fontName,
                fontSize: fontSize,
                documentId: document.id,
                isEditable: true,
                onLinkClick: { identifier in
                    guard let document = model.currentDocument else { return }
                    let target = WikiEditorLinks.target(for: identifier) ?? identifier
                    do {
                        let location = try WikiLinks.resolve(target, from: document, files: model.files, vault: model.vault, wikiStyle: true)
                        model.openDocument(location.path, anchor: location.anchor)
                    } catch { model.store.report(error) }
                },
                onBuildContextMenu: { menu, _ in
                    for item in menu.items where item.action == #selector(NSText.paste(_:)) {
                        item.action = #selector(NSTextView.pasteAsPlainText(_:))
                    }
                    return menu
                }
            )
            .frame(width: min(AppDefaults.Reader.columnWidth + AppDefaults.Reader.horizontalInset * 2, geometry.size.width), height: geometry.size.height)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .accessibilityLabel("Page")
            .background(WikiEditorSetup(model: model, anchorRequest: model.anchorRequest))
        }
        .background(paper)
    }

    private var configuration: MarkdownEditorConfiguration {
        var config = MarkdownEditorConfiguration.default
        let targets = WikiLinks.targets(in: model.wikiEdit?.markdown ?? document.body).filter { link in
            (try? WikiLinks.resolve(link.target, from: document, files: model.files, vault: model.vault, wikiStyle: link.wikiStyle)) != nil
        }.flatMap { [$0.target, WikiEditorLinks.prefix + Data($0.target.utf8).base64EncodedString()] }
        config.services.wikiLinks = EditorLinkResolver(targets: Set(targets))
        config.readingWidth = nil
        config.textInsets = TextInsets(horizontal: AppDefaults.Reader.horizontalInset, vertical: AppDefaults.Reader.topInset)
        config.paragraph.lineHeightExtraSpacing = fontSize * 0.3
        config.paragraph.spacingFactor = 0
        config.headings.fontMultipliers = AppDefaults.Reader.headingMultipliers
        config.overscroll.percent = 0.35
        config.theme.link = PiperTheme.accentNS
        config.theme.incompleteLink = PiperTheme.accentNS
        config.theme.bodyText = PiperTheme.inkNS
        config.theme.mutedText = PiperTheme.secondaryNS
        config.theme.disabledText = PiperTheme.secondaryNS
        config.theme.headingMarker = PiperTheme.secondaryNS
        config.theme.strikethroughColor = PiperTheme.secondaryNS
        config.theme.findMatchHighlight = PiperTheme.selectionNS
        config.theme.findCurrentMatchHighlight = PiperTheme.selectionNS
        config.theme.highlightColor = PiperTheme.selectionNS
        config.spellChecking.automaticSpellingCorrection = false
        config.extensions = [StrikethroughExtension()]
        return config
    }
}

private struct EditorLinkResolver: WikiLinkResolver {
    let targets: Set<String>
    func resolve(displayName: String, range: NSRange) -> WikiLinkResolution? {
        WikiLinkResolution(id: displayName, exists: targets.contains(displayName))
    }
    func fingerprint() -> AnyHashable { targets }
}

private struct WikiEditorSetup: NSViewRepresentable {
    let model: AppModel
    let anchorRequest: UUID

    func makeNSView(context: Context) -> SetupView { SetupView() }
    func updateNSView(_ view: SetupView, context: Context) {
        view.model = model
        DispatchQueue.main.async { [weak view] in
            view?.configure(anchorRequest: anchorRequest)
        }
    }

    static func dismantleNSView(_ view: SetupView, coordinator: ()) { view.removeMonitor() }

    final class SetupView: NSView {
        weak var model: AppModel?
        private weak var editor: NSTextView?
        private var anchorRequest: UUID?
        private var monitor: Any?

        func configure(anchorRequest: UUID) {
            guard let root = window?.contentView, let editor = findEditor(in: root), let scroll = editor.enclosingScrollView else { return }
            self.editor = editor
            editor.setAccessibilityLabel("Markdown text")
            editor.selectedTextAttributes = [.backgroundColor: PiperTheme.selectionNS, .foregroundColor: PiperTheme.inkNS]
            editor.linkTextAttributes = [.foregroundColor: PiperTheme.accentNS]
            editor.isAutomaticQuoteSubstitutionEnabled = false
            scroll.scrollerStyle = .overlay
            scroll.verticalScroller?.controlSize = .small
            scroll.scrollerInsets = NSEdgeInsets(top: 12, left: 0, bottom: 12, right: 6)
            scroll.horizontalScrollElasticity = .none
            installMonitor()

            if self.anchorRequest != anchorRequest {
                self.anchorRequest = anchorRequest
                if let anchor = model?.requestedAnchor, !anchor.isEmpty {
                    if let range = WikiMarkdown.range(ofAnchor: anchor, in: editor.string) {
                        editor.scrollRangeToVisible(range)
                        let rect = editor.firstRect(forCharacterRange: range, actualRange: nil)
                        if let window, let page = scroll.documentView {
                            let point = page.convert(window.convertFromScreen(rect), from: nil).origin
                            scroll.contentView.scroll(to: NSPoint(x: 0, y: max(0, point.y - 24)))
                            scroll.reflectScrolledClipView(scroll.contentView)
                        }
                    } else { model?.store.report(PiperError("The heading “\(anchor)” is unavailable in this note.")) }
                }
            }
        }

        func removeMonitor() {
            if let monitor { NSEvent.removeMonitor(monitor) }
            monitor = nil
        }

        private func installMonitor() {
            guard monitor == nil else { return }
            monitor = NSEvent.addLocalMonitorForEvents(matching: .leftMouseDown) { [weak self] event in
                guard let self, let editor, event.window === window,
                      let storage = editor.textStorage,
                      let document = model?.currentDocument else { return event }
                let point = editor.convert(event.locationInWindow, from: nil)
                guard editor.visibleRect.contains(point) else { return event }
                let index = editor.characterIndexForInsertion(at: point)
                guard index < storage.length else { return event }
                var label = NSRange()
                guard storage.attribute(.link, at: index, longestEffectiveRange: &label, in: NSRange(location: 0, length: storage.length)) is URL,
                      let url = WikiEditorLinks.markdownURL(in: editor.string, after: label) else { return event }
                model?.openLink(url, from: document)
                return nil
            }
        }

        private func findEditor(in view: NSView) -> NSTextView? {
            if let editor = view as? NSTextView, editor.delegate is NativeTextViewCoordinator { return editor }
            return view.subviews.lazy.compactMap { self.findEditor(in: $0) }.first
        }
    }
}
