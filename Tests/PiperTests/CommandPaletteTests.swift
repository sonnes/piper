import Vault
import XCTest
@testable import Piper

final class CommandPaletteTests: XCTestCase {
    private let files = [
        makeFile("# Cancellation rules\n", path: "Projects/Cancellation rules.md"),
        makeFile("# Agent request lifecycle\n\nCancel the run when the user stops.\n", path: "Architecture/Agent request lifecycle.md"),
        makeFile("# pi-go\n", path: "Projects/pi-go.md"),
    ]

    private func command(_ title: String) -> PaletteCommand { PaletteCommand(title: title, shortcut: "", run: {}) }

    private func ids(_ rows: [PaletteResults.Row]) -> [String] { rows.map(\.id) }

    func testTextFindsFilesByTitleFirst() {
        let results = PaletteResults.rank("cancel", files: files, recent: [], commands: [], recentCommands: [])
        XCTAssertEqual(ids(results.files), ["file:Projects/Cancellation rules.md"])
    }

    func testAnEmptyQueryListsRecentFiles() {
        let results = PaletteResults.rank("", files: files, recent: ["Projects/pi-go.md", "Missing.md"], commands: [], recentCommands: [])
        XCTAssertEqual(ids(results.files), ["file:Projects/pi-go.md"])
    }

    func testASlashListsOnlyCommandsWithRecentOnesFirst() {
        let commands = [command("Refresh"), command("Show Brief"), command("Show Source")]
        let results = PaletteResults.rank("/show", files: files, recent: [], commands: commands, recentCommands: ["Show Source"])
        XCTAssertTrue(results.files.isEmpty)
        XCTAssertEqual(ids(results.commands), ["command:Show Source", "command:Show Brief"])
    }

    func testLinesFindTextInsideFiles() {
        let rows = PaletteResults.lines("user stops", in: files)
        XCTAssertEqual(ids(rows), ["line:Architecture/Agent request lifecycle.md:2"])
    }

    func testRecentCommandsKeepTheNewestFirst() throws {
        let defaults = try XCTUnwrap(UserDefaults(suiteName: "CommandPaletteTests." + UUID().uuidString))
        PaletteRecents.add("Refresh", defaults)
        PaletteRecents.add("Show Brief", defaults)
        PaletteRecents.add("Refresh", defaults)
        XCTAssertEqual(PaletteRecents.titles(defaults), ["Refresh", "Show Brief"])
    }
}
