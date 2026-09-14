import XCTest
@testable import PiperCommands

final class SkillIndexTests: XCTestCase {
    private var fixtures: CommandFixtures!

    override func setUpWithError() throws {
        fixtures = try CommandFixtures()
    }

    override func tearDown() {
        fixtures.remove()
        fixtures = nil
    }

    func testSkillNameComesFromTheFrontmatterNotTheFolder() throws {
        try fixtures.writeSkill(folder: "folder-name", scope: .wiki, text: """
        ---
        name: frontmatter-name
        description: Turn an article into a reading note.
        ---

        The body.
        """)

        let skills = SkillIndex.all(wikiRoot: fixtures.wikiRoot, homeRoot: fixtures.homeRoot)

        XCTAssertEqual(skills.count, 1)
        XCTAssertEqual(skills[0].name, "frontmatter-name")
    }

    func testSkillNameFallsBackToTheFolderName() throws {
        try fixtures.writeSkill(folder: "okf-bundle", scope: .wiki, text: """
        ---
        description: Validate an OKF bundle.
        ---
        """)

        let skills = SkillIndex.all(wikiRoot: fixtures.wikiRoot, homeRoot: fixtures.homeRoot)

        XCTAssertEqual(skills[0].name, "okf-bundle")
    }

    func testSkillSummaryShowsOnlyTheFirstSentence() throws {
        try fixtures.writeSkill(folder: "simple-english", scope: .personal, text: """
        ---
        name: simple-english
        description: >-
          Write technical text with the rules of ASD-STE100. Use for
          documentation, READMEs, and runbooks. Also use when the user says STE.
        ---
        """)

        let skills = SkillIndex.all(wikiRoot: fixtures.wikiRoot, homeRoot: fixtures.homeRoot)

        XCTAssertEqual(skills[0].summary, "Write technical text with the rules of ASD-STE100.")
    }

    func testLargeSkillBodyIsNotRead() throws {
        let body = String(repeating: "A long line of skill instructions.\n", count: 40_000)
        try fixtures.writeSkill(folder: "docs", scope: .wiki, text: """
        ---
        name: docs
        description: The documentation skill. It has two modes.
        ---

        \(body)
        THE-END-MARKER
        """)

        let file = fixtures.claudeDirectory(.wiki)
            .appendingPathComponent("skills/docs/SKILL.md")
        let size = try FileManager.default.attributesOfItem(atPath: file.path)[.size] as? Int ?? 0
        XCTAssertGreaterThan(size, 1_000_000)

        let frontmatter = try XCTUnwrap(FrontmatterReader.read(file))

        XCTAssertLessThanOrEqual(frontmatter.body.utf8.count, FrontmatterReader.byteLimit)
        XCTAssertFalse(frontmatter.body.contains("THE-END-MARKER"))

        let skills = SkillIndex.all(wikiRoot: fixtures.wikiRoot, homeRoot: fixtures.homeRoot)
        XCTAssertEqual(skills[0].name, "docs")
        XCTAssertEqual(skills[0].summary, "The documentation skill.")
    }

    func testMissingClaudeDirectoryGivesAnEmptyList() {
        let skills = SkillIndex.all(wikiRoot: fixtures.wikiRoot, homeRoot: fixtures.homeRoot)

        XCTAssertTrue(skills.isEmpty)
    }

    func testWikiSkillWinsOverAPersonalSkillOfTheSameName() throws {
        try fixtures.writeSkill(folder: "whip", scope: .personal, text: """
        ---
        description: The personal one.
        ---
        """)
        try fixtures.writeSkill(folder: "whip", scope: .wiki, text: """
        ---
        description: The Wiki one.
        ---
        """)

        let skills = SkillIndex.all(wikiRoot: fixtures.wikiRoot, homeRoot: fixtures.homeRoot)

        XCTAssertEqual(skills.count, 1)
        XCTAssertEqual(skills[0].scope, .wiki)
        XCTAssertEqual(skills[0].summary, "The Wiki one.")
    }

    func testSkillsSortByName() throws {
        try fixtures.writeSkill(folder: "whip", scope: .personal, text: "---\ndescription: b.\n---")
        try fixtures.writeSkill(folder: "docs", scope: .wiki, text: "---\ndescription: a.\n---")

        let skills = SkillIndex.all(wikiRoot: fixtures.wikiRoot, homeRoot: fixtures.homeRoot)

        XCTAssertEqual(skills.map(\.name), ["docs", "whip"])
    }
}
