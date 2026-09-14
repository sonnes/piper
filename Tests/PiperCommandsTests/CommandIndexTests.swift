import XCTest
@testable import PiperCommands

final class CommandIndexTests: XCTestCase {
    private var fixtures: CommandFixtures!

    override func setUpWithError() throws {
        fixtures = try CommandFixtures()
    }

    override func tearDown() {
        fixtures.remove()
        fixtures = nil
    }

    func testCommandReadsDescriptionAndArgumentHint() throws {
        try fixtures.writeCommand("capture", scope: .wiki, text: """
        ---
        description: Fetch a page and save it as a Markdown note
        argument-hint: <url>
        ---

        Fetch the page at $ARGUMENTS.
        """)

        let commands = CommandIndex.all(wikiRoot: fixtures.wikiRoot, homeRoot: fixtures.homeRoot)

        XCTAssertEqual(commands.count, 1)
        XCTAssertEqual(commands[0].name, "capture")
        XCTAssertEqual(commands[0].summary, "Fetch a page and save it as a Markdown note")
        XCTAssertEqual(commands[0].argumentHint, "<url>")
        XCTAssertTrue(commands[0].takesArguments)
        XCTAssertEqual(commands[0].scope, .wiki)
    }

    func testCommandWithoutArgumentHintTakesNoArguments() throws {
        try fixtures.writeCommand("review", scope: .wiki, text: """
        ---
        description: List stale files
        ---
        """)

        let commands = CommandIndex.all(wikiRoot: fixtures.wikiRoot, homeRoot: fixtures.homeRoot)

        XCTAssertEqual(commands[0].argumentHint, "")
        XCTAssertFalse(commands[0].takesArguments)
    }

    func testMissingClaudeDirectoryGivesAnEmptyList() {
        let commands = CommandIndex.all(wikiRoot: fixtures.wikiRoot, homeRoot: fixtures.homeRoot)

        XCTAssertTrue(commands.isEmpty)
    }

    func testPersonalScopeCarriesItsTag() throws {
        try fixtures.writeCommand("commit", scope: .personal, text: """
        ---
        description: Create a single git commit
        ---
        """)

        let commands = CommandIndex.all(wikiRoot: fixtures.wikiRoot, homeRoot: fixtures.homeRoot)

        XCTAssertEqual(commands.count, 1)
        XCTAssertEqual(commands[0].scope, .personal)
        XCTAssertEqual(commands[0].scope.tag, "personal")
    }

    func testWikiCommandWinsOverAPersonalCommandOfTheSameName() throws {
        try fixtures.writeCommand("capture", scope: .personal, text: """
        ---
        description: The personal one
        ---
        """)
        try fixtures.writeCommand("capture", scope: .wiki, text: """
        ---
        description: The Wiki one
        ---
        """)

        let commands = CommandIndex.all(wikiRoot: fixtures.wikiRoot, homeRoot: fixtures.homeRoot)

        XCTAssertEqual(commands.count, 1)
        XCTAssertEqual(commands[0].scope, .wiki)
        XCTAssertEqual(commands[0].summary, "The Wiki one")
        XCTAssertEqual(commands[0].scope.tag, "")
    }

    func testCommandsSortByName() throws {
        try fixtures.writeCommand("review", scope: .wiki, text: "---\ndescription: b\n---")
        try fixtures.writeCommand("capture", scope: .wiki, text: "---\ndescription: a\n---")
        try fixtures.writeCommand("index", scope: .personal, text: "---\ndescription: c\n---")

        let commands = CommandIndex.all(wikiRoot: fixtures.wikiRoot, homeRoot: fixtures.homeRoot)

        XCTAssertEqual(commands.map(\.name), ["capture", "index", "review"])
    }
}
