import AppKit
import SwiftUI
import Captures

struct CaptureEditor: NSViewRepresentable {
    @Binding var text: String
    @Binding var focused: Bool
    let placeholder: String
    var label = "New note text"
    var help = "Return saves the note. Shift-Return inserts a new line."
    var compact = false
    /// The texts that show in the accent color, such as `@` mentions.
    var highlights: [String] = []
    /// Handles a key command such as `insertNewline:` or `moveUp:`. Returns
    /// true when it handled the command. The coordinator reads the newest
    /// value on each update, so the handler never sees an old view.
    var command: ((Selector) -> Bool)?
    /// Receives the height of the text and its insets after each change.
    var contentHeight: ((CGFloat) -> Void)?

    func makeCoordinator() -> Coordinator { Coordinator(self) }

    func makeNSView(context: Context) -> NSScrollView {
        let metrics = AppDefaults.Composer.self
        let fontSize = compact ? metrics.inboxFontSize : metrics.fontSize
        let lineHeight = compact ? metrics.inboxLineHeight : metrics.lineHeight
        let scroll = CaptureScrollView(frame: NSRect(x: 0, y: 0, width: metrics.width, height: metrics.height))
        scroll.borderType = .noBorder
        scroll.drawsBackground = false
        scroll.hasVerticalScroller = true
        scroll.hasHorizontalScroller = false
        scroll.autohidesScrollers = true
        scroll.scrollerStyle = .overlay
        scroll.verticalScroller?.controlSize = .small
        scroll.scrollerInsets = NSEdgeInsets(top: metrics.textInset.height, left: 0,
                                             bottom: metrics.textInset.height, right: metrics.scrollerInset)
        scroll.horizontalScrollElasticity = .none
        scroll.automaticallyAdjustsContentInsets = false

        let editor = CaptureTextView(frame: scroll.contentView.bounds)
        editor.isRichText = false
        editor.importsGraphics = false
        editor.drawsBackground = false
        editor.font = PiperTheme.uiNS(fontSize)
        editor.textColor = PiperTheme.inkNS
        editor.insertionPointColor = PiperTheme.accentNS
        editor.selectedTextAttributes = [.backgroundColor: PiperTheme.selectionNS, .foregroundColor: PiperTheme.inkNS]
        editor.textContainerInset = metrics.textInset
        editor.textContainer?.lineFragmentPadding = 0
        editor.textContainer?.widthTracksTextView = true
        editor.textContainer?.containerSize = NSSize(width: metrics.textWidth, height: CGFloat.greatestFiniteMagnitude)
        editor.isVerticallyResizable = true
        editor.isHorizontallyResizable = false
        editor.autoresizingMask = [.width]
        editor.minSize = NSSize(width: 0, height: compact ? lineHeight : metrics.textHeight)
        editor.maxSize = NSSize(width: CGFloat.greatestFiniteMagnitude, height: CGFloat.greatestFiniteMagnitude)
        editor.allowsUndo = true
        editor.isAutomaticQuoteSubstitutionEnabled = false
        editor.isAutomaticDashSubstitutionEnabled = false
        editor.isAutomaticTextReplacementEnabled = false
        editor.isAutomaticSpellingCorrectionEnabled = false

        let paragraph = NSMutableParagraphStyle()
        paragraph.minimumLineHeight = lineHeight
        paragraph.maximumLineHeight = lineHeight
        editor.defaultParagraphStyle = paragraph
        editor.typingAttributes = [
            .font: PiperTheme.uiNS(fontSize),
            .foregroundColor: PiperTheme.inkNS,
            .paragraphStyle: paragraph
        ]
        editor.string = text
        editor.setSelectedRange(NSRange(location: (text as NSString).length, length: 0))
        editor.placeholder = placeholder
        editor.delegate = context.coordinator
        editor.setAccessibilityLabel(label)
        editor.setAccessibilityHelp(help)
        editor.onFocusChange = { [weak coordinator = context.coordinator] focused in
            DispatchQueue.main.async { coordinator?.parent.focused = focused }
        }
        scroll.documentView = editor
        return scroll
    }

    func updateNSView(_ scroll: NSScrollView, context: Context) {
        context.coordinator.parent = self
        guard let editor = scroll.documentView as? CaptureTextView else { return }
        if editor.placeholder != placeholder {
            editor.placeholder = placeholder
            editor.needsDisplay = true
        }
        if editor.string != text {
            editor.string = text
            editor.setSelectedRange(NSRange(location: (text as NSString).length, length: 0))
            editor.undoManager?.removeAllActions()
            editor.needsDisplay = true
            editor.sizeToFit()
            if text.isEmpty { scroll.contentView.scroll(to: .zero) }
            scroll.reflectScrolledClipView(scroll.contentView)
        }
        context.coordinator.reportHeight(of: editor)
        context.coordinator.highlight(editor)
        if focused, editor.window?.firstResponder !== editor {
            DispatchQueue.main.async { [weak editor, weak coordinator = context.coordinator] in
                guard let editor, coordinator?.parent.focused == true else { return }
                editor.window?.makeFirstResponder(editor)
            }
        } else if !focused, editor.window?.firstResponder === editor {
            editor.window?.makeFirstResponder(nil)
        }
    }

    final class Coordinator: NSObject, NSTextViewDelegate {
        var parent: CaptureEditor
        init(_ parent: CaptureEditor) { self.parent = parent }

        private var reportedHeight: CGFloat?

        func textDidChange(_ notification: Notification) {
            guard let editor = notification.object as? NSTextView else { return }
            parent.text = editor.string
            reportHeight(of: editor)
            highlight(editor)
        }

        /// Colors each highlight text. The colors are temporary attributes, so
        /// the text keeps no style.
        func highlight(_ editor: NSTextView) {
            guard let manager = editor.layoutManager else { return }
            let text = editor.string as NSString
            let whole = NSRange(location: 0, length: text.length)
            manager.removeTemporaryAttribute(.foregroundColor, forCharacterRange: whole)
            manager.removeTemporaryAttribute(.backgroundColor, forCharacterRange: whole)
            for token in parent.highlights where !token.isEmpty {
                var search = whole
                while search.length > 0 {
                    let found = text.range(of: token, range: search)
                    guard found.location != NSNotFound else { break }
                    manager.addTemporaryAttributes([.foregroundColor: PiperTheme.accentNS,
                                                    .backgroundColor: PiperTheme.accentNS.withAlphaComponent(0.1)],
                                                   forCharacterRange: found)
                    let next = found.location + found.length
                    search = NSRange(location: next, length: text.length - next)
                }
            }
        }

        /// Sends the height of the laid-out text to `contentHeight`, when it changed.
        func reportHeight(of editor: NSTextView) {
            guard let report = parent.contentHeight, let manager = editor.layoutManager,
                  let container = editor.textContainer else { return }
            manager.ensureLayout(for: container)
            let height = manager.usedRect(for: container).height + editor.textContainerInset.height * 2
            guard height != reportedHeight else { return }
            reportedHeight = height
            DispatchQueue.main.async { report(height) }
        }

        func textView(_ textView: NSTextView, doCommandBy selector: Selector) -> Bool {
            parent.command?(selector) ?? false
        }
    }
}

private final class CaptureScrollView: NSScrollView {
    override func tile() {
        super.tile()
        contentView.frame = bounds.insetBy(dx: 0, dy: AppDefaults.Composer.regionInset)
    }

    override func mouseDown(with event: NSEvent) {
        if !contentView.frame.contains(convert(event.locationInWindow, from: nil)) {
            window?.makeFirstResponder(documentView)
        } else {
            super.mouseDown(with: event)
        }
    }
}

private final class CaptureTextView: NSTextView {
    var onFocusChange: ((Bool) -> Void)?
    var placeholder = ""

    override func becomeFirstResponder() -> Bool {
        let accepted = super.becomeFirstResponder()
        if accepted { onFocusChange?(true) }
        return accepted
    }

    override func resignFirstResponder() -> Bool {
        let accepted = super.resignFirstResponder()
        if accepted { onFocusChange?(false) }
        return accepted
    }

    override func didChangeText() {
        super.didChangeText()
        needsDisplay = true
    }

    /// Draws the placeholder with the attributes of the text that replaces it.
    ///
    /// The typing attributes carry the font and the paragraph style of a real
    /// line, so the placeholder sits on the same baseline.
    override func draw(_ dirtyRect: NSRect) {
        super.draw(dirtyRect)
        guard string.isEmpty, let container = textContainer else { return }
        var attributes = typingAttributes
        attributes[.foregroundColor] = PiperTheme.faintNS
        NSAttributedString(string: placeholder, attributes: attributes).draw(in: NSRect(origin: textContainerOrigin,
            size: NSSize(width: container.size.width, height: AppDefaults.Composer.lineHeight)))
    }
}
