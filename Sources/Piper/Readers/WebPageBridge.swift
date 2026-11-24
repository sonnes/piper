import Foundation
import WebKit

/// The Swift side of a local page of Piper: the editor page and the reader page.
///
/// Piper calls the functions on `window.piper` with JSON arguments. A call
/// waits until the page posts `ready`. Each call reports a JavaScript
/// exception. A crash of the web content process loads the page again, and
/// `reloaded` lets the owner show its last state again. Only the page itself
/// loads in the main frame.
@MainActor
final class WebPageBridge: NSObject {

    // MARK: - Properties

    private(set) weak var view: WKWebView?
    private let page: URL?
    private let allowsFrame: (URL) -> Bool
    private let report: (Error) -> Void
    /// Runs after a crash, when the page loads again. The owner forgets what
    /// the page shows and shows its last state again.
    var reloaded: () -> Void = {}
    private var ready = false
    private var queue: [String] = []

    // MARK: - Initialization

    /// The page is a resource of Piper, such as `editor` for `editor.html`.
    /// `allowsFrame` decides which addresses a frame in the page can load.
    init(view: WKWebView, page: String, allowsFrame: @escaping (URL) -> Bool = { _ in false },
         report: @escaping (Error) -> Void) {
        self.view = view
        self.page = PiperTheme.resources.url(forResource: page, withExtension: "html")
        self.allowsFrame = allowsFrame
        self.report = report
        super.init()
        view.navigationDelegate = self
    }

    // MARK: - Calls

    func load() {
        guard let page, let view else { return }
        view.loadFileURL(page, allowingReadAccessTo: page.deletingLastPathComponent())
    }

    /// Calls `window.piper.<name>` with the arguments. The call waits until the page is ready.
    func call(_ name: String, _ arguments: any Encodable...) {
        do {
            let script = try Self.script(name, arguments)
            if ready { run(script) } else { queue.append(script) }
        } catch {
            report(error)
        }
    }

    /// Calls `window.piper.<name>` now and returns its result. Nil when the page is not ready.
    func value(_ name: String, _ arguments: any Encodable...) async throws -> Any? {
        guard ready, let view else { return nil }
        return try await view.evaluateJavaScript(Self.script(name, arguments))
    }

    /// The script that calls `window.piper.<name>` with each argument as JSON.
    nonisolated static func script(_ name: String, _ arguments: [any Encodable]) throws -> String {
        let encoder = JSONEncoder()
        let list = try arguments.map { String(decoding: try encoder.encode($0), as: UTF8.self) }
        return "window.piper.\(name)(\(list.joined(separator: ", ")))"
    }

    private func run(_ script: String) {
        view?.evaluateJavaScript(script) { [weak self] _, error in
            if let error { self?.report(error) }
        }
    }

    // MARK: - Messages

    /// The message of the page as a value. Nil for a message from another
    /// frame. A message that does not decode goes to the report.
    func decode<Message: Decodable>(_ message: WKScriptMessage) -> Message? {
        guard message.frameInfo.isMainFrame, message.frameInfo.request.url == page else { return nil }
        do {
            return try Self.decode(message.body)
        } catch {
            report(error)
            return nil
        }
    }

    /// A message body, as WebKit gives it, as a value.
    nonisolated static func decode<Message: Decodable>(_ body: Any) throws -> Message {
        try JSONDecoder().decode(Message.self, from: JSONSerialization.data(withJSONObject: body))
    }

    /// The page posted `ready`. The calls that waited run now.
    func pageReady() {
        ready = true
        let pending = queue
        queue = []
        pending.forEach(run)
    }
}

// MARK: - WKNavigationDelegate

extension WebPageBridge: WKNavigationDelegate {

    /// A crash of the web content process leaves a blank view. The page loads
    /// again, and the calls of `reloaded` run when it is ready.
    func webViewWebContentProcessDidTerminate(_ webView: WKWebView) {
        ready = false
        queue = []
        load()
        reloaded()
    }

    func webView(_ webView: WKWebView, decidePolicyFor action: WKNavigationAction) async -> WKNavigationActionPolicy {
        guard let url = action.request.url, let frame = action.targetFrame else { return .cancel }
        if frame.isMainFrame { return url == page ? .allow : .cancel }
        return allowsFrame(url) ? .allow : .cancel
    }
}
