import Briefs
import Foundation
import WebKit

/// Loads the root page of each host with the sign-ins of the Web tab.
///
/// Piper makes each URL from a host, so the agent cannot put data in a URL.
/// A page that ends on a blocked or private host gives nothing.
@MainActor
final class BriefPageLoader {

    func load(_ hosts: [String], blocked: [String]) async -> [LoadedPage] {
        await withTaskGroup(of: LoadedPage?.self) { group in
            var pages: [LoadedPage] = []
            var next = hosts.makeIterator()
            var running = 0
            while true {
                while running < AppDefaults.Brief.concurrentPages, let host = next.next() {
                    running += 1
                    group.addTask { @MainActor in await SinglePage(host: host, blocked: blocked).load() }
                }
                guard running > 0, let page = await group.next() else { return pages }
                running -= 1
                if let page { pages.append(page) }
            }
        }
    }
}

/// One web view that loads one page.
@MainActor
private final class SinglePage: NSObject, WKNavigationDelegate {

    private static let script = """
    (() => {
      const links = [...document.querySelectorAll('a[href]')]
        .filter(a => /^https?:/.test(a.href))
        .map(a => ({ label: (a.innerText || a.title || '').trim().slice(0, 200), url: a.href }))
        .filter(link => link.label.length > 0);
      return JSON.stringify({ title: document.title, links });
    })()
    """

    private struct Extracted: Decodable {
        let title: String
        let links: [PageLink]
    }

    private let host: String
    private let blocked: [String]
    private var finished: CheckedContinuation<Bool, Never>?

    init(host: String, blocked: [String]) {
        self.host = host
        self.blocked = blocked
    }

    func load() async -> LoadedPage? {
        guard let url = URL(string: "https://\(host)/"), BlockedSites.allows(url.absoluteString, list: blocked) else { return nil }
        let view = WKWebView(frame: NSRect(origin: .zero, size: AppDefaults.Brief.loaderSize))
        view.navigationDelegate = self
        defer { view.stopLoading(); view.navigationDelegate = nil }

        let timeout = Task { [weak self] in
            try? await Task.sleep(for: AppDefaults.Brief.pageLoadTimeout)
            if !Task.isCancelled { self?.finish(false) }
        }
        defer { timeout.cancel() }
        let loaded = await withCheckedContinuation { continuation in
            finished = continuation
            view.load(URLRequest(url: url))
        }
        guard loaded, let finalURL = view.url, BlockedSites.allows(finalURL.absoluteString, list: blocked) else { return nil }

        try? await Task.sleep(for: AppDefaults.Brief.pageSettle)
        guard let current = view.url, BlockedSites.allows(current.absoluteString, list: blocked),
              let json = try? await view.evaluateJavaScript(Self.script, in: nil, contentWorld: .defaultClient) as? String,
              let page = try? JSONDecoder().decode(Extracted.self, from: Data(json.utf8)),
              !page.links.isEmpty else { return nil }
        return LoadedPage(host: host, title: page.title, links: page.links)
    }

    private func finish(_ loaded: Bool) {
        finished?.resume(returning: loaded)
        finished = nil
    }

    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) { finish(true) }
    func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) { finish(false) }
    func webView(_ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!, withError error: Error) { finish(false) }

    /// A redirect to a blocked or private host stops before the request leaves.
    func webView(_ webView: WKWebView, decidePolicyFor action: WKNavigationAction) async -> WKNavigationActionPolicy {
        guard action.targetFrame?.isMainFrame == true, let url = action.request.url else { return .allow }
        return BlockedSites.allows(url.absoluteString, list: blocked) ? .allow : .cancel
    }
}
