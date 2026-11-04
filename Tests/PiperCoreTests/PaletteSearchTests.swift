import PiperCore
import XCTest

final class PaletteSearchTests: XCTestCase {
    func testScoresRankExactOverPrefixOverSubstringOverSubsequence() {
        XCTAssertEqual(PaletteSearch.score("tea notes", "Tea-Notes"), 1)
        XCTAssertEqual(PaletteSearch.score("tea", "Tea notes"), 0.9)
        XCTAssertEqual(PaletteSearch.score("notes", "Tea notes"), 0.75)
        XCTAssertEqual(PaletteSearch.score("tns", "Tea notes"), 0.45)
        XCTAssertEqual(PaletteSearch.score("xyz", "Tea notes"), 0)
        XCTAssertEqual(PaletteSearch.score("", "Anything"), 1)
    }

    func testAFileNameMatchRanksOverAFolderNameMatch() {
        let inName = PaletteSearch.score("report", path: "notes/report.md", title: "Weekly")
        let inFolder = PaletteSearch.score("report", path: "report/notes.md", title: "Notes")
        XCTAssertGreaterThan(inName, inFolder)
    }

    func testExcerptsCutTheLineAroundTheMatch() throws {
        let line = String(repeating: "a", count: 60) + " Cancellation " + String(repeating: "b", count: 60)
        let excerpts = PaletteSearch.excerpts(of: "cancel", in: "First line\n" + line, context: 10)
        let excerpt = try XCTUnwrap(excerpts.first)
        XCTAssertEqual(excerpt.line, 1)
        XCTAssertTrue(excerpt.text.hasPrefix("…"))
        XCTAssertTrue(excerpt.text.hasSuffix("…"))
        XCTAssertEqual(String(excerpt.text[excerpt.match]), "Cancel")
    }

    func testExcerptsStopAtTheLimitAndNeedThreeCharacters() {
        let text = Array(repeating: "tea time", count: 10).joined(separator: "\n")
        XCTAssertEqual(PaletteSearch.excerpts(of: "tea", in: text).count, 3)
        XCTAssertTrue(PaletteSearch.excerpts(of: "te", in: text).isEmpty)
    }
}
