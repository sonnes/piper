import AppKit
import SwiftUI
import Captures

struct CaptureEditor: NSViewRepresentable {
    @Binding var text: String
    @Binding var focused: Bool

    func makeCoordinator() -> Coordinator { Coordinator(self) }

    func makeNSView(context: Context) -> NSScrollView {
        let metrics = AppDefaults.Composer.self
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
        editor.font = PiperTheme.uiNS(AppDefaults.FontSize.large)
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
        editor.minSize = NSSize(width: 0, height: metrics.textHeight)
        editor.maxSize = NSSize(width: CGFloat.greatestFiniteMagnitude, height: CGFloat.greatestFiniteMagnitude)
        editor.allowsUndo = true
        editor.isAutomaticQuoteSubstitutionEnabled = false
        editor.isAutomaticDashSubstitutionEnabled = false
        editor.isAutomaticTextReplacementEnabled = false
        editor.isAutomaticSpellingCorrectionEnabled = false

        let paragraph = NSMutableParagraphStyle()
        paragraph.minimumLineHeight = metrics.lineHeight
        paragraph.maximumLineHeight = metrics.lineHeight
        editor.defaultParagraphStyle = paragraph
        editor.typingAttributes = [
            .font: PiperTheme.uiNS(AppDefaults.FontSize.large),
            .foregroundColor: PiperTheme.inkNS,
            .paragraphStyle: paragraph
        ]
        editor.string = text
        editor.delegate = context.coordinator
        editor.setAccessibilityLabel("New note text")
        editor.setAccessibilityHelp("Return saves the note. Shift-Return inserts a new line.")
        editor.onFocusChange = { [weak coordinator = context.coordinator] focused in
            DispatchQueue.main.async { coordinator?.parent.focused = focused }
        }
        scroll.documentView = editor
        return scroll
    }

    func updateNSView(_ scroll: NSScrollView, context: Context) {
        context.coordinator.parent = self
        guard let editor = scroll.documentView as? CaptureTextView else { return }
        if editor.string != text {
            editor.string = text
            editor.undoManager?.removeAllActions()
            editor.needsDisplay = true
            editor.sizeToFit()
            if text.isEmpty { scroll.contentView.scroll(to: .zero) }
            scroll.reflectScrolledClipView(scroll.contentView)
        }
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

        func textDidChange(_ notification: Notification) {
            guard let editor = notification.object as? NSTextView else { return }
            parent.text = editor.string
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
        attributes[.foregroundColor] = PiperTheme.secondaryNS
        let placeholder = NSAttributedString(string: "Add a note or a prompt", attributes: attributes)
        placeholder.draw(in: NSRect(origin: textContainerOrigin,
            size: NSSize(width: container.size.width, height: AppDefaults.Composer.lineHeight)))
    }
}
