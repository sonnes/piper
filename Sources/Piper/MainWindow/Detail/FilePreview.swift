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

    static func sourceText(for document: VaultFile, markdown: String? = nil) -> String? {
        let ext = (document.name as NSString).pathExtension.lowercased()
        guard document.isText, document.isMarkdown || ["html", "htm"].contains(ext) else { return nil }
        if document.isMarkdown, let markdown { return document.frontmatterPrefix + markdown }
        return document.text
    }

    static func typeName(for document: VaultFile) -> String {
        UTType(filenameExtension: (document.name as NSString).pathExtension)?.localizedDescription ?? "File"
    }
}

struct FilePreview: View {
    let model: AppModel
    let document: VaultFile

    private var url: URL? { try? model.vault.containedURL(document.id) }

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 12) {
                VStack(alignment: .leading, spacing: 4) {
                    Text(document.name).font(PiperTheme.ui(17, weight: .semibold)).lineLimit(1)
                    Text(FilePresentation.typeName(for: document) + " · " +
                         ByteCountFormatter.string(fromByteCount: Int64(document.size), countStyle: .file))
                        .font(PiperTheme.ui(12)).foregroundStyle(.secondary)
                }
                Spacer(minLength: 12)
                if let url {
                    Button("Open in Default App") { NSWorkspace.shared.open(url) }
                    Button { NSWorkspace.shared.activateFileViewerSelecting([url]) } label: {
                        Image(systemName: "folder")
                    }.help("Reveal in Finder").accessibilityLabel("Reveal in Finder")
                }
            }
            .padding(20)
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
        .background(PiperTheme.page)
    }
}

struct PlainTextPreview: NSViewRepresentable {
    let text: String

    func makeNSView(context: Context) -> NSScrollView {
        let scroll = NSScrollView()
        scroll.hasVerticalScroller = true
        scroll.autohidesScrollers = true
        scroll.drawsBackground = true
        scroll.backgroundColor = PiperTheme.pageNS

        let editor = NSTextView(frame: NSRect(x: 0, y: 0, width: 640, height: 480))
        editor.isEditable = false
        editor.isSelectable = true
        editor.isRichText = false
        editor.usesFindBar = true
        editor.isVerticallyResizable = true
        editor.isHorizontallyResizable = false
        editor.autoresizingMask = [.width]
        editor.minSize = .zero
        editor.maxSize = NSSize(width: CGFloat.greatestFiniteMagnitude, height: CGFloat.greatestFiniteMagnitude)
        editor.textContainer?.widthTracksTextView = true
        editor.textContainer?.containerSize = NSSize(width: 640, height: CGFloat.greatestFiniteMagnitude)
        editor.textContainerInset = NSSize(width: 24, height: 20)
        editor.font = .monospacedSystemFont(ofSize: 14, weight: .regular)
        editor.textColor = PiperTheme.inkNS
        editor.backgroundColor = PiperTheme.pageNS
        editor.setAccessibilityLabel("File text")
        scroll.documentView = editor
        return scroll
    }

    func updateNSView(_ scroll: NSScrollView, context: Context) {
        guard let editor = scroll.documentView as? NSTextView, editor.string != text else { return }
        editor.string = text
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
