import AppKit
import QuickLookUI
import SwiftUI
import UniformTypeIdentifiers
import Vault

/// The editor handles Markdown. Other files use literal text or a system preview.
enum FilePresentation {
    case markdown, text, quickLook

    init(_ document: VaultFile) {
        if document.isMarkdown, document.isText {
            self = .markdown
        } else {
            let type = UTType(filenameExtension: (document.name as NSString).pathExtension)
            let richPreview = [UTType.html, .image, .pdf, .rtf].contains { candidate in
                type?.conforms(to: candidate) == true
            }
            self = document.isText && !richPreview ? .text : .quickLook
        }
    }

    /// The text that the Source tab shows, or nil for a file without a Source tab.
    static func sourceText(for document: VaultFile) -> String? {
        let ext = (document.name as NSString).pathExtension.lowercased()
        guard document.isText, document.isMarkdown || ["html", "htm"].contains(ext) else { return nil }
        return document.text
    }

    static func typeName(for document: VaultFile) -> String {
        UTType(filenameExtension: (document.name as NSString).pathExtension)?.localizedDescription ?? "File"
    }
}

struct FilePreview: View {
    let library: Library
    let document: VaultFile

    private var url: URL? { try? library.vault.containedURL(document.id) }

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: Metrics.headerSpacing) {
                VStack(alignment: .leading, spacing: Metrics.titleSpacing) {
                    Text(document.name).font(PiperTheme.paperUI(.heading, weight: .semibold)).lineLimit(1)
                    Text(FilePresentation.typeName(for: document) + " · " +
                         ByteCountFormatter.string(fromByteCount: Int64(document.size), countStyle: .file))
                        .font(PiperTheme.paperUI(.body)).foregroundStyle(.secondary)
                }
                Spacer(minLength: Metrics.headerSpacing)
                if let url {
                    Button("Open in Default App") { NSWorkspace.shared.open(url) }
                    Button { NSWorkspace.shared.activateFileViewerSelecting([url]) } label: {
                        Image(systemName: "folder")
                    }.help("Reveal in Finder").accessibilityLabel("Reveal in Finder")
                }
            }
            .padding(Metrics.headerPadding)
            Rule()
            if let url {
                if FilePresentation(document) == .text, let text = document.text {
                    PlainTextPreview(text: text)
                } else {
                    SystemFilePreview(url: url, document: document)
                }
            } else {
                Text("This file is unavailable")
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .background(PiperTheme.paper)
    }
}

struct PlainTextPreview: NSViewRepresentable {
    let text: String

    func makeNSView(context: Context) -> NSScrollView { Self.makeScrollView() }

    /// A read-only text view that wraps each line at the width of the pane.
    ///
    /// `scrollableTextView()` sizes the text view to the clip view and tracks
    /// its width.
    static func makeScrollView() -> NSScrollView {
        let scroll = NSTextView.scrollableTextView()
        scroll.hasVerticalScroller = true
        scroll.hasHorizontalScroller = false
        scroll.autohidesScrollers = true
        scroll.drawsBackground = true
        scroll.backgroundColor = PiperTheme.paperNS
        guard let editor = scroll.documentView as? NSTextView else { return scroll }
        editor.isEditable = false
        editor.isSelectable = true
        editor.isRichText = false
        editor.usesFindBar = true
        editor.isHorizontallyResizable = false
        editor.textContainer?.widthTracksTextView = true
        editor.textContainerInset = Metrics.textInset
        editor.font = PiperTheme.manuscript(size: Metrics.fontSize)
        editor.textColor = PiperTheme.paperInkNS
        editor.backgroundColor = PiperTheme.paperNS
        editor.defaultParagraphStyle = {
            let style = NSMutableParagraphStyle()
            style.lineSpacing = Metrics.lineSpacing
            return style
        }()
        editor.setAccessibilityLabel("File text")
        return scroll
    }

    func updateNSView(_ scroll: NSScrollView, context: Context) {
        guard let editor = scroll.documentView as? NSTextView, editor.string != text else { return }
        editor.string = text
    }
}

extension FilePreview {
    enum Metrics {
        /// The header of a file: the name and the type, then the buttons.
        static let headerSpacing: CGFloat = 12
        static let titleSpacing: CGFloat = 4
        static let headerPadding: CGFloat = 20
    }
}

extension PlainTextPreview {
    enum Metrics {
        static let textInset = NSSize(width: 32, height: 20)
        static let fontSize: CGFloat = 12.5
        static let lineSpacing: CGFloat = 3
    }
}

private struct SystemFilePreview: NSViewRepresentable {
    let url: URL
    let document: VaultFile

    final class Coordinator {
        var document: VaultFile?
        var url: URL?
    }

    func makeCoordinator() -> Coordinator { Coordinator() }

    func makeNSView(context: Context) -> QLPreviewView {
        let view = QLPreviewView(frame: .zero, style: .normal)!
        view.autostarts = false
        view.setAccessibilityLabel("File preview")
        return view
    }

    func updateNSView(_ view: QLPreviewView, context: Context) {
        guard context.coordinator.url != url || context.coordinator.document != document else { return }
        if context.coordinator.url == url { view.refreshPreviewItem() }
        else { view.previewItem = url as NSURL }
        context.coordinator.url = url
        context.coordinator.document = document
    }

    static func dismantleNSView(_ view: QLPreviewView, coordinator: Coordinator) {
        view.close()
    }
}
