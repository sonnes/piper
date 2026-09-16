import AppKit
import XCTest
@testable import Piper

@MainActor
final class SourceViewTests: XCTestCase {

    /// A long line must wrap inside a narrow pane instead of running past its edge.
    func testTheSourceTextWrapsAtTheWidthOfThePane() throws {
        let scroll = PlainTextPreview.makeScrollView()
        scroll.frame = NSRect(x: 0, y: 0, width: 300, height: 400)
        let editor = try XCTUnwrap(scroll.documentView as? NSTextView)
        editor.string = String(repeating: "word ", count: 400)
        scroll.layoutSubtreeIfNeeded()
        editor.layoutManager?.ensureLayout(for: try XCTUnwrap(editor.textContainer))

        XCTAssertLessThanOrEqual(editor.frame.width, scroll.contentSize.width)
        let used = try XCTUnwrap(editor.layoutManager?.usedRect(for: try XCTUnwrap(editor.textContainer)))
        XCTAssertLessThanOrEqual(used.width, scroll.contentSize.width)
        XCTAssertGreaterThan(used.height, 100, "The text wraps onto many lines")
    }
}
