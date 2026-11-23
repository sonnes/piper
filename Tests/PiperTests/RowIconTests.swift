import PiperTree
import XCTest
@testable import Piper

final class RowIconTests: XCTestCase {

    func testFileRowsShowTheKind() {
        XCTAssertEqual(RowIcon.fileIcon("claude-code.md"), "note")
        XCTAssertEqual(RowIcon.fileIcon("figure.png"), "image")
        XCTAssertEqual(RowIcon.fileIcon("page.html"), "web")
        XCTAssertEqual(RowIcon.fileIcon("captions.vtt"), "file")
    }

    func testFolderTilesAndSectionDotsTakeAColorByPositionAndALetter() {
        XCTAssertEqual(RowIcon.monogram("notes"), "N")
        XCTAssertEqual(RowIcon.monogram(".config"), "C")
        XCTAssertEqual(RowIcon.monogram("2026 journal"), "2")
        XCTAssertEqual(RowIcon.monogram("---"), "•")
        // Neighbors differ, and the colors repeat after the last one.
        let count = PiperTheme.tagsNS.count
        for index in 0..<count { XCTAssertNotEqual(RowIcon.tagColor(at: index), RowIcon.tagColor(at: index + 1)) }
        XCTAssertEqual(RowIcon.tagColor(at: count), RowIcon.tagColor(at: 0))
        XCTAssertEqual(RowIcon.tagColor(at: -1), RowIcon.tagColor(at: 0))
    }

    @MainActor
    func testEveryGlyphLoadsAsATemplate() throws {
        for name in ["inbox", "clipboard", "archived", "claude", "folder", "note", "image", "web", "file"] {
            let image = try XCTUnwrap(RowIcon.glyph(name), name)
            XCTAssertTrue(image.isTemplate, name)
        }
    }

    func testTreeListsFilesUnderTheirFoldersAfterSubfolders() {
        let root = PathTreeBuilder.tree(paths: ["index.md", "topics/a.md", "sources/b.md", "sources/prompts/c.md"])
        let names = root.children.map { ($0.representedObject as! PathItem).name }
        XCTAssertEqual(names, ["sources", "topics", "index.md"])
        let sources = root.children[0].children.map { ($0.representedObject as! PathItem).name }
        XCTAssertEqual(sources, ["prompts", "b.md"])
    }
}
