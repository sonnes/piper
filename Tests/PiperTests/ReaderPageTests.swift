import AppKit
import Captures
import WebKit
import XCTest
@testable import Piper

/// Loads the reader page in an offscreen web view and reads the messages that it sends to Piper.
@MainActor
final class ReaderPageTests: XCTestCase {

    private final class Messages: NSObject, WKScriptMessageHandler {
        var received: [[String: Any]] = []
        func userContentController(_ controller: WKUserContentController, didReceive message: WKScriptMessage) {
            if let body = message.body as? [String: Any] { received.append(body) }
        }
    }

    private var window: NSWindow!
    private var view: WKWebView!
    private let messages = Messages()

    override func setUp() async throws {
        let configuration = WKWebViewConfiguration()
        configuration.userContentController.add(messages, name: "piper")
        view = WKWebView(frame: NSRect(x: 0, y: 0, width: 712, height: 800), configuration: configuration)
        window = NSWindow(contentRect: NSRect(x: -10_000, y: -10_000, width: 712, height: 800),
                          styleMask: [.borderless], backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        window.contentView?.addSubview(view)
        let page = try XCTUnwrap(PiperTheme.resources.url(forResource: "reader", withExtension: "html"))
        view.loadFileURL(page, allowingReadAccessTo: page.deletingLastPathComponent())
        try await wait("The page is ready.") { self.messages.received.contains { $0["action"] as? String == "ready" } }
        _ = try await view.evaluateJavaScript("""
        window.piper.render({ site: "harbor.example", title: "Tide Tables", byline: ["Mara Vale"],
          blocks: [{ kind: "paragraph", text: "The tide turns twice a day at the harbor mouth." }] })
        """)
    }

    override func tearDown() async throws {
        window.close()
    }

    private func wait(_ message: String, _ condition: @escaping () -> Bool) async throws {
        let deadline = Date().addingTimeInterval(10)
        while Date() < deadline {
            if condition() { return }
            try await Task.sleep(for: .milliseconds(50))
        }
        XCTFail(message)
    }

    /// Selects "twice a day" in the first block.
    private func select() async throws {
        _ = try await view.evaluateJavaScript("""
        (() => {
          const text = document.querySelector('[data-b="0"]').firstChild;
          const range = document.createRange();
          range.setStart(text, 15);
          range.setEnd(text, 26);
          getSelection().removeAllRanges();
          getSelection().addRange(range);
        })()
        """)
    }

    private func highlights() -> [[String: Any]] {
        messages.received.filter { $0["action"] as? String == "highlight" }
    }

    func testHHighlightsTheSelectedText() async throws {
        try await select()
        let used = try await view.evaluateJavaScript("window.piper.key('h')") as? Bool
        XCTAssertEqual(used, true)
        try await wait("The page sends the highlight.") { !self.highlights().isEmpty }
        let message: ReaderPageMessage = try WebPageBridge.decode(try XCTUnwrap(highlights().first))
        XCTAssertEqual(message, .mark(.highlight(NoteAnchor(quote: "twice a day", block: 0, offset: 15), color: "yellow")))
    }

    func testEscapeOnTheNoteSlipKeepsTheHighlight() async throws {
        let hidden = try await view.evaluateJavaScript("getComputedStyle(document.querySelector('#noteline')).display") as? String
        XCTAssertEqual(hidden, "none", "The note slip waits for N.")
        try await select()
        _ = try await view.evaluateJavaScript("window.piper.key('n')")
        let slip = try await view.evaluateJavaScript("getComputedStyle(document.querySelector('#noteline')).display") as? String
        XCTAssertEqual(slip, "block", "The note slip opens under the passage.")
        let marked = try await view.evaluateJavaScript("document.querySelector('mark.pending')?.textContent") as? String
        XCTAssertEqual(marked, "twice a day")
        _ = try await view.evaluateJavaScript("""
        document.querySelector('#noteinput').dispatchEvent(new KeyboardEvent('keydown', { key: 'Escape', bubbles: true }))
        """)
        try await wait("Escape keeps the highlight.") { !self.highlights().isEmpty }
        XCTAssertFalse(messages.received.contains { $0["action"] as? String == "note" })
    }

    func testReturnOnTheNoteSlipSavesTheNote() async throws {
        try await select()
        _ = try await view.evaluateJavaScript("window.piper.key('n')")
        _ = try await view.evaluateJavaScript("""
        (() => {
          const input = document.querySelector('#noteinput');
          input.value = 'Check the almanac.';
          input.dispatchEvent(new KeyboardEvent('keydown', { key: 'Enter', bubbles: true }));
        })()
        """)
        try await wait("Return saves the note.") { self.messages.received.contains { $0["action"] as? String == "note" } }
        let note = try XCTUnwrap(messages.received.first { $0["action"] as? String == "note" })
        XCTAssertEqual(note["text"] as? String, "Check the almanac.")
    }

    func testALetterThatThePageDoesNotUseGoesToThePaper() async throws {
        _ = try await view.evaluateJavaScript("""
        document.body.dispatchEvent(new KeyboardEvent('keydown', { key: 't', bubbles: true }))
        """)
        try await wait("The page sends T to the paper.") {
            self.messages.received.contains { $0["action"] as? String == "key" && $0["key"] as? String == "t" }
        }
    }
}
