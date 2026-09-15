import XCTest
@testable import PiperCore

final class FrontmatterTests: XCTestCase {

    func testFileWithoutFrontmatterKeepsItsWholeBody() {
        let file = Frontmatter.parse("# Notes\n\nLoose text.\n")
        XCTAssertTrue(file.isEmpty)
        XCTAssertNil(file.problem)
        XCTAssertEqual(file.prefix, "")
        XCTAssertEqual(file.body, "# Notes\n\nLoose text.\n")
    }

    func testFrontmatterSplitsMetadataFromBody() {
        let file = Frontmatter.parse("---\ntitle: Payment retries\nowner: platform\n---\n\nBody text.\n")
        XCTAssertEqual(file.string("title"), "Payment retries")
        XCTAssertEqual(file.string("owner"), "platform")
        XCTAssertEqual(file.body, "\nBody text.\n")
        XCTAssertEqual(file.prefix, "---\ntitle: Payment retries\nowner: platform\n---\n")
        XCTAssertNil(file.problem)
    }

    func testBrokenYamlReportsAProblemAndKeepsTheBody() {
        let file = Frontmatter.parse("---\ntitle: [unclosed\n---\n\nBody.\n")
        XCTAssertNotNil(file.problem)
        XCTAssertEqual(file.body, "\nBody.\n")
    }

    func testCarriageReturnsDoNotHideTheBlock() {
        let file = Frontmatter.parse("---\r\ntitle: A\r\n---\r\n\r\nBody.\r\n")
        XCTAssertEqual(file.string("title"), "A")
    }

    func testStringsReadsAScalarOrAList() {
        let file = Frontmatter.parse("---\none: a\nmany:\n  - a\n  - b\n---\n")
        XCTAssertEqual(file.strings("one"), ["a"])
        XCTAssertEqual(file.strings("many"), ["a", "b"])
        XCTAssertEqual(file.strings("absent"), [])
    }

}

extension FrontmatterTests {

    /// A save rewrites the prefix verbatim, so the prefix must hold the bytes
    /// that the file already had.
    func testCarriageReturnsSurviveInThePrefixAndTheBody() {
        let prefix = "---\r\ntitle: 'Tea'\r\ncustom: [one, two]\r\n---\r\n"
        let raw = prefix + "\r\n# Tea\r\n\r\nOriginal.\r\n"
        let file = Frontmatter.parse(raw)
        XCTAssertEqual(file.prefix, prefix, "The prefix keeps the CRLF bytes of the original file")
        XCTAssertEqual(file.body, "\r\n# Tea\r\n\r\nOriginal.\r\n")
        XCTAssertEqual(file.prefix + file.body, raw, "prefix + body must rebuild the file exactly")
        XCTAssertEqual(file.string("title"), "Tea")
        XCTAssertEqual(file.strings("custom"), ["one", "two"])
        XCTAssertNil(file.problem)
    }

    func testLineFeedFilesRebuildExactlyToo() {
        let raw = "---\ntitle: A\n---\n\nBody.\n"
        let file = Frontmatter.parse(raw)
        XCTAssertEqual(file.prefix + file.body, raw)
    }
}
