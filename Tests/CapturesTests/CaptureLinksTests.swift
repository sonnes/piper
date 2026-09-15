import Captures
import Foundation
import XCTest

final class CaptureLinksTests: XCTestCase {
    func testLinksPreserveTextAndOrderAndDeduplicateDestinations() {
        let text = "👋 नमस्ते https://example.com/路径?q=hello#part.\nThen https://swift.org and https://swift.org"
        let links = CaptureLinks(text)
        XCTAssertEqual(String(links.text.characters), text)
        XCTAssertEqual(links.urls.map(\.absoluteString), [
            "https://example.com/%E8%B7%AF%E5%BE%84?q=hello#part", "https://swift.org"
        ])
        XCTAssertEqual(links.text.runs.compactMap(\.link).count, 3)
        XCTAssertNil(links.standaloneURL)
    }

    func testOnlyAWholeURLAutomaticallyOpens() {
        for text in ["https://example.com/path?q=one#two", "  https://example.com/path?q=one#two\n"] {
            XCTAssertEqual(CaptureLinks(text).standaloneURL?.absoluteString, "https://example.com/path?q=one#two")
        }
        for text in ["A note", "https://example.com/path This is a note", "https://example.com/path\nSecond line",
                     "Read https://example.com", "https://example.com https://swift.org", "[Article](https://example.com)"] {
            XCTAssertNil(CaptureLinks(text).standaloneURL, text)
        }
        XCTAssertEqual(CaptureLinks("www.swift.org").standaloneURL?.absoluteString, "http://www.swift.org")
    }

    func testMarkdownAndSurroundingParenthesesKeepTheDestination() {
        for text in ["[Article](https://example.com/a_(b))", "Read (https://example.com/a_(b))."] {
            let links = CaptureLinks(text)
            XCTAssertEqual(links.urls.map(\.absoluteString), ["https://example.com/a_(b)"])
            XCTAssertNil(links.standaloneURL)
            let range = links.text.runs.first(where: { $0.link != nil })!.range
            XCTAssertEqual(String(links.text[range].characters), "https://example.com/a_(b)")
            XCTAssertEqual(String(links.text.characters), text)
        }
        XCTAssertEqual(CaptureLinks("https://example.com/a_(b)").standaloneURL?.absoluteString, "https://example.com/a_(b)")
        XCTAssertEqual(CaptureLinks("[Article](https://example.com/path \"Title\")").urls.map(\.absoluteString),
                       ["https://example.com/path"])
    }

    func testNonWebLinksRemainPlainText() {
        let text = "me@example.com mailto:me@example.com file:///tmp/file javascript:alert(1) ftp://example.com"
        let links = CaptureLinks(text)
        XCTAssertTrue(links.urls.isEmpty)
        XCTAssertTrue(links.text.runs.allSatisfy { $0.link == nil })
        XCTAssertNil(links.standaloneURL)
        XCTAssertEqual(String(links.text.characters), text)
        for value in ["https:path", "http:///", "file:///tmp/file", "javascript:alert(1)"] {
            XCTAssertFalse(CaptureLinks.isWebURL(URL(string: value)!))
        }
        XCTAssertTrue(CaptureLinks.isWebURL(URL(string: "HTTPS://example.com")!))
    }
}
