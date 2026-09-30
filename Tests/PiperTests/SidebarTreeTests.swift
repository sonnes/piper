import PiperTree
import XCTest
@testable import Piper

final class SidebarTreeTests: XCTestCase {

    func testFileSelectionNamesItsFolderAndSurvivesASave() throws {
        var state = MainWindowState()
        state.selection = .file("sources/prompts/interview.md")
        XCTAssertEqual(state.selectedFolder, "sources/prompts")
        XCTAssertFalse(state.selection.showsCaptures)
        let data = try JSONEncoder().encode(state)
        XCTAssertEqual(try JSONDecoder().decode(MainWindowState.self, from: data).selection, .file("sources/prompts/interview.md"))
        XCTAssertEqual(SidebarSelection.file("index.md").folder, "")
    }

    func testFileRowsDropTheMarkdownExtensionAndShowTheKind() {
        XCTAssertEqual(SidebarOutline.fileTitle("claude-code.md"), "claude-code")
        XCTAssertEqual(SidebarOutline.fileTitle("2026-09-18-openui.html"), "2026-09-18-openui.html")
        XCTAssertEqual(SidebarOutline.fileSymbol("claude-code.md"), "doc.text")
        XCTAssertEqual(SidebarOutline.fileSymbol("figure.png"), "photo")
        XCTAssertEqual(SidebarOutline.fileSymbol("page.html"), "globe")
        XCTAssertEqual(SidebarOutline.fileSymbol("captions.vtt"), "doc")
    }

    func testTreeListsFilesUnderTheirFoldersAfterSubfolders() {
        let root = PathTreeBuilder.tree(paths: ["index.md", "topics/a.md", "sources/b.md", "sources/prompts/c.md"])
        let names = root.children.map { ($0.representedObject as! PathItem).name }
        XCTAssertEqual(names, ["sources", "topics", "index.md"])
        let sources = root.children[0].children.map { ($0.representedObject as! PathItem).name }
        XCTAssertEqual(sources, ["prompts", "b.md"])
    }
}
