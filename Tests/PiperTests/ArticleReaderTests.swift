import XCTest
@testable import Piper
import Captures
import WebKit

@MainActor
final class ArticleReaderTests: XCTestCase {

    private let url = URL(string: "https://www.example.dev/notes/wal")!

    func testPageTextKeepsLongLinesAsParagraphs() throws {
        let text = """
        Home   Archive   About
        How the log works
        SQLite began with a rollback journal. Before it changed a page, it copied the old page.

        Write-ahead\u{00A0}logging turns this around. The database file stays as it was.
        Sign in
        """
        let article = try XCTUnwrap(ReaderArticle(url: url, title: "How the log works", pageText: text))
        XCTAssertEqual(article.site, "example.dev")
        XCTAssertEqual(article.title, "How the log works")
        XCTAssertEqual(article.texts, [
            "SQLite began with a rollback journal. Before it changed a page, it copied the old page.",
            "Write-ahead logging turns this around. The database file stays as it was."
        ])
        XCTAssertEqual(article.byline, ["1 min read"])
        XCTAssertNil(ReaderArticle(url: url, title: nil, pageText: "Menu\nSign in"))
    }

    func testABrowserHighlightFindsItsPlaceInPageText() throws {
        let article = try XCTUnwrap(ReaderArticle(url: url, title: nil, pageText: """
        SQLite began with a rollback journal. Before it changed a page, it copied the old page.
        Write-ahead logging turns this around. The database file stays as it was.
        """))
        let quote = NoteAnchor.normalized("copied the old page.\nWrite-ahead logging turns")
        let place = try XCTUnwrap(NoteAnchor(quote: quote, block: -1, offset: 0).locate(in: article.texts))
        XCTAssertEqual(place.block, 0)
        XCTAssertEqual(place.quote, "copied the old page.")
    }

    func testPageTextGivesTheReadingTime() {
        let words = Array(repeating: "word", count: 460).joined(separator: " ")
        XCTAssertEqual(CapturedSelection(text: "", sourceURL: nil, pageText: words).minutes, 2)
        XCTAssertNil(CapturedSelection(text: "", sourceURL: nil).minutes)
    }

    func testExtractionKeepsRepositoryArticleWithoutPageChrome() async throws {
        let article = try await extract("""
        <title>Repository</title><main>
        <h2>Repository navigation</h2><p>Notifications and repository controls with many words outside the article.</p>
        <article class="markdown-body"><h1>Read Me</h1>
        <p>The article explains how the application reads the screen and chooses its next action.</p>
        <h2>Install</h2><p>Install the application and open the folder to start the first session.</p></article>
        <h2>About</h2><p>Repository metadata repeats the summary and other information outside the article.</p>
        <h2>Languages</h2><p>Python and Shell are the languages that this repository uses for its tools.</p>
        </main>
        """)
        XCTAssertEqual(article.blocks.map(\.text), [
            "Read Me",
            "The article explains how the application reads the screen and chooses its next action.",
            "Install",
            "Install the application and open the folder to start the first session."
        ])
    }

    func testShortArticleKeepsItsStructureAndExcludesNavigation() async throws {
        let article = try await extract("""
        <title>Short Article</title><nav><p>A long navigation paragraph must stay outside the article even when the article has few blocks.</p></nav>
        <article><h1>Short Article</h1><h2>One Section</h2><p>This short article has one paragraph and keeps its heading.</p></article>
        """)
        XCTAssertEqual(article.blocks.map(\.kind), ["heading", "paragraph"])
        XCTAssertEqual(article.blocks.map(\.text), ["One Section", "This short article has one paragraph and keeps its heading."])
    }

    func testExtractionReadsPagesWithLineBreaks() async throws {
        let article = try await extract("""
        <title>Old Page</title><nav>Navigation contains a long sentence that must stay outside the article.</nav>
        <main>The first paragraph uses line breaks instead of paragraph elements.<br><br>The second paragraph also uses line breaks and contains the rest of the article.</main>
        """)
        XCTAssertEqual(article.blocks.map(\.text), [
            "The first paragraph uses line breaks instead of paragraph elements.",
            "The second paragraph also uses line breaks and contains the rest of the article."
        ])
    }

    private struct ExtractedArticle: Decodable {
        let blocks: [ReaderArticle.Block]
    }

    private func extract(_ html: String) async throws -> ExtractedArticle {
        let view = WKWebView()
        let loaded = expectation(description: "Load the article fixture")
        let delegate = PageLoadDelegate(loaded: loaded)
        view.navigationDelegate = delegate
        view.loadHTMLString(html, baseURL: url)
        await fulfillment(of: [loaded], timeout: 5)
        let result = try await view.evaluateJavaScript(ArticleLoader.script)
        let json = try XCTUnwrap(result as? String)
        return try JSONDecoder().decode(ExtractedArticle.self, from: Data(json.utf8))
    }

    private final class PageLoadDelegate: NSObject, WKNavigationDelegate {
        let loaded: XCTestExpectation
        init(loaded: XCTestExpectation) { self.loaded = loaded }
        func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) { loaded.fulfill() }
    }
}
