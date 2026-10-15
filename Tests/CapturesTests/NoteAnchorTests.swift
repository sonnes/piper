import XCTest
import Captures

final class NoteAnchorTests: XCTestCase {

    private let blocks = ["SQLite began with a journal.", "A reader keeps reading the old pages. The old pages stay.", "The end."]

    func testTheStoredPlaceWinsWhenItStillMatches() {
        let anchor = NoteAnchor(quote: "old pages", block: 1, offset: 42)
        XCTAssertEqual(anchor.locate(in: blocks), anchor)
    }

    func testAMovedQuoteIsFoundInItsBlockFirst() {
        let anchor = NoteAnchor(quote: "old pages", block: 1, offset: 3)
        XCTAssertEqual(anchor.locate(in: blocks), NoteAnchor(quote: "old pages", block: 1, offset: 27))
    }

    func testAQuoteInAnotherBlockIsFound() {
        let anchor = NoteAnchor(quote: "The end.", block: 0, offset: 0)
        XCTAssertEqual(anchor.locate(in: blocks), NoteAnchor(quote: "The end.", block: 2, offset: 0))
    }

    func testAMissingQuoteHasNoPlace() {
        XCTAssertNil(NoteAnchor(quote: "rollback", block: 0, offset: 0).locate(in: blocks))
        XCTAssertNil(NoteAnchor(quote: "", block: 0, offset: 0).locate(in: blocks))
        XCTAssertNil(NoteAnchor(quote: "journal", block: 9, offset: -4).locate(in: []))
    }

    func testOffsetsCountUTF16Units() {
        let anchor = NoteAnchor(quote: "pages", block: 0, offset: 3)
        XCTAssertEqual(anchor.locate(in: ["😀 pages"]), anchor)
    }

    func testAThreadReadsItsTurns() {
        let thread = NoteThread("Explain: wal-index\n\nA lookup table.\n\nIt maps pages.\n\nQ: Why a file?\n\nTo share it.")
        XCTAssertEqual(thread.title, "Explain: wal-index")
        XCTAssertEqual(thread.turns, [
            NoteThread.Turn(answer: "A lookup table.\n\nIt maps pages."),
            NoteThread.Turn(question: "Why a file?", answer: "To share it.")
        ])
    }

    func testAnAskThreadStartsWithItsQuestion() {
        let thread = NoteThread("Ask: one long read\n\nQ: Why does it block?")
        XCTAssertEqual(thread.turns, [NoteThread.Turn(question: "Why does it block?")])
        XCTAssertEqual(NoteThread("Explain: x").turns, [NoteThread.Turn()])
    }

    func testABrowserSelectionIsNormalized() {
        XCTAssertEqual(NoteAnchor.normalized("  one\u{00A0}long\n\n read\u{00AD}s\t "), "one long reads")
    }

    func testAQuoteOverTwoBlocksMarksItsStart() {
        let anchor = NoteAnchor(quote: "keeps reading the old pages. The old pages stay. The end.", block: -1, offset: 0)
        XCTAssertEqual(anchor.locate(in: blocks), NoteAnchor(quote: "keeps reading the old pages. The old pages stay.", block: 1, offset: 9))
    }

    func testAQuoteWithAMissingEndMatchesItsLongestStart() {
        let anchor = NoteAnchor(quote: "A reader keeps reading the new figures from the caption", block: -1, offset: 0)
        XCTAssertEqual(anchor.locate(in: blocks), NoteAnchor(quote: "A reader keeps reading the", block: 1, offset: 0))
        XCTAssertNil(NoteAnchor(quote: "keeps reading new", block: -1, offset: 0).locate(in: blocks))
    }

    func testAQuoteAfterAnEmptyBlockFindsItsBlock() {
        let blocks = ["Alpha beta gamma delta.", "", "One two three four five six."]
        let anchor = NoteAnchor(quote: "three four five six. Words that the article lost", block: -1, offset: 0)
        XCTAssertEqual(anchor.locate(in: blocks), NoteAnchor(quote: "three four five six.", block: 2, offset: 8))
    }

    func testTheCommentOfAnEditedQuoteFollowsTheFirstBlankLine() {
        let text = "the edited quote\n\nMy note.\n\nA second paragraph."
        XCTAssertEqual(HighlightText.comment(of: text, quote: "the original quote"), "My note.\n\nA second paragraph.")
        XCTAssertEqual(HighlightText.comment(of: "the edited quote", quote: "the original quote"), "")
        XCTAssertEqual(HighlightText.comment(of: "a quote\n\n  ", quote: nil), "")
    }
}

