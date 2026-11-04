import AppKit
import SwiftUI
import UniformTypeIdentifiers
import Vault
import WebKit

/// The reading preferences that the editor page applies.
struct EditorTheme: Encodable, Equatable {
    let theme: String
    let font: String
    let size: Double
    let appearance: String
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
    let editable: Bool
    /// `rich` for the Preview tab, `source` for the Source tab.
    let mode: String
    let wikiTargets: [WikiTarget]
    /// The byline: the date, the reading time, and the save state.
    let header: String
    /// The title over a file whose body has no heading.
    let title: String?
    let anchor: String?
}

/// The web page with Hubble.md's Markdown editor.
///
/// One page serves every file of the main window, so a change of file does not
/// load the page again. Piper calls the functions on `window.piper`, and the page
/// sends messages to the `editor` handler. See `web/src/bridge.ts`.
@MainActor
final class EditorPage: NSObject, WKScriptMessageHandlerWithReply, WKNavigationDelegate {
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
        let anchorRequest: UUID
    }

    let webView: EditorWebView
    private weak var model: AppModel?
    private let page: URL?
    private let assets: AssetSchemeHandler
    private var ready = false
    private var queue: [String] = []
    private var shown: Shown?
    private var shownTheme: EditorTheme?
    private var shownHeader: [String?]?
    private var shownAnchorRequest: UUID?
    private var shownNotes: [ReaderPageNote]?
    private var last: Show?

    init(model: AppModel) {
        self.model = model
        let configuration = WKWebViewConfiguration()
        assets = AssetSchemeHandler { [weak model] in model?.vault }
        configuration.setURLSchemeHandler(assets, forURLScheme: AssetSchemeHandler.scheme)
        configuration.websiteDataStore = .nonPersistent()
        webView = EditorWebView(frame: .zero, configuration: configuration)
        page = PiperTheme.resources.url(forResource: "editor", withExtension: "html")
        super.init()
        configuration.userContentController.addScriptMessageHandler(WeakMessageHandler(self), contentWorld: .page, name: "editor")
        webView.navigationDelegate = self
        webView.underPageBackgroundColor = PiperTheme.readerNS
        webView.setAccessibilityLabel("Page")
        load()
    }

    private func load() {
        guard let page else { return }
        webView.loadFileURL(page, allowingReadAccessTo: page.deletingLastPathComponent())
    }

    /// Shows a file. A new file or a new mode opens the file again. A new
    /// revision of the same file loads the disk text with no undo step.
    func show(_ request: EditorOpenRequest, session: ObjectIdentifier, revision: Int, theme: EditorTheme, anchorRequest: UUID) {
        last = Show(request: request, session: session, revision: revision, theme: theme, anchorRequest: anchorRequest)
        if theme != shownTheme {
            shownTheme = theme
            call("theme", theme)
        }
        let header = [request.header, request.title]
        if shown?.session != session || shown?.path != request.path || shown?.mode != request.mode {
            shown = Shown(session: session, path: request.path, mode: request.mode, revision: revision)
            shownHeader = header
            shownAnchorRequest = anchorRequest
            call("open", request)
            return
        }
        if shown?.revision != revision {
            shown?.revision = revision
            call("replace", request.text)
        }
        if header != shownHeader {
            shownHeader = header
            call("header", header)
        }
        if anchorRequest != shownAnchorRequest {
            shownAnchorRequest = anchorRequest
            if let anchor = request.anchor { call("scrollTo", anchor) }
        }
    }

    /// The text in the editor now, which can be newer than the last `change` message.
    func flush() async -> (path: String, text: String)? {
        guard ready, let path = shown?.path,
              let text = try? await webView.evaluateJavaScript("window.piper.flush()") as? String else { return nil }
        return (path, text)
    }

    /// The margin notes of the open file. The page draws a card for each note and question.
    func setNotes(_ notes: [ReaderPageNote]) {
        guard notes != shownNotes else { return }
        shownNotes = notes
        call("setNotes", notes)
    }

    /// Reloads the embeds that show an HTML file of the folder.
    func assetChanged(_ path: String) {
        call("assetChanged", path)
    }

    func command(_ name: String) {
        call("command", name)
    }

    private func call(_ function: String, _ value: some Encodable) {
        guard let data = try? JSONEncoder().encode(value) else { return }
        let script = "window.piper.\(function)(\(String(decoding: data, as: UTF8.self)))"
        if ready { webView.evaluateJavaScript(script) } else { queue.append(script) }
    }

    private func call(_ function: String, _ values: [String?]) {
        guard let data = try? JSONEncoder().encode(values) else { return }
        let script = "window.piper.\(function)(...\(String(decoding: data, as: UTF8.self)))"
        if ready { webView.evaluateJavaScript(script) } else { queue.append(script) }
    }

    // MARK: Messages

    func userContentController(_ controller: WKUserContentController, didReceive message: WKScriptMessage) async -> (Any?, String?) {
        guard message.frameInfo.isMainFrame, message.frameInfo.request.url == page,
              let body = message.body as? [String: Any], let action = body["action"] as? String,
              let model else { return (nil, nil) }
        switch action {
        case "ready":
            ready = true
            let pending = queue
            queue = []
            for script in pending { _ = try? await webView.evaluateJavaScript(script) }
        case "change":
            guard let path = body["path"] as? String, let text = body["text"] as? String else { break }
            model.editorChanged(path: path, text: text)
        case "link":
            guard let kind = body["kind"] as? String, let target = body["target"] as? String else { break }
            model.openEditorLink(kind: kind, target: target)
        case "image":
            guard let path = body["path"] as? String, let data = body["data"] as? String else { break }
            do { return (try model.saveEditorImage(for: path, type: body["type"] as? String ?? "", base64: data), nil) }
            catch {
                model.store.report(error)
                return (nil, error.localizedDescription)
            }
        case "lossy":
            guard let path = body["path"] as? String else { break }
            model.editors[path]?.lossy = body["reasons"] as? [String] ?? []
        case "copy" where body["id"] != nil:
            if let path = shown?.path { model.performFileAction(body, path: path) }
        case "copy":
            guard let text = body["text"] as? String else { break }
            NSPasteboard.general.clearContents()
            NSPasteboard.general.setString(text, forType: .string)
        case "explain", "define", "ask", "note", "capture", "open", "continue", "followup":
            if let path = shown?.path { model.performFileAction(body, path: path) }
        default:
            break
        }
        return (nil, nil)
    }

    // MARK: Navigation

    /// A crash of the web content process leaves a blank view. The page loads
    /// again and shows the file when it reports that it is ready.
    func webViewWebContentProcessDidTerminate(_ webView: WKWebView) {
        ready = false
        queue = []
        shown = nil
        shownTheme = nil
        shownHeader = nil
        shownNotes = nil
        load()
        if let last {
            show(last.request, session: last.session, revision: last.revision, theme: last.theme, anchorRequest: last.anchorRequest)
        }
    }

    /// The page is local. Only an embed loads a file of the folder in a frame.
    func webView(_ webView: WKWebView, decidePolicyFor action: WKNavigationAction) async -> WKNavigationActionPolicy {
        guard let url = action.request.url, let frame = action.targetFrame else { return .cancel }
        if frame.isMainFrame { return url == page ? .allow : .cancel }
        return url.scheme == AssetSchemeHandler.scheme || url.absoluteString == "about:blank" ? .allow : .cancel
    }
}

/// The web view of the editor page.
final class EditorWebView: WKWebView {
    /// Edit > Paste pastes plain text in the text views of Piper. The editor
    /// reads images and rich text from the pasteboard, so it takes a full paste.
    @objc func pasteAsPlainText(_ sender: Any?) {
        NSApp.sendAction(#selector(NSText.paste(_:)), to: self, from: sender)
    }

    /// Edit > Find, when the editor does not have the keyboard focus.
    @objc func findInPage(_ sender: Any?) {
        evaluateJavaScript("window.piper.command(\"find\")")
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

/// The editor page in the detail pane. The pane moves the one web view of the
/// page into its own container.
struct EditorPane: NSViewRepresentable {
    let page: EditorPage
    let request: EditorOpenRequest
    let session: EditorSession
    let theme: EditorTheme
    let anchorRequest: UUID
    let notes: [ReaderPageNote]

    func makeNSView(context: Context) -> NSView {
        let container = NSView()
        attach(to: container)
        return container
    }

    func updateNSView(_ container: NSView, context: Context) {
        if page.webView.superview !== container { attach(to: container) }
        page.show(request, session: ObjectIdentifier(session), revision: session.revision, theme: theme, anchorRequest: anchorRequest)
        page.setNotes(notes)
    }

    private func attach(to container: NSView) {
        let view = page.webView
        view.removeFromSuperview()
        view.frame = container.bounds
        view.autoresizingMask = [.width, .height]
        container.addSubview(view)
    }

    /// The request for the open file of the model.
    @MainActor
    static func request(for session: EditorSession, model: AppModel, source: Bool) -> EditorOpenRequest {
        let document = session.document
        var byline = [document.modifiedAt.formatted(date: .long, time: .shortened)]
        if let time = ReadingTime.text(of: document.body) { byline.append(time) }
        switch session.status {
        case .saved: byline.append("Saved")
        case .conflict, .failed: byline.append("Not saved")
        case .opened: break
        }
        let hasTitle = document.body.trimmingCharacters(in: .whitespacesAndNewlines).hasPrefix("# ")
        let targets = model.files.filter(\.isMarkdown).map { file in
            EditorOpenRequest.WikiTarget(path: file.id, target: (file.id as NSString).deletingPathExtension, title: file.title)
        }
        return EditorOpenRequest(path: session.path, text: session.text, editable: true,
                                 mode: source ? "source" : "rich", wikiTargets: targets,
                                 header: byline.joined(separator: " · "), title: hasTitle ? nil : document.title,
                                 anchor: model.requestedAnchor)
    }
}

/// The bar over the editor when Piper stopped saving, or when the Preview tab
/// cannot edit the file.
struct EditorBanner: View {
    let model: AppModel
    let session: EditorSession

    var body: some View {
        if session.status == .conflict {
            bar(model.sessionWrote(session.path)
                ? "Claude changed this file while you edited it. Piper stopped saving."
                : "This file changed on disk while you edited it. Piper stopped saving.") {
                Button("Keep Mine") { model.keepEditorText() }
                Button("Reload") { model.reloadEditorFromDisk() }
                    .keyboardShortcut(.defaultAction)
            }
        } else if case .failed(let reason) = session.status {
            bar("Piper could not save this file. \(reason)") {
                Button("Try Again") { model.saveEditor(session) }
            }
        } else if !session.lossy.isEmpty, !model.showsFileSource {
            bar("Preview cannot edit \(ListFormatter.localizedString(byJoining: session.lossy)) without losing them. Edit this file in Source.") {
                Button("Edit in Source") { model.showsFileSource = true }
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
        .font(PiperTheme.ui(AppDefaults.Editor.bannerFontSize))
        .padding(.horizontal, 16)
        .padding(.vertical, 8)
        .background(PiperTheme.warningFill)
        .overlay(alignment: .bottom) { Divider() }
    }
}

/// The reading time of a text, such as "6 min read".
enum ReadingTime {
    /// Nil for a text without words.
    static func text(of body: String) -> String? {
        let words = body.split(whereSeparator: \.isWhitespace).count
        guard words > 0 else { return nil }
        return "\(max(1, Int((Double(words) / AppDefaults.ArticleReader.wordsPerMinute).rounded()))) min read"
    }
}
