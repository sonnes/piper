import AppKit
import Captures
import PiperCore
import SwiftUI
import UniformTypeIdentifiers
import Vault
import WebKit

/// The reading preferences that the editor page applies.
struct EditorTheme: Encodable, Equatable {
    struct Background: Encodable, Equatable {
        let light: String
        let dark: String
    }

    let theme: WikiReadingTheme
    let font: WikiReadingFont
    let size: Double
    let appearance: WikiReadingAppearance
    /// The paper color of the theme as CSS. The page has no colors of its own for a theme.
    let background: Background

    init(theme: WikiReadingTheme, font: WikiReadingFont, size: Double, appearance: WikiReadingAppearance) {
        self.theme = theme
        self.font = font
        self.size = size
        self.appearance = appearance
        background = Background(light: theme.cssBackground(dark: false), dark: theme.cssBackground(dark: true))
    }
}

/// The file that the editor page shows. The page reads the whole file, with its frontmatter.
struct EditorOpenRequest: Encodable, Equatable {
    struct WikiTarget: Encodable, Equatable {
        let path: String
        let target: String
        let title: String
    }

    let path: String
    let text: String
    /// `rich` for the Preview tab, `source` for the Source tab.
    let mode: String
    let wikiTargets: [WikiTarget]
    /// The byline: the date, the reading time, and the save state.
    let header: String
    /// The title over a file whose body has no heading.
    let title: String?
}

/// A message of the editor page. See `Outgoing` in `web/src/bridge.ts`.
enum EditorMessage: Decodable, Equatable {
    enum LinkKind: String, Decodable {
        case url, wiki
    }

    case ready
    case change(path: String, text: String)
    case link(kind: LinkKind, target: String)
    /// A pasted or dropped image, in base64. The answer is its path for the Markdown.
    case image(path: String, type: String, data: String)
    case lossy(path: String, reasons: [String])
    /// An uncaught error or an unhandled rejection of the page.
    case error(message: String)
    case mark(ReaderAction)

    private enum Key: String, CodingKey { case action, path, text, kind, target, type, data, reasons, message }

    init(from decoder: Decoder) throws {
        let values = try decoder.container(keyedBy: Key.self)
        switch try values.decode(String.self, forKey: .action) {
        case "ready":
            self = .ready
        case "change":
            self = .change(path: try values.decode(String.self, forKey: .path), text: try values.decode(String.self, forKey: .text))
        case "link":
            self = .link(kind: try values.decode(LinkKind.self, forKey: .kind), target: try values.decode(String.self, forKey: .target))
        case "image":
            self = .image(path: try values.decode(String.self, forKey: .path), type: try values.decode(String.self, forKey: .type),
                          data: try values.decode(String.self, forKey: .data))
        case "lossy":
            self = .lossy(path: try values.decode(String.self, forKey: .path), reasons: try values.decode([String].self, forKey: .reasons))
        case "error":
            self = .error(message: try values.decode(String.self, forKey: .message))
        default:
            self = .mark(try ReaderAction(from: decoder))
        }
    }
}

/// The web page with Hubble.md's Markdown editor.
///
/// One page serves every file of the file paper, so a change of file does not
/// load the page again. `WebPageBridge` calls the functions on `window.piper`,
/// and the page sends messages to the `editor` handler. See `web/src/bridge.ts`.
@MainActor
final class EditorPage: NSObject, WKScriptMessageHandlerWithReply {
    private struct Shown: Equatable {
        let session: ObjectIdentifier
        let path: String
        let mode: String
        var revision: Int
    }

    private struct Show {
        let request: EditorOpenRequest
        let session: ObjectIdentifier
        let revision: Int
        let theme: EditorTheme
        let anchor: String?
        let anchorRequest: UUID
        let notes: [ReaderPageNote]
    }

    let webView: EditorWebView
    private weak var files: FileEditor?
    private let assets: AssetSchemeHandler
    private let bridge: WebPageBridge
    private var shown: Shown?
    private var shownTheme: EditorTheme?
    private var shownHeader: [String?]?
    private var shownAnchorRequest: UUID?
    private var shownNotes: [ReaderPageNote]?
    private var last: Show?

    init(files: FileEditor) {
        self.files = files
        let configuration = WKWebViewConfiguration()
        assets = AssetSchemeHandler { [weak files] in files?.library.vault }
        configuration.setURLSchemeHandler(assets, forURLScheme: AssetSchemeHandler.scheme)
        configuration.websiteDataStore = .nonPersistent()
        webView = EditorWebView(frame: .zero, configuration: configuration)
        // Only an embed loads a file of the folder in a frame.
        bridge = WebPageBridge(view: webView, page: "editor",
                               allowsFrame: { $0.scheme == AssetSchemeHandler.scheme || $0.absoluteString == "about:blank" },
                               report: { [weak files] in files?.messages.report($0) })
        super.init()
        configuration.userContentController.addScriptMessageHandler(WeakMessageHandler(self), contentWorld: .page, name: "editor")
        webView.underPageBackgroundColor = PiperTheme.paperNS
        webView.setAccessibilityLabel("Page")
        webView.find = { [weak self] in self?.bridge.call("find") }
        bridge.reloaded = { [weak self] in self?.reload() }
        bridge.load()
    }

    /// Shows a file and its margin notes. A new file or a new mode opens the
    /// file again. A new revision of the same file loads the disk text with no
    /// undo step. A new anchor request scrolls to the anchor.
    func show(_ request: EditorOpenRequest, session: ObjectIdentifier, revision: Int, theme: EditorTheme,
              anchor: String?, anchorRequest: UUID, notes: [ReaderPageNote]) {
        last = Show(request: request, session: session, revision: revision, theme: theme,
                    anchor: anchor, anchorRequest: anchorRequest, notes: notes)
        if theme != shownTheme {
            shownTheme = theme
            bridge.call("theme", theme)
        }
        let header = [request.header, request.title]
        if shown?.session != session || shown?.path != request.path || shown?.mode != request.mode {
            shown = Shown(session: session, path: request.path, mode: request.mode, revision: revision)
            shownHeader = header
            shownAnchorRequest = nil
            bridge.call("open", request)
        }
        if shown?.revision != revision {
            shown?.revision = revision
            bridge.call("replace", request.text)
        }
        if header != shownHeader {
            shownHeader = header
            bridge.call("header", request.header, request.title)
        }
        if anchorRequest != shownAnchorRequest {
            shownAnchorRequest = anchorRequest
            if let anchor { bridge.call("scrollTo", anchor) }
        }
        if notes != shownNotes {
            shownNotes = notes
            bridge.call("setNotes", notes)
        }
    }

    /// Shows the last state again on a page that loaded again.
    private func reload() {
        shown = nil
        shownTheme = nil
        shownHeader = nil
        shownAnchorRequest = nil
        shownNotes = nil
        if let last {
            show(last.request, session: last.session, revision: last.revision, theme: last.theme,
                 anchor: last.anchor, anchorRequest: last.anchorRequest, notes: last.notes)
        }
    }

    /// The text in the editor now, which can be newer than the last `change`
    /// message. Nil when the page shows no file.
    func flush() async throws -> (path: String, text: String)? {
        guard let path = shown?.path, let text = try await bridge.value("flush") as? String else { return nil }
        return (path, text)
    }

    func assetChanged(_ path: String) {
        bridge.call("assetChanged", path)
    }

    // MARK: Messages

    func userContentController(_ controller: WKUserContentController, didReceive message: WKScriptMessage) async -> (Any?, String?) {
        guard let files, let decoded: EditorMessage = bridge.decode(message) else { return (nil, nil) }
        switch decoded {
        case .ready:
            bridge.pageReady()
        case .change(let path, let text):
            files.editorChanged(path: path, text: text)
        case .link(let kind, let target):
            files.openEditorLink(kind: kind, target: target)
        case .image(let path, let type, let data):
            do { return (try files.saveEditorImage(for: path, type: type, base64: data), nil) }
            catch {
                files.messages.report(error)
                return (nil, error.localizedDescription)
            }
        case .lossy(let path, let reasons):
            files.editors[path]?.lossy = reasons
        case .error(let message):
            bridge.report(PiperError("The editor page failed. \(message)"))
        case .mark(let action):
            if let path = shown?.path { files.performFileAction(action, path: path) }
        }
        return (nil, nil)
    }
}

final class EditorWebView: WKWebView {
    var find: () -> Void = {}

    /// Edit > Paste pastes plain text in the text views of Piper. The editor
    /// reads images and rich text from the pasteboard, so it takes a full paste.
    @objc func pasteAsPlainText(_ sender: Any?) {
        NSApp.sendAction(#selector(NSText.paste(_:)), to: self, from: sender)
    }

    /// Edit > Find, and Find in File of the command palette.
    @objc func findInPage(_ sender: Any?) {
        find()
    }
}

/// The user content controller keeps its handlers. This keeps the page free to go.
private final class WeakMessageHandler: NSObject, WKScriptMessageHandlerWithReply {
    weak var target: EditorPage?

    init(_ target: EditorPage) { self.target = target }

    @MainActor
    func userContentController(_ controller: WKUserContentController, didReceive message: WKScriptMessage) async -> (Any?, String?) {
        await target?.userContentController(controller, didReceive: message) ?? (nil, nil)
    }
}

/// Serves the files of the open folder at `piper-asset://folder/<path>`, for
/// images and embeds. A path that leaves the folder fails.
@MainActor
final class AssetSchemeHandler: NSObject, WKURLSchemeHandler {
    static let scheme = "piper-asset"
    private let vault: () -> Vault?

    init(vault: @escaping () -> Vault?) {
        self.vault = vault
    }

    func webView(_ webView: WKWebView, start task: any WKURLSchemeTask) {
        guard let url = task.request.url, let vault = vault() else {
            task.didFailWithError(URLError(.fileDoesNotExist))
            return
        }
        do {
            let (data, type) = try Self.load(url, from: vault)
            var headers = ["Content-Type": type, "Content-Length": String(data.count), "Cache-Control": "no-store"]
            // An embed runs in a sandbox with no access to the page or to the folder.
            if type == "text/html" { headers["Content-Security-Policy"] = "sandbox allow-scripts allow-forms" }
            guard let response = HTTPURLResponse(url: url, statusCode: 200, httpVersion: "HTTP/1.1", headerFields: headers) else {
                throw URLError(.cannotParseResponse)
            }
            task.didReceive(response)
            task.didReceive(data)
            task.didFinish()
        } catch {
            task.didFailWithError(error)
        }
    }

    func webView(_ webView: WKWebView, stop task: any WKURLSchemeTask) {}

    /// The bytes and the MIME type of the file for a URL. The path is relative to the folder root.
    nonisolated static func load(_ url: URL, from vault: Vault) throws -> (Data, String) {
        let path = String(url.path.drop { $0 == "/" })
        guard !path.isEmpty else { throw URLError(.fileDoesNotExist) }
        let file = try vault.containedURL(path)
        let data = try Data(contentsOf: file)
        let type = UTType(filenameExtension: file.pathExtension)?.preferredMIMEType ?? "application/octet-stream"
        return (data, type)
    }
}

/// The editor page in the file paper. The paper moves the one web view of the
/// page into its own container.
struct EditorPane: NSViewRepresentable {
    let page: EditorPage
    let request: EditorOpenRequest
    let session: EditorSession
    let theme: EditorTheme
    let anchor: String?
    let anchorRequest: UUID
    let notes: [ReaderPageNote]

    func makeNSView(context: Context) -> NSView {
        let container = NSView()
        attach(to: container)
        return container
    }

    func updateNSView(_ container: NSView, context: Context) {
        if page.webView.superview !== container { attach(to: container) }
        page.show(request, session: ObjectIdentifier(session), revision: session.revision, theme: theme,
                  anchor: anchor, anchorRequest: anchorRequest, notes: notes)
    }

    private func attach(to container: NSView) {
        let view = page.webView
        view.removeFromSuperview()
        view.frame = container.bounds
        view.autoresizingMask = [.width, .height]
        container.addSubview(view)
    }

    /// The request for the open file of the editor.
    @MainActor
    static func request(for session: EditorSession, files: FileEditor, source: Bool) -> EditorOpenRequest {
        let document = session.document
        var byline = [document.modifiedAt.formatted(date: .long, time: .shortened)]
        let words = ReadingTime.words(in: document.body)
        if words > 0 { byline.append("\(ReadingTime.minutes(words: words)) min read") }
        switch session.status {
        case .saved: byline.append("Saved")
        case .conflict, .failed: byline.append("Not saved")
        case .opened: break
        }
        let hasTitle = document.body.trimmingCharacters(in: .whitespacesAndNewlines).hasPrefix("# ")
        let targets = files.library.files.filter(\.isMarkdown).map { file in
            EditorOpenRequest.WikiTarget(path: file.id, target: (file.id as NSString).deletingPathExtension, title: file.title)
        }
        return EditorOpenRequest(path: session.path, text: session.text,
                                 mode: source ? "source" : "rich", wikiTargets: targets,
                                 header: byline.joined(separator: " · "), title: hasTitle ? nil : document.title)
    }
}

/// The bar over the editor when Piper stopped saving, or when the Preview tab
/// cannot edit the file.
struct EditorBanner: View {
    @Bindable var files: FileEditor
    let session: EditorSession

    var body: some View {
        if session.status == .conflict {
            bar(files.sessionWrote(session.path)
                ? "Claude changed this file while you edited it. Piper stopped saving."
                : "This file changed on disk while you edited it. Piper stopped saving.") {
                Button("Keep Mine") { files.keepEditorText() }
                Button("Reload") { files.reloadEditorFromDisk() }
                    .keyboardShortcut(.defaultAction)
            }
        } else if case .failed(let reason) = session.status {
            bar("Piper could not save this file. \(reason)") {
                Button("Try Again") { files.saveEditor(session) }
            }
        } else if !session.lossy.isEmpty, !files.showsFileSource {
            bar("Preview cannot edit \(ListFormatter.localizedString(byJoining: session.lossy)) without losing them. Edit this file in Source.") {
                Button("Edit in Source") { files.showsFileSource = true }
            }
        }
    }

    private func bar(_ text: String, @ViewBuilder actions: () -> some View) -> some View {
        HStack(spacing: 10) {
            Image(systemName: "exclamationmark.triangle.fill")
                .foregroundStyle(PiperTheme.warning)
            Text(text)
                .lineLimit(2)
                .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 12)
            actions()
        }
        .font(PiperTheme.paperUI(.body))
        .padding(.horizontal, 16)
        .padding(.vertical, 8)
        .background(PiperTheme.warningFill)
        .overlay(alignment: .bottom) { Divider() }
    }
}
