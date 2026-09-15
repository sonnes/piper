import AppKit
import Captures
import Observation
import PiperCore
import SwiftUI
import WebKit

struct NoteWebReader: View {

    // MARK: - Properties

    let url: URL
    let showNote: () -> Void
    let capture: (String, String, URL) -> Bool
    @State private var page = NoteWebPage()
    @State private var isCapturing = false
    @State private var captureMessage: String?

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 10) {
                Button("Show Note", action: showNote)
                Button { page.webView?.goBack() } label: { Image(systemName: "chevron.left") }
                    .disabled(!page.canGoBack)
                    .help("Back").accessibilityLabel("Back")
                Button { page.webView?.goForward() } label: { Image(systemName: "chevron.right") }
                    .disabled(!page.canGoForward)
                    .help("Forward").accessibilityLabel("Forward")
                Button { page.reload() } label: { Image(systemName: "arrow.clockwise") }
                    .help("Reload").accessibilityLabel("Reload")
                Text((page.url ?? url).absoluteString)
                    .lineLimit(1)
                    .truncationMode(.middle)
                    .textSelection(.enabled)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .help((page.url ?? url).absoluteString)
                Button { NSWorkspace.shared.open(page.url ?? url) } label: {
                    Image(systemName: "safari")
                }
                .help("Open in Browser").accessibilityLabel("Open in Browser")
            }
            .buttonStyle(.borderless)
            .font(PiperTheme.ui(12))
            .padding(10)
            Rule()
            NoteWebView(url: url, page: page)
                .overlay(alignment: .top) {
                    if page.isLoading { ProgressView().controlSize(.small).padding(12) }
                }
                .overlay {
                    if let error = page.errorMessage {
                        VStack(spacing: 12) {
                            Text("Cannot Open Page").font(.headline)
                            Text(error).multilineTextAlignment(.center)
                            Button("Retry") { page.reload() }
                        }
                        .padding(24)
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                        .background(PiperTheme.page)
                    }
                }
                .overlay(alignment: .bottom) {
                    VStack(spacing: AppDefaults.Reader.floatingActionSpacing) {
                        if let captureMessage {
                            Text(captureMessage)
                                .font(PiperTheme.ui(AppDefaults.FontSize.small))
                                .multilineTextAlignment(.center)
                                .padding(AppDefaults.Reader.floatingActionSpacing)
                                .background(.regularMaterial, in: Capsule())
                        }
                        Button {
                            Task { await capturePage() }
                        } label: {
                            Label(isCapturing ? "Capturing…" : "Capture", systemImage: "square.and.arrow.down")
                        }
                        .buttonStyle(.borderedProminent)
                        .buttonBorderShape(.capsule)
                        .controlSize(.large)
                        .tint(PiperTheme.accent)
                        .shadow(color: PiperTheme.ink.opacity(0.15), radius: AppDefaults.Reader.floatingActionShadow)
                        .disabled(isCapturing || page.isLoading || page.errorMessage != nil || page.url == nil)
                        .help("Save selected text, or the page text, to Inbox")
                        .accessibilityLabel("Capture Web Page")
                    }
                    .padding(AppDefaults.Reader.floatingActionInset)
                }
        }
        .onChange(of: page.url) { captureMessage = nil }
    }

    // MARK: - Capture

    private func capturePage() async {
        guard !isCapturing, let webView = page.webView else { return }
        isCapturing = true
        captureMessage = nil
        defer { isCapturing = false }

        do {
            // One evaluation keeps the text and source URL in the same document.
            let result = try await webView.evaluateJavaScript(
                """
                (() => {
                    const selection = window.getSelection()?.toString() ?? '';
                    return {
                        text: selection.trim() ? selection : (document.body?.innerText ?? ''),
                        title: document.title,
                        url: location.href
                    };
                })()
                """,
                in: nil, contentWorld: .defaultClient
            )
            guard let values = result as? [String: Any], let text = values["text"] as? String,
                  let location = values["url"] as? String, let sourceURL = URL(string: location),
                  CaptureLinks.isWebURL(sourceURL) else {
                throw PiperError("Cannot read this page. Reload it and try again.")
            }
            guard !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
                throw PiperError("This page has no text to capture.")
            }
            let title = (values["title"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            let source = title.isEmpty ? (sourceURL.host ?? "Web Page") : title
            captureMessage = capture(text, source, sourceURL) ? "Saved to Inbox" : "Capture was not saved. Try again."
        } catch {
            captureMessage = error.localizedDescription
        }
    }
}

private struct NoteWebView: NSViewRepresentable {
    let url: URL
    let page: NoteWebPage

    func makeNSView(context: Context) -> WKWebView {
        let view = WKWebView(frame: .zero)
        view.navigationDelegate = page
        view.uiDelegate = page
        view.allowsBackForwardNavigationGestures = true
        view.setAccessibilityLabel("Inbox web page")
        page.webView = view
        return view
    }

    func updateNSView(_ view: WKWebView, context: Context) {
        page.load(url, in: view)
    }

    static func dismantleNSView(_ view: WKWebView, coordinator: ()) {
        view.navigationDelegate = nil
        view.uiDelegate = nil
        view.stopLoading()
    }
}

@MainActor @Observable
private final class NoteWebPage: NSObject {

    // MARK: - Properties

    @ObservationIgnored weak var webView: WKWebView?
    @ObservationIgnored private var requestedURL: URL?
    var url: URL?
    var isLoading = false
    var canGoBack = false
    var canGoForward = false
    var errorMessage: String?

    // MARK: - Navigation

    func load(_ url: URL, in view: WKWebView) {
        // The requested URL stays separate from redirects and navigation inside the page.
        guard requestedURL != url, CaptureLinks.isWebURL(url) else { return }
        requestedURL = url
        view.load(URLRequest(url: url))
    }

    func reload() {
        guard let webView else { return }
        if errorMessage != nil, let url = url ?? requestedURL {
            webView.load(URLRequest(url: url))
        } else {
            webView.reload()
        }
    }

    private func updateNavigation(_ view: WKWebView) {
        if let current = view.url, CaptureLinks.isWebURL(current) { url = current }
        canGoBack = view.canGoBack
        canGoForward = view.canGoForward
    }

    private func failed(_ error: Error) {
        let error = error as NSError
        guard error.domain != NSURLErrorDomain || error.code != NSURLErrorCancelled else { return }
        isLoading = false
        errorMessage = error.localizedDescription
    }
}

extension NoteWebPage: WKNavigationDelegate {
    func webView(_ webView: WKWebView, decidePolicyFor navigationAction: WKNavigationAction,
                 decisionHandler: @escaping (WKNavigationActionPolicy) -> Void) {
        guard navigationAction.targetFrame?.isMainFrame != false else {
            decisionHandler(.allow)
            return
        }
        guard let destination = navigationAction.request.url, CaptureLinks.isWebURL(destination) else {
            isLoading = false
            errorMessage = "This link cannot open here. Use Open in Browser."
            decisionHandler(.cancel)
            return
        }
        url = destination
        decisionHandler(.allow)
    }

    func webView(_ webView: WKWebView, decidePolicyFor navigationResponse: WKNavigationResponse,
                 decisionHandler: @escaping (WKNavigationResponsePolicy) -> Void) {
        if navigationResponse.isForMainFrame, !navigationResponse.canShowMIMEType {
            isLoading = false
            errorMessage = "This file cannot open here. Use Open in Browser."
            decisionHandler(.cancel)
        } else {
            decisionHandler(.allow)
        }
    }

    func webView(_ webView: WKWebView, didStartProvisionalNavigation navigation: WKNavigation!) {
        isLoading = true
        errorMessage = nil
    }

    func webView(_ webView: WKWebView, didReceiveServerRedirectForProvisionalNavigation navigation: WKNavigation!) {
        updateNavigation(webView)
    }

    func webView(_ webView: WKWebView, didCommit navigation: WKNavigation!) {
        updateNavigation(webView)
    }

    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        isLoading = false
        updateNavigation(webView)
    }

    func webView(_ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!, withError error: Error) {
        failed(error)
    }

    func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) {
        failed(error)
    }

    func webViewWebContentProcessDidTerminate(_ webView: WKWebView) {
        isLoading = false
        errorMessage = "The page stopped. Select Retry to reload it."
    }
}

extension NoteWebPage: WKUIDelegate {
    func webView(_ webView: WKWebView, createWebViewWith configuration: WKWebViewConfiguration,
                 for navigationAction: WKNavigationAction, windowFeatures: WKWindowFeatures) -> WKWebView? {
        if navigationAction.targetFrame == nil, let url = navigationAction.request.url, CaptureLinks.isWebURL(url) {
            webView.load(navigationAction.request)
        }
        return nil
    }
}
