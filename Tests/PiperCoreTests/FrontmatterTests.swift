import XCTest
@testable import PiperCore

final class FrontmatterTests: XCTestCase {

    func testFileWithoutFrontmatterKeepsItsWholeBody() {
        let file = Frontmatter.parse("# Notes\n\nLoose text.\n")
        XCTAssertTrue(file.metadata.isEmpty)
        XCTAssertNil(file.problem)
        XCTAssertEqual(file.body, "# Notes\n\nLoose text.\n")
    }

    func testFrontmatterSplitsMetadataFromBody() {
        let file = Frontmatter.parse("---\ntitle: Payment retries\nowner: platform\n---\n\nBody text.\n")
        XCTAssertEqual(file.string("title"), "Payment retries")
        XCTAssertEqual(file.string("owner"), "platform")
        XCTAssertEqual(file.body, "\nBody text.\n")
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

}

extension FrontmatterTests {

    func testCarriageReturnsSurviveInTheBody() {
        let raw = "---\r\ntitle: 'Tea'\r\ncustom: [one, two]\r\n---\r\n\r\n# Tea\r\n\r\nOriginal.\r\n"
        let file = Frontmatter.parse(raw)
        XCTAssertEqual(file.body, "\r\n# Tea\r\n\r\nOriginal.\r\n")
        XCTAssertEqual(file.string("title"), "Tea")
        XCTAssertEqual(file.metadata["custom"] as? [String], ["one", "two"])
        XCTAssertNil(file.problem)
    }
}
