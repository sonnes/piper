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

    func testOnlyTheCapturesShowTheListPane() {
        let withList: [SidebarSelection] = [.inbox, .section("Reading"), .archived]
        let withoutList: [SidebarSelection] = [.clipboard, .folder("notes"), .file("notes/a.md"), .sessions("/Users/me/Wiki")]
        for selection in withList { XCTAssertTrue(selection.showsList, "\(selection)") }
        for selection in withoutList { XCTAssertFalse(selection.showsList, "\(selection)") }
        XCTAssertTrue(SidebarSelection.clipboard.showsCaptures)
    }

    func testAnOpenClaudeFolderKeyCannotMatchAFolderPath() {
        let key = SidebarOutline.sessionsExpandedKey("/Users/me/Wiki")
        XCTAssertTrue(key.hasPrefix("\u{1}"))
        XCTAssertNotEqual(key, SidebarOutline.inboxCollapsedKey)
        XCTAssertNotEqual(key, SidebarOutline.sessionsExpandedKey("/Users/me/Other"))
    }

    func testFileRowsShowTheKind() {
        XCTAssertEqual(SidebarOutline.fileIcon("claude-code.md"), "note")
        XCTAssertEqual(SidebarOutline.fileIcon("figure.png"), "image")
        XCTAssertEqual(SidebarOutline.fileIcon("page.html"), "web")
        XCTAssertEqual(SidebarOutline.fileIcon("captions.vtt"), "file")
    }

    func testFolderTilesAndSectionDotsTakeAColorByPositionAndALetter() {
        XCTAssertEqual(SidebarOutline.monogram("notes"), "N")
        XCTAssertEqual(SidebarOutline.monogram(".config"), "C")
        XCTAssertEqual(SidebarOutline.monogram("2026 journal"), "2")
        XCTAssertEqual(SidebarOutline.monogram("---"), "•")
        // Neighbors differ, and the colors repeat after the last one.
        let count = PiperTheme.tagsNS.count
        for index in 0..<count { XCTAssertNotEqual(SidebarOutline.tagColor(at: index), SidebarOutline.tagColor(at: index + 1)) }
        XCTAssertEqual(SidebarOutline.tagColor(at: count), SidebarOutline.tagColor(at: 0))
        XCTAssertEqual(SidebarOutline.tagColor(at: -1), SidebarOutline.tagColor(at: 0))
    }

    @MainActor
    func testEverySidebarGlyphLoadsAsATemplate() throws {
        for name in ["inbox", "clipboard", "archived", "claude", "folder", "note", "image", "web", "file"] {
            let image = try XCTUnwrap(SidebarIcon.glyph(name), name)
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
